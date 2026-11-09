import Foundation
import Supabase

/// Recipe create / update / delete, exactly like the website's `recipe-data` module (SPEC §A.5).
/// These writes are online-only: callers check `store.isOnline` first.
@MainActor
struct RecipeRepository {
    let store: AppStore

    enum RepositoryError: LocalizedError {
        case rightsNotCertified, titleMissing, sourceTooLong, offline
        var errorDescription: String? {
            switch self {
            case .rightsNotCertified: String(localized: "Certifie tes droits avant de partager la recette")
            case .titleMissing: String(localized: "Le titre est obligatoire")
            case .sourceTooLong: String(localized: "La source ne doit pas dépasser 1000 caractères.")
            case .offline: String(localized: "Pas de connexion : la recette sera enregistrable dès le retour du réseau.")
            }
        }
    }

    struct SimilarRecipe: Identifiable, Hashable, Sendable {
        let id: UUID
        let title: String
    }

    private var db: SupabaseClient { store.client }

    // MARK: - Save

    /// `saveRecipe(values, id?)`. Returns the recipe id.
    @discardableResult
    func save(_ draft: RecipeDraft, id: UUID? = nil, logId: String? = nil) async throws -> UUID {
        guard store.isOnline else { throw RepositoryError.offline }
        guard draft.rightsCertified else { throw RepositoryError.rightsNotCertified }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw RepositoryError.titleMissing }
        let inspiration = draft.sourceInspiration?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let inspiration, inspiration.count > 1000 { throw RepositoryError.sourceTooLong }

        UploadSession.commit([draft.photoUrl, draft.photoThumbUrl] + draft.sourceImageUrls)

        let row = RecipeRow(draft: draft, title: title, sourceInspiration: inspiration?.isEmpty == true ? nil : inspiration)
        let recipeId: UUID
        if let id {
            struct OldPhoto: Decodable { let photo_url: String?; let photo_thumb_url: String? }
            let old: OldPhoto? = try? await db.from("recipes").select("photo_url,photo_thumb_url").eq("id", value: id).single().execute().value
            try await db.from("recipes").update(row).eq("id", value: id).execute()
            try await db.from("recipe_ingredients").delete().eq("recipe_id", value: id).execute()
            try await db.from("recipe_steps").delete().eq("recipe_id", value: id).execute()
            if let old, let oldPhoto = old.photo_url, oldPhoto != draft.photoUrl {
                let stale = [old.photo_url, old.photo_thumb_url].compactMap { $0 }
                    .filter { $0 != draft.photoUrl && $0 != draft.photoThumbUrl }
                let client = db
                Task { await ImagePipeline.remove(stale, client: client) }
            }
            recipeId = id
        } else {
            struct IdRow: Decodable { let id: UUID }
            let created: IdRow = try await db.from("recipes").insert(row).select("id").single().execute().value
            recipeId = created.id
        }

        let ingredientRows = draft.ingredients
            .map { ($0, $0.name.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.1.isEmpty }
            .enumerated()
            .map { index, pair in IngredientRow(pair.0, name: pair.1, recipeId: recipeId, position: index) }
        if !ingredientRows.isEmpty {
            struct Linked: Decodable { let ingredient_id: UUID? }
            let linked: [Linked] = try await db.from("recipe_ingredients").insert(ingredientRows).select("ingredient_id").execute().value
            let ids = linked.compactMap(\.ingredient_id)
            if !ids.isEmpty {
                let store = store
                Task { await RecipeRepository(store: store).enrichPendingIngredients(ids) }
            }
        }

        let stepRows = draft.steps
            .map { $0.instruction.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { StepRow(instruction: $1, recipe_id: recipeId, position: $0) }
        if !stepRows.isEmpty {
            try await db.from("recipe_steps").insert(stepRows).execute()
        }

        if let logId, !logId.isEmpty {
            struct LogUpdate: Encodable { let recipe_id: UUID }
            let client = db
            Task { _ = try? await client.from("ai_usage_logs").update(LogUpdate(recipe_id: recipeId)).eq("id", value: logId).execute() }
        }
        return recipeId
    }

    /// `enrichPendingIngredients(ids)`: asks the server to classify ingredients the DB just created.
    func enrichPendingIngredients(_ ids: [UUID]) async {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return }
        struct IdRow: Decodable { let id: UUID }
        guard let pending: [IdRow] = try? await db.from("ingredients").select("id")
            .in("id", values: unique.map(\.uuidString)).eq("pending_ai", value: true).execute().value,
            !pending.isEmpty else { return }
        _ = try? await store.serverFunctions.call(ServerFunctions.ID.enrichIngredients,
                                                  data: ["ids": pending.map { $0.id.uuidString.lowercased() }])
    }

    // MARK: - Delete

