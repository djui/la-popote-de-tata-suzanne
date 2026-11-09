import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Indexes recipes in Spotlight.
@MainActor
enum SpotlightIndexer {
    nonisolated static let activityType = "net.dauernheim.popote.recipe"
    nonisolated static let domain = "recipes"
    private static let fingerprintsKey = "spotlight.fingerprints"
    private static var task: Task<Void, Never>?

    /// What a recipe's index entry depends on; unchanged recipes are skipped.
    struct Item: Sendable {
        var id: UUID
        var title: String
        var categories: [String]
        var ingredients: [String]
        var photoPath: String?

        var fingerprint: String {
            ([title, photoPath ?? "-"] + categories + ingredients).joined(separator: "\u{1F}")
        }
    }

    static func index(recipes: [Recipe], store: AppStore) {
        let isFullSync = recipes.count == store.recipes.count
        let items = recipes.map { r in
            Item(id: r.id, title: r.title,
                 categories: r.recipeCategories.map(\.label),
                 ingredients: (store.ingredientsByRecipe[r.id] ?? []).map(\.name),
                 photoPath: r.listPhotoPath)
        }
        let photos = store.photos
        let previous = task
        task = Task {
            await previous?.value
            var fingerprints = UserDefaults.standard.dictionary(forKey: fingerprintsKey) as? [String: String] ?? [:]
            if isFullSync {
                let current = Set(items.map(\.id.uuidString))
                let stale = fingerprints.keys.filter { !current.contains($0) }
                if !stale.isEmpty {
                    try? await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: stale)
                    stale.forEach { fingerprints[$0] = nil }
                }
            }
            var searchable: [CSSearchableItem] = []
            for item in items {
                if Task.isCancelled { return }
                var thumb: Data?
                if let path = item.photoPath, let data = await photos.data(for: path) {
                    thumb = await Task.detached(priority: .utility) { WidgetBridge.downscaledJPEG(data, maxPixels: 180) }.value
                }
                // Only mark the photo as indexed once it is actually on disk.
                let fp = item.fingerprint + (thumb == nil ? "|nothumb" : "")
                if fingerprints[item.id.uuidString] == fp { continue }
                fingerprints[item.id.uuidString] = fp
                searchable.append(makeItem(item, thumbnail: thumb))
            }
            if !searchable.isEmpty {
                for chunk in stride(from: 0, to: searchable.count, by: 200) {
                    let slice = Array(searchable[chunk..<min(chunk + 200, searchable.count)])
                    try? await CSSearchableIndex.default().indexSearchableItems(slice)
                }
                PopoteShortcuts.updateAppShortcutParameters()
            }
            UserDefaults.standard.set(fingerprints, forKey: fingerprintsKey)
        }
    }

    static func remove(recipeId: UUID) {
        var fingerprints = UserDefaults.standard.dictionary(forKey: fingerprintsKey) as? [String: String] ?? [:]
        fingerprints[recipeId.uuidString] = nil
        UserDefaults.standard.set(fingerprints, forKey: fingerprintsKey)
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [recipeId.uuidString]) { _ in }
    }

    static func removeAll() {
        task?.cancel()
        task = nil
        UserDefaults.standard.removeObject(forKey: fingerprintsKey)
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
    }

    nonisolated static func recipeId(from activity: NSUserActivity) -> UUID? {
        let raw: Any?
        switch activity.activityType {
        case CSSearchableItemActionType:
            raw = activity.userInfo?[CSSearchableItemActivityIdentifier]
        case activityType:
            raw = activity.userInfo?["recipeId"] ?? activity.targetContentIdentifier
        default:
            raw = nil
        }
        if let id = raw as? UUID { return id }
        if let s = raw as? String { return UUID(uuidString: s) }
        return nil
    }

    /// The activity a recipe screen can advertise (Handoff, Siri suggestions).
    static func userActivity(for recipe: Recipe) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = recipe.title
        activity.userInfo = ["recipeId": recipe.id.uuidString]
        activity.targetContentIdentifier = recipe.id.uuidString
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = recipe.id.uuidString
        activity.webpageURL = Backend.webURL.appending(path: "recettes/\(recipe.id.uuidString)")
        return activity
    }

    private static func makeItem(_ item: Item, thumbnail: Data?) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = item.title
        attributes.displayName = item.title
        var description = item.categories.joined(separator: " · ")
        if !item.ingredients.isEmpty {
            description += (description.isEmpty ? "" : "\n") + item.ingredients.joined(separator: ", ")
        }
        attributes.contentDescription = description
        attributes.keywords = item.categories + item.ingredients
        attributes.thumbnailData = thumbnail
        attributes.contentURL = URL(string: "popote://recette/\(item.id.uuidString)")
        let searchable = CSSearchableItem(uniqueIdentifier: item.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
        searchable.expirationDate = .distantFuture
        return searchable
    }
}
