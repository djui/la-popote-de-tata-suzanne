import Foundation

/// Indexes recipes in Spotlight.
@MainActor
enum SpotlightIndexer {
    static let activityType = "net.dauernheim.popote.recipe"
    static func index(recipes: [Recipe], store: AppStore) {}
    static func remove(recipeId: UUID) {}
    static func removeAll() {}
    static func recipeId(from activity: NSUserActivity) -> UUID? { nil }
}
