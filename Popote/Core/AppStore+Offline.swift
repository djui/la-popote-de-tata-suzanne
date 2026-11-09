import Foundation
import Supabase

/// A write that has been applied locally and still has to reach Supabase.
enum PendingOp: Codable, Hashable, Sendable {
    case favorite(recipeId: UUID, on: Bool)
    case rating(recipeId: UUID, stars: Int?)
    case mealInsert(MealPlanEntry)
    case mealUpdate(MealPlanEntry)
    case mealDelete(id: UUID)
    case shoppingInsert(ShoppingListItem)
    case shoppingUpdate(ShoppingListItem)
    case shoppingDelete(id: UUID)
}

/// Everything persisted to disk for offline use.
struct Snapshot: Codable {
    var userId: UUID?
    var email: String?
    var recipes: [Recipe] = []
    var ingredientsByRecipe: [UUID: [RecipeIngredient]] = [:]
    var stepsByRecipe: [UUID: [RecipeStep]] = [:]
    var authorNames: [UUID: String] = [:]
    var ingredients: [Ingredient] = []
    var aisles: [IngredientCategory] = []
    var household: Household?
    var members: [HouseholdMember] = []
    var memberNames: [UUID: String] = [:]
    var categoryOrders: [HouseholdCategoryOrder] = []
    var ingredientOverrides: [HouseholdIngredientOverride] = []
    var mealPlan: [MealPlanEntry] = []
    var shoppingItems: [ShoppingListItem] = []
    var favorites: [UUID: Date] = [:]
    var myRatings: [UUID: Int] = [:]
    var profile: Profile?
    var isAdmin = false
    var termsAccepted: Bool?
    var lastSync: Date?
    var pendingOps: [PendingOp] = []
}

