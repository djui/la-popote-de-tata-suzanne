import Foundation

/// Data shared between the app and the widget extension through the App Group container.
struct WidgetSnapshot: Codable, Sendable {
    struct Meal: Codable, Sendable, Hashable {
        var date: String
        var mealType: String
        var title: String
        var recipeId: UUID?
        var servings: Int?
        /// File name of a small JPEG thumbnail stored next to the snapshot.
        var thumbnailFile: String?
    }

    var meals: [Meal]
    var updatedAt: Date

    static let appGroup = "group.net.dauernheim.popote"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var fileURL: URL? { containerURL?.appending(path: "widget-snapshot.json") }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.fileURL else { return }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(self) { try? data.write(to: url, options: .atomic) }
    }
}
