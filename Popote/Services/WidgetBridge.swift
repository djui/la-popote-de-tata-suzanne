import CryptoKit
import Foundation
import UIKit
import WidgetKit

/// Publishes upcoming meals to the widget through the App Group.
@MainActor
enum WidgetBridge {
    /// How many days ahead (today included) the widget knows about.
    nonisolated static let horizonDays = 7
    nonisolated static let thumbnailSize: CGFloat = 200

    private static var task: Task<Void, Never>?
    private static var lastPublished: [WidgetSnapshot.Meal]?

    static func publish(from store: AppStore) {
        guard store.authState == .signedIn || store.userId != nil else { return }
        let meals = meals(from: store.mealPlan, recipes: Dictionary(store.recipes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }))
        let photos = store.photos
        task?.cancel()
        task = Task {
            // Coalesce bursts of writes (every outbox enqueue calls publish).
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            var withThumbs: [WidgetSnapshot.Meal] = []
            var keep: Set<String> = []
            for (meal, path) in meals {
                var meal = meal
                if let path, let id = meal.recipeId {
                    let file = thumbnailFileName(recipeId: id, path: path)
                    if await writeThumbnail(path: path, file: file, photos: photos) {
                        meal.thumbnailFile = file
                        keep.insert(file)
                    }
                }
                withThumbs.append(meal)
            }
            guard !Task.isCancelled else { return }
            removeThumbnails(except: keep)
            if withThumbs == lastPublished, WidgetSnapshot.load() != nil { return }
            lastPublished = withThumbs
            WidgetSnapshot(meals: withThumbs, updatedAt: .now).save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static func clear() {
        task?.cancel()
        task = nil
        lastPublished = nil
        if let url = WidgetSnapshot.fileURL { try? FileManager.default.removeItem(at: url) }
        removeThumbnails(except: [])
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Today's and the next days' meals, in display order, with the photo path to thumbnail.
    nonisolated static func meals(from plan: [MealPlanEntry], recipes: [UUID: Recipe], today: Date = .now,
                                  calendar: Calendar = .current) -> [(WidgetSnapshot.Meal, String?)] {
        let f = WidgetSnapshot.dayFormatter(calendar)
        let start = f.string(from: today)
        let end = f.string(from: calendar.date(byAdding: .day, value: horizonDays - 1, to: today) ?? today)
        return plan
            .filter { $0.date >= start && $0.date <= end }
            .sorted { ($0.date, WidgetSnapshot.mealOrder($0.mealType.rawValue), $0.position ?? 0) < ($1.date, WidgetSnapshot.mealOrder($1.mealType.rawValue), $1.position ?? 0) }
            .compactMap { entry in
                let recipe = entry.recipeId.flatMap { recipes[$0] }
                let custom = entry.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let title = recipe?.title ?? (custom?.isEmpty == false ? custom : nil) else { return nil }
                let meal = WidgetSnapshot.Meal(date: entry.date, mealType: entry.mealType.rawValue, title: title,
                                               recipeId: recipe?.id, servings: entry.servings, thumbnailFile: nil)
                return (meal, recipe?.listPhotoPath)
            }
    }

    // MARK: - Thumbnails

    /// Includes a digest of the storage path so a changed photo gets a new file.
    nonisolated static func thumbnailFileName(recipeId: UUID, path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "thumb-\(recipeId.uuidString)-\(digest).jpg"
    }

    private static func writeThumbnail(path: String, file: String, photos: PhotoCache) async -> Bool {
        guard let dest = WidgetSnapshot.thumbnailURL(file) else { return false }
        if FileManager.default.fileExists(atPath: dest.path) { return true }
        guard let data = await photos.data(for: path) else { return false }
        let size = thumbnailSize
        return await Task.detached(priority: .utility) {
            guard let jpeg = downscaledJPEG(data, maxPixels: size) else { return false }
            return (try? jpeg.write(to: dest, options: .atomic)) != nil
        }.value
    }

    nonisolated static func downscaledJPEG(_ data: Data, maxPixels: CGFloat, quality: CGFloat = 0.75) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, maxPixels / max(image.size.width * image.scale, image.size.height * image.scale))
        let target = CGSize(width: max(1, (image.size.width * image.scale * scale).rounded()),
                            height: max(1, (image.size.height * image.scale * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    private static func removeThumbnails(except keep: Set<String>) {
        guard let dir = WidgetSnapshot.containerURL,
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for file in files where file.hasPrefix("thumb-") && !keep.contains(file) {
            try? FileManager.default.removeItem(at: dir.appending(path: file))
        }
    }
}
