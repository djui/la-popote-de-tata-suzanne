import CryptoKit
import Foundation
import SwiftUI
import UIKit

/// Stores recipe photos on disk (Application Support, so iOS doesn't purge them), keyed by storage path.
actor PhotoCache {
    private let directory: URL
    private var memory = NSCache<NSString, UIImage>()

    init() {
        directory = URL.applicationSupportDirectory.appending(path: "Popote/Photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var dir = directory
        try? dir.setResourceValues(values)
        memory.countLimit = 120
    }

    private func fileURL(_ path: String) -> URL {
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: digest)
    }

    func has(_ path: String) -> Bool { FileManager.default.fileExists(atPath: fileURL(path).path) }

    func missing(_ paths: [String]) -> [String] { Array(Set(paths)).filter { !has($0) } }

    func data(for path: String) -> Data? { try? Data(contentsOf: fileURL(path)) }

    func store(_ data: Data, for path: String) {
        try? data.write(to: fileURL(path), options: .atomic)
    }

    func image(for path: String) -> UIImage? {
        if let cached = memory.object(forKey: path as NSString) { return cached }
        guard let data = data(for: path), let image = UIImage(data: data)?.preparingForDisplay() ?? UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: path as NSString)
        return image
    }

    func cache(_ image: UIImage, for path: String) { memory.setObject(image, forKey: path as NSString) }

    func diskUsage() -> (files: Int, bytes: Int64) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = urls.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return (urls.count, bytes)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.removeAllObjects()
    }
}

/// Shows a recipe photo from the offline cache. Falls back to the category tile like the website.
struct RecipePhotoView: View {
    @Environment(AppStore.self) private var store
    let path: String?
    var category: RecipeCategory = .plat
    var iconSize: CGFloat = 34

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Rectangle().fill(Palette.tileGradient)
                if path == nil {
                    Image(systemName: category.symbol)
                        .font(.system(size: iconSize, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.3), value: image != nil)
        .task(id: TaskKey(path: path, progress: store.photoProgress.done)) {
            guard image == nil, let path else { return }
            if let img = await store.photos.image(for: path) {
                image = img
            } else if let data = await store.photoData(path), let img = UIImage(data: data) {
                await store.photos.cache(img, for: path)
                image = img
            }
        }
        .accessibilityHidden(true)
    }

    private struct TaskKey: Hashable { let path: String?; let progress: Int }
}
