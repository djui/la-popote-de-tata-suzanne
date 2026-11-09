import Foundation
import Supabase

/// Row returned by `my_invitations()`.
struct IncomingInvitation: Decodable, Hashable, Identifiable, Sendable {
    var code: String
    var inviter: String?
    var householdName: String?
    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code, inviter
        case householdName = "household_name"
    }
}

/// Row returned by `get_invitation(_code)`.
struct InvitationInfo: Decodable, Hashable, Sendable {
    var householdName: String?
    var inviter: String?
    var alreadyMember: Bool?
    var expired: Bool?

    enum CodingKeys: String, CodingKey {
        case inviter, expired
        case householdName = "household_name"
        case alreadyMember = "already_member"
    }
}

/// Profile, household and account operations (online only, except where noted).
extension AppStore {
    var isHouseholdOwner: Bool {
        members.first { $0.userId == userId }?.role == "owner"
    }

    func memberName(_ member: HouseholdMember) -> String {
        memberNames[member.userId] ?? member.profiles?.firstName ?? "?"
    }

    // MARK: First name

    func updateFirstName(_ name: String) async throws {
        guard let userId else { return }
        struct Row: Encodable { let first_name: String }
        try await client.from("profiles").update(Row(first_name: name)).eq("id", value: userId).execute()
        if profile == nil { profile = Profile(id: userId) }
        profile?.firstName = name
        memberNames[userId] = name
        authorNames[userId] = name
        saveSnapshot()
    }

    // MARK: Default servings

    /// Optimistic: updates the mirror at once, the caller debounces the server write.
    func setDefaultServingsLocally(_ n: Int) {
        household?.defaultServings = min(50, max(1, n))
        saveSnapshot()
    }

    func saveDefaultServings(_ n: Int) async throws {
        guard let id = household?.id else { return }
        struct Row: Encodable { let default_servings: Int }
        try await client.from("households").update(Row(default_servings: n)).eq("id", value: id).execute()
    }

    // MARK: Invitations

    func createInvitation(email: String?) async throws -> String {
        guard let householdId = household?.id else { throw ServerFunctions.CallError.notSignedIn }
        struct Row: Encodable { let household_id: UUID; let email: String? }
        struct CodeRow: Decodable { let code: String }
        let clean = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let row: CodeRow = try await client.from("household_invitations")
            .insert(Row(household_id: householdId, email: (clean?.isEmpty ?? true) ? nil : clean))
            .select("code").single().execute().value
        return row.code
    }

    func activeInvitations() async throws -> [HouseholdInvitation] {
        let now = ISO8601DateFormatter().string(from: .now)
        return try await client.from("household_invitations")
            .select("id,code,email,expires_at")
            .gt("expires_at", value: now)
            .order("created_at", ascending: false)
            .execute().value
    }

    func revokeInvitation(_ id: UUID) async throws {
        try await client.from("household_invitations").delete().eq("id", value: id).execute()
    }

    func myInvitations() async throws -> [IncomingInvitation] {
        try await client.rpc("my_invitations").execute().value
    }

    func invitationInfo(code: String) async throws -> InvitationInfo? {
        let rows: [InvitationInfo] = try await client.rpc("get_invitation", params: ["_code": code]).execute().value
        return rows.first
    }

    func acceptInvitation(code: String) async throws {
        try await client.rpc("accept_invitation", params: ["_code": code]).execute()
        await refresh()
    }

    func removeMember(_ userId: UUID) async throws {
        try await client.rpc("remove_household_member", params: ["_user_id": userId.uuidString]).execute()
        members.removeAll { $0.userId == userId }
        await refresh()
    }

    func leaveHousehold() async throws {
        try await client.rpc("leave_household").execute()
        await refresh()
    }

    // MARK: Aisle order ("Mon magasin")

    func saveAisleOrder(_ ordered: [IngredientCategory]) async throws {
        let previous = categoryOrders
        let hid = household?.id
        if let hid {
            categoryOrders = ordered.enumerated().map { HouseholdCategoryOrder(householdId: hid, categoryId: $0.element.id, sortOrder: $0.offset) }
            saveSnapshot()
        }
        struct Row: Encodable {
            let household_id: UUID?
            let category_id: String
            let sort_order: Int
        }
        do {
            let rows = ordered.enumerated().map { Row(household_id: hid, category_id: $0.element.id, sort_order: $0.offset) }
            try await client.from("household_category_orders").upsert(rows, onConflict: "household_id,category_id").execute()
        } catch {
            categoryOrders = previous
            saveSnapshot()
            throw error
        }
    }

    func resetAisleOrder() async throws {
        if let hid = household?.id {
            try await client.from("household_category_orders").delete().eq("household_id", value: hid).execute()
        } else {
            try await client.from("household_category_orders").delete().neq("category_id", value: "").execute()
        }
        categoryOrders = []
        saveSnapshot()
    }

    // MARK: Mes données

    /// `mes-recettes-popote.json`, same shape as the website's export.
    func exportMyRecipes() async throws -> URL {
        guard let userId else { throw ServerFunctions.CallError.notSignedIn }
        let rows: [Any]
        if isOnline {
            let data = try await client.from("recipes")
                .select("*,recipe_ingredients(*),recipe_steps(*)")
                .eq("created_by", value: userId)
                .execute().data
            rows = (try JSONSerialization.jsonObject(with: data) as? [Any]) ?? []
        } else {
            rows = try localExportRows(userId: userId)
        }
        let stripped = rows.compactMap { $0 as? [String: Any] }.map { row in
            row.filter { !["user_id", "created_by", "source_image_urls", "photo_url", "photo_thumb_url"].contains($0.key) }
        }
        let payload: [String: Any] = [
            "application": "La Popote de Tata Suzanne",
            "exported_at": ISO8601DateFormatter.withFractions.string(from: .now),
            "recipes": stripped,
        ]
        let json = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .withoutEscapingSlashes])
        let url = FileManager.default.temporaryDirectory.appending(path: "mes-recettes-popote.json")
        try json.write(to: url, options: .atomic)
        return url
    }

    /// Offline fallback built from the mirror.
    private func localExportRows(userId: UUID) throws -> [Any] {
        struct Row: Encodable {
            let recipe: Recipe
            let ingredients: [RecipeIngredient]
            let steps: [RecipeStep]
            func encode(to encoder: Encoder) throws {
                try recipe.encode(to: encoder)
                enum K: String, CodingKey { case recipe_ingredients, recipe_steps }
                var c = encoder.container(keyedBy: K.self)
                try c.encode(ingredients, forKey: .recipe_ingredients)
                try c.encode(steps, forKey: .recipe_steps)
            }
        }
        let mine = recipes.filter { $0.createdBy == userId }.map {
            Row(recipe: $0, ingredients: ingredientsByRecipe[$0.id] ?? [], steps: stepsByRecipe[$0.id] ?? [])
        }
        let data = try JSONEncoder.popote.encode(mine)
        return (try JSONSerialization.jsonObject(with: data) as? [Any]) ?? []
    }

    func deleteAccount(keepRecipes: Bool) async throws {
        _ = try await serverFunctions.call(ServerFunctions.ID.deleteAccount,
                                           data: ["confirmation": "SUPPRIMER", "keepRecipes": keepRecipes] as [String: Any])
        await signOut()
    }
}

extension ISO8601DateFormatter {
    static var withFractions: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }
}
