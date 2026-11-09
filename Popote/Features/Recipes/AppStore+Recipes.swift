import Foundation
import Supabase

/// Online-only recipe actions (delete, report, favourite counters). See SPEC §A.5, §A.12, §A.13.
extension AppStore {
    func canEdit(_ recipe: Recipe) -> Bool {
        guard let userId else { return false }
        return recipe.createdBy == userId || isAdmin
    }

    /// `deleteRecipe(id)`: read the photo paths, delete the row, then remove the storage objects (errors swallowed).
    func deleteRecipe(_ id: UUID) async throws {
        struct Paths: Decodable { let photo_url: String?; let photo_thumb_url: String?; let source_image_urls: [String]? }
        let local = recipe(id)
        let paths: Paths? = try? await client.from("recipes")
            .select("photo_url,photo_thumb_url,source_image_urls").eq("id", value: id).single().execute().value
        try await client.from("recipes").delete().eq("id", value: id).execute()
        let files = [paths?.photo_url ?? local?.photoUrl, paths?.photo_thumb_url ?? local?.photoThumbUrl].compactMap { $0 }
            + (paths?.source_image_urls ?? local?.sourceImageUrls ?? [])
        if !files.isEmpty {
            _ = try? await client.storage.from(Backend.photoBucket).remove(paths: files)
        }
        removeRecipeLocally(id)
    }

    func reportRecipe(_ recipe: Recipe, reason: ReportReason, details: String) async throws {
        struct Row: Encodable { let recipe_id: UUID; let reason: String; let details: String; let user_id: UUID?; let recipe_title: String }
        let trimmed = String(details.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        try await client.from("content_reports")
            .insert(Row(recipe_id: recipe.id, reason: reason.rawValue, details: trimmed, user_id: userId, recipe_title: recipe.title))
            .execute()
    }

    func favoriteCount(_ id: UUID) async throws -> Int {
        try await client.rpc("recipe_favorite_count", params: ["_recipe_id": id.uuidString]).execute().value
    }

    func favoriteNames(_ id: UUID) async throws -> [String] {
        try await client.rpc("recipe_favorite_names", params: ["_recipe_id": id.uuidString]).execute().value
    }
}