extension AppStore {
    static var snapshotURL: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Popote", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "snapshot.json")
    }

    func loadSnapshot() {
        guard let data = try? Data(contentsOf: Self.snapshotURL),
              let s = try? JSONDecoder.popote.decode(Snapshot.self, from: data) else { return }
        userId = s.userId; email = s.email
        recipes = s.recipes; ingredientsByRecipe = s.ingredientsByRecipe; stepsByRecipe = s.stepsByRecipe
        authorNames = s.authorNames; ingredients = s.ingredients; aisles = s.aisles
        household = s.household; members = s.members; memberNames = s.memberNames
        categoryOrders = s.categoryOrders; ingredientOverrides = s.ingredientOverrides
        mealPlan = s.mealPlan; shoppingItems = s.shoppingItems; favorites = s.favorites
        myRatings = s.myRatings; profile = s.profile; isAdmin = s.isAdmin; termsAccepted = s.termsAccepted
        lastSync = s.lastSync; pendingOps = s.pendingOps
    }

    func saveSnapshot() {
        let s = Snapshot(userId: userId, email: email, recipes: recipes, ingredientsByRecipe: ingredientsByRecipe,
                         stepsByRecipe: stepsByRecipe, authorNames: authorNames, ingredients: ingredients, aisles: aisles,
                         household: household, members: members, memberNames: memberNames, categoryOrders: categoryOrders,
                         ingredientOverrides: ingredientOverrides, mealPlan: mealPlan, shoppingItems: shoppingItems,
                         favorites: favorites, myRatings: myRatings, profile: profile, isAdmin: isAdmin,
                         termsAccepted: termsAccepted, lastSync: lastSync, pendingOps: pendingOps)
        let url = Self.snapshotURL
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder.popote.encode(s) {
                try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }

    func clearData() {
        recipes = []; ingredientsByRecipe = [:]; stepsByRecipe = [:]; authorNames = [:]
        ingredients = []; aisles = []; household = nil; members = []; memberNames = [:]
        categoryOrders = []; ingredientOverrides = []; mealPlan = []; shoppingItems = []
        favorites = [:]; myRatings = [:]; profile = nil; isAdmin = false; termsAccepted = nil
        lastSync = nil; pendingOps = []
        try? FileManager.default.removeItem(at: Self.snapshotURL)
        Task { await photos.removeAll() }
        WidgetBridge.clear()
        SpotlightIndexer.removeAll()
    }

    // MARK: - Outbox

    func enqueue(_ op: PendingOp) {
        pendingOps.append(op)
        saveSnapshot()
        WidgetBridge.publish(from: self)
        guard isOnline else { return }
        Task { await flushOutbox() }
    }

    func flushOutbox() async {
        guard isOnline, authState == .signedIn else { return }
        while let op = pendingOps.first {
            do {
                try await send(op)
                pendingOps.removeFirst()
                saveSnapshot()
            } catch {
                if Self.isOfflineError(error) || Self.isCancellation(error) { return }
                // The server rejected it (RLS, constraint…): drop it so the queue doesn't block forever.
                lastError = error.localizedDescription
                pendingOps.removeFirst()
                saveSnapshot()
            }
        }
    }

    private func send(_ op: PendingOp) async throws {
        let db = client
        switch op {
        case let .favorite(recipeId, on):
            guard let uid = userId else { return }
            if on {
                struct Row: Encodable { let recipe_id: UUID; let user_id: UUID }
                try await db.from("recipe_favorites").upsert(Row(recipe_id: recipeId, user_id: uid), onConflict: "recipe_id,user_id", ignoreDuplicates: true).execute()
            } else {
                try await db.from("recipe_favorites").delete().eq("recipe_id", value: recipeId).eq("user_id", value: uid).execute()
            }
        case let .rating(recipeId, stars):
            guard let uid = userId else { return }
            if let stars {
                try await db.from("recipe_ratings").upsert(RecipeRating(recipeId: recipeId, userId: uid, stars: stars), onConflict: "recipe_id,user_id").execute()
            } else {
                try await db.from("recipe_ratings").delete().eq("recipe_id", value: recipeId).eq("user_id", value: uid).execute()
            }
        case let .mealInsert(entry):
            try await db.from("meal_plan_entries").insert(entry).execute()
        case let .mealUpdate(entry):
            try await db.from("meal_plan_entries").update(entry).eq("id", value: entry.id).execute()
        case let .mealDelete(id):
            try await db.from("meal_plan_entries").delete().eq("id", value: id).execute()
        case let .shoppingInsert(item):
            try await db.from("shopping_list_items").insert(ShoppingInsert(item)).execute()
        case let .shoppingUpdate(item):
            try await db.from("shopping_list_items").update(ShoppingInsert(item)).eq("id", value: item.id).execute()
        case let .shoppingDelete(id):
            try await db.from("shopping_list_items").delete().eq("id", value: id).execute()
        }
    }

    /// Keeps local, not-yet-synced menu changes visible after a pull.
    func mergePending(_ remote: [MealPlanEntry]) -> [MealPlanEntry] {
        var byId = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for op in pendingOps {
            switch op {
            case let .mealInsert(e), let .mealUpdate(e): byId[e.id] = e
            case let .mealDelete(id): byId[id] = nil
            default: break
            }
        }
        return byId.values.sorted { ($0.date, $0.mealType.rawValue, $0.position ?? 0) < ($1.date, $1.mealType.rawValue, $1.position ?? 0) }
    }

    func mergePendingShopping(_ remote: [ShoppingListItem]) -> [ShoppingListItem] {
        var byId = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var order = remote.map(\.id)
        for op in pendingOps {
            switch op {
            case let .shoppingInsert(i), let .shoppingUpdate(i):
                if byId[i.id] == nil { order.append(i.id) }
                byId[i.id] = i
            case let .shoppingDelete(id): byId[id] = nil
            default: break
            }
        }
        return order.compactMap { byId[$0] }
    }

    // MARK: - Optimistic mutations used by the screens

    func isFavorite(_ recipeId: UUID) -> Bool { favorites[recipeId] != nil }

    func toggleFavorite(_ recipeId: UUID) {
        let on = !isFavorite(recipeId)
        favorites[recipeId] = on ? .now : nil
        enqueue(.favorite(recipeId: recipeId, on: on))
    }

    func setRating(_ recipeId: UUID, stars: Int?) {
        myRatings[recipeId] = stars
        enqueue(.rating(recipeId: recipeId, stars: stars))
    }

    func mealEntries(on date: String) -> [MealPlanEntry] {
        mealPlan.filter { $0.date == date }
    }

    @discardableResult
    func addMeal(date: Date, mealType: MealType, recipeId: UUID?, customTitle: String?, servings: Int?) -> MealPlanEntry {
        let day = LocalDay.string(date)
        let position = mealPlan.filter { $0.date == day && $0.mealType == mealType }.count
        let entry = MealPlanEntry(id: UUID(), date: day, mealType: mealType, recipeId: recipeId,
                                  customTitle: customTitle, servings: servings, position: position)
        mealPlan.append(entry)
        enqueue(.mealInsert(entry))
        return entry
    }

    func updateMeal(_ entry: MealPlanEntry) {
        guard let i = mealPlan.firstIndex(where: { $0.id == entry.id }) else { return }
        mealPlan[i] = entry
        enqueue(.mealUpdate(entry))
    }

    func deleteMeal(_ id: UUID) {
        mealPlan.removeAll { $0.id == id }
        enqueue(.mealDelete(id: id))
    }

    func shoppingItems(week: String) -> [ShoppingListItem] {
        shoppingItems.filter { $0.weekStart == week }
    }

    func addShoppingItem(_ item: ShoppingListItem) {
        shoppingItems.append(item)
        enqueue(.shoppingInsert(item))
    }

    func updateShoppingItem(_ item: ShoppingListItem) {
        guard let i = shoppingItems.firstIndex(where: { $0.id == item.id }) else { return }
        shoppingItems[i] = item
        enqueue(.shoppingUpdate(item))
    }

    func setChecked(_ id: UUID, _ checked: Bool) {
        guard var item = shoppingItems.first(where: { $0.id == id }) else { return }
        item.checked = checked
        item.checkedAt = checked ? .now : nil
        item.checkedBy = checked ? userId : nil
        updateShoppingItem(item)
    }

    func deleteShoppingItem(_ id: UUID) {
        shoppingItems.removeAll { $0.id == id }
        enqueue(.shoppingDelete(id: id))
    }

    // MARK: - Lookups

    func recipe(_ id: UUID?) -> Recipe? {
        guard let id else { return nil }
        return recipes.first { $0.id == id }
    }

    var defaultServings: Int { household?.defaultServings ?? 4 }

    func ingredient(_ id: UUID?) -> Ingredient? {
        guard let id else { return nil }
        return ingredients.first { $0.id == id }
    }

    /// Aisle for an ingredient, honouring the household's overrides.
    func aisleId(for ingredientId: UUID?) -> String? {
        guard let ingredientId else { return nil }
        if let o = ingredientOverrides.first(where: { $0.ingredientId == ingredientId }) { return o.categoryId }
        return ingredient(ingredientId)?.categoryId
    }

    /// Aisles in the household's order (falls back to the global sort order).
    var orderedAisles: [IngredientCategory] {
        let custom = Dictionary(categoryOrders.map { ($0.categoryId, $0.sortOrder) }, uniquingKeysWith: { a, _ in a })
        return aisles.sorted {
            (custom[$0.id] ?? 1000 + ($0.sortOrder ?? 0)) < (custom[$1.id] ?? 1000 + ($1.sortOrder ?? 0))
        }
    }
}