    /// `deleteRecipe(id)`: deletes the row, then its photos. Storage errors are swallowed.
    func delete(_ id: UUID) async throws {
        guard store.isOnline else { throw RepositoryError.offline }
        struct Paths: Decodable { let photo_url: String?; let photo_thumb_url: String?; let source_image_urls: [String]? }
        let paths: Paths? = try? await db.from("recipes").select("photo_url,photo_thumb_url,source_image_urls")
            .eq("id", value: id).single().execute().value
        try await db.from("recipes").delete().eq("id", value: id).execute()
        if let paths {
            await ImagePipeline.remove([paths.photo_url, paths.photo_thumb_url].compactMap { $0 } + (paths.source_image_urls ?? []), client: db)
        }
        store.removeRecipeLocally(id)
    }

    // MARK: - Duplicate checks

    /// Near-duplicate titles among all recipes (first 3 with similarity ≥ 0.75).
    func similarTitles(to title: String) async throws -> [SimilarRecipe] {
        struct Row: Decodable { let id: UUID; let title: String }
        let rows: [Row]
        if store.isOnline {
            rows = try await db.from("recipes").select("id,title").execute().value
        } else {
            rows = store.recipes.map { Row(id: $0.id, title: $0.title) }
        }
        return rows
            .filter { TitleSimilarity.similarity(title, $0.title) >= TitleSimilarity.duplicateThreshold }
            .prefix(3)
            .map { SimilarRecipe(id: $0.id, title: $0.title) }
    }

    /// A recipe already imported from this URL, if any.
    func existing(sourceURL url: String) async -> SimilarRecipe? {
        struct Row: Decodable { let id: UUID; let title: String }
        if let rows: [Row] = try? await db.from("recipes").select("id,title").eq("source_url", value: url).limit(1).execute().value,
           let r = rows.first {
            return SimilarRecipe(id: r.id, title: r.title)
        }
        return store.recipes.first { $0.sourceUrl == url }.map { SimilarRecipe(id: $0.id, title: $0.title) }
    }
}

// MARK: - Rows

/// Columns written to `recipes`. Every key is sent (nulls included) so an edit can clear a field;
/// `source_url` is left out when the flow never set it (SPEC §A.5 step 5).
struct RecipeRow: Encodable {
    let draft: RecipeDraft
    let title: String
    let sourceInspiration: String?

    enum K: String, CodingKey {
        case title, categories, seasons, servings, prep_time_min, cook_time_min, difficulty, tags, notes
        case source_inspiration, source_url, is_private, rights_certified_at, photo_url, photo_thumb_url, source_image_urls
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(title, forKey: .title)
        try c.encode(draft.categories.map(\.rawValue), forKey: .categories)
        try c.encode(draft.seasons.map(\.rawValue), forKey: .seasons)
        try c.encode(draft.servings, forKey: .servings)
        try c.encode(draft.prepTimeMin, forKey: .prep_time_min)
        try c.encode(draft.cookTimeMin, forKey: .cook_time_min)
        try c.encode(draft.difficulty, forKey: .difficulty)
        try c.encode(draft.tags, forKey: .tags)
        let notes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        try c.encode(notes?.isEmpty == false ? draft.notes : nil, forKey: .notes)
        try c.encode(sourceInspiration, forKey: .source_inspiration)
        if let url = draft.sourceUrl {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            try c.encode(trimmed.isEmpty ? nil : trimmed, forKey: .source_url)
        }
        try c.encode(draft.isPrivate, forKey: .is_private)
        try c.encode(ISO8601DateFormatter().string(from: .now), forKey: .rights_certified_at)
        try c.encode(draft.photoUrl, forKey: .photo_url)
        try c.encode(draft.photoThumbUrl, forKey: .photo_thumb_url)
        try c.encode(draft.sourceImageUrls, forKey: .source_image_urls)
    }
}

struct IngredientRow: Encodable {
    let recipe_id: UUID
    let position: Int
    let raw_text: String?
    let name: String
    let quantity: Double?
    let unit: String?
    let shopping_category: String
    let optional: Bool

    init(_ i: DraftIngredient, name: String, recipeId: UUID, position: Int) {
        recipe_id = recipeId
        self.position = position
        raw_text = i.rawText
        self.name = name
        quantity = i.quantity
        unit = i.unit?.isEmpty == true ? nil : i.unit
        shopping_category = i.shoppingCategory
        optional = i.optional
    }

    func encode(to encoder: Encoder) throws {
        enum K: String, CodingKey { case recipe_id, position, raw_text, name, quantity, unit, shopping_category, optional }
        var c = encoder.container(keyedBy: K.self)
        try c.encode(recipe_id, forKey: .recipe_id); try c.encode(position, forKey: .position)
        try c.encode(raw_text, forKey: .raw_text); try c.encode(name, forKey: .name)
        try c.encode(quantity, forKey: .quantity); try c.encode(unit, forKey: .unit)
        try c.encode(shopping_category, forKey: .shopping_category); try c.encode(optional, forKey: .optional)
    }
}

struct StepRow: Encodable {
    let instruction: String
    let recipe_id: UUID
    let position: Int
}