/// Columns written to `shopping_list_items` (server-owned columns like `added_by` are left out).
struct ShoppingInsert: Encodable {
    let id: UUID
    let week_start: String
    let name: String
    let quantity: Double?
    let unit: String?
    let ingredient_id: UUID?
    let item_key: String?
    let source: String?
    let source_recipe_ids: [UUID]?
    let checked: Bool
    let checked_at: Date?
    let checked_by: UUID?
    let in_stock: Bool?

    init(_ i: ShoppingListItem) {
        id = i.id; week_start = i.weekStart; name = i.name; quantity = i.quantity; unit = i.unit
        ingredient_id = i.ingredientId; item_key = i.itemKey; source = i.source
        source_recipe_ids = i.sourceRecipeIds; checked = i.checked; checked_at = i.checkedAt
        checked_by = i.checkedBy; in_stock = i.inStock
    }

    func encode(to encoder: Encoder) throws {
        enum K: String, CodingKey { case id, week_start, name, quantity, unit, ingredient_id, item_key, source, source_recipe_ids, checked, checked_at, checked_by, in_stock }
        var c = encoder.container(keyedBy: K.self)
        try c.encode(id, forKey: .id); try c.encode(week_start, forKey: .week_start); try c.encode(name, forKey: .name)
        try c.encode(quantity, forKey: .quantity); try c.encode(unit, forKey: .unit); try c.encode(ingredient_id, forKey: .ingredient_id)
        try c.encode(item_key, forKey: .item_key); try c.encode(source, forKey: .source)
        try c.encode(source_recipe_ids ?? [], forKey: .source_recipe_ids); try c.encode(checked, forKey: .checked)
        try c.encode(checked_at, forKey: .checked_at); try c.encode(checked_by, forKey: .checked_by)
        try c.encode(in_stock ?? false, forKey: .in_stock)
    }
}

extension JSONEncoder {
    static let popote: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let popote: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
