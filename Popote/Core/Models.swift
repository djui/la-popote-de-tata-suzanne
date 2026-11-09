import Foundation

// Row types mirror the Supabase tables used by the website (see docs/spec/SPEC.md §0.3).
// Every optional column stays optional so older rows decode without surprises.

struct Recipe: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var categories: [String]?
    var seasons: [String]?
    var servings: Int?
    var prepTimeMin: Int?
    var cookTimeMin: Int?
    var difficulty: String?
    var tags: [String]?
    var notes: String?
    var sourceInspiration: String?
    var sourceUrl: String?
    var isPrivate: Bool?
    var rightsCertifiedAt: Date?
    var photoUrl: String?
    var photoThumbUrl: String?
    var sourceImageUrls: [String]?
    var createdAt: Date?
    var createdBy: UUID?
    var ratingAvg: Double?
    var ratingCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, categories, seasons, servings, difficulty, tags, notes
        case prepTimeMin = "prep_time_min"
        case cookTimeMin = "cook_time_min"
        case sourceInspiration = "source_inspiration"
        case sourceUrl = "source_url"
        case isPrivate = "is_private"
        case rightsCertifiedAt = "rights_certified_at"
        case photoUrl = "photo_url"
        case photoThumbUrl = "photo_thumb_url"
        case sourceImageUrls = "source_image_urls"
        case createdAt = "created_at"
        case createdBy = "created_by"
        case ratingAvg = "rating_avg"
        case ratingCount = "rating_count"
    }

    var totalMinutes: Int? {
        let total = (prepTimeMin ?? 0) + (cookTimeMin ?? 0)
        return total > 0 ? total : nil
    }

    var recipeCategories: [RecipeCategory] { RecipeCategory.normalize(categories ?? []) }
    var primaryCategory: RecipeCategory { recipeCategories.first ?? .plat }
    var listPhotoPath: String? { photoThumbUrl ?? photoUrl }
}

struct RecipeIngredient: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var recipeId: UUID
    var position: Int
    var rawText: String?
    var name: String
    var quantity: Double?
    var unit: String?
    var shoppingCategory: String?
    var optional: Bool?
    var ingredientId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, position, name, quantity, unit, optional
        case recipeId = "recipe_id"
        case rawText = "raw_text"
        case shoppingCategory = "shopping_category"
        case ingredientId = "ingredient_id"
    }
}

struct RecipeStep: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var recipeId: UUID
    var position: Int
    var instruction: String

    enum CodingKeys: String, CodingKey {
        case id, position, instruction
        case recipeId = "recipe_id"
    }
}

struct Ingredient: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var displayName: String?
    var pluralName: String?
    var aliases: [String]?
    var categoryId: UUID?
    var seasons: [String]?
    var verified: Bool?
    var source: String?
    var pendingAi: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, seasons, verified, source
        case displayName = "display_name"
        case pluralName = "plural_name"
        case categoryId = "category_id"
        case pendingAi = "pending_ai"
    }
}

struct IngredientCategory: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var color: String?
    var icon: String?
    var sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, color, icon
        case sortOrder = "sort_order"
    }
}

struct Household: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String?
    var defaultServings: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case defaultServings = "default_servings"
    }
}

struct HouseholdMember: Codable, Hashable, Sendable, Identifiable {
    var userId: UUID
    var role: String?
    var joinedAt: Date?
    var profiles: Profile?
    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case role, profiles
        case userId = "user_id"
        case joinedAt = "joined_at"
    }
}

struct HouseholdInvitation: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var householdId: UUID?
    var email: String?
    var code: String
    var expiresAt: Date?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email, code
        case householdId = "household_id"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

struct HouseholdCategoryOrder: Codable, Hashable, Sendable {
    var householdId: UUID
    var categoryId: UUID
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case categoryId = "category_id"
        case sortOrder = "sort_order"
    }
}

struct HouseholdIngredientOverride: Codable, Hashable, Sendable {
    var ingredientId: UUID
    var categoryId: UUID

    enum CodingKeys: String, CodingKey {
        case ingredientId = "ingredient_id"
        case categoryId = "category_id"
    }
}

enum MealType: String, Codable, CaseIterable, Sendable, Identifiable {
    case dejeuner = "déjeuner"
    case diner = "dîner"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dejeuner: String(localized: "Déjeuner")
        case .diner: String(localized: "Dîner")
        }
    }
}

struct MealPlanEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// Local calendar date as `YYYY-MM-DD`.
    var date: String
    var mealType: MealType
    var recipeId: UUID?
    var customTitle: String?
    var servings: Int?
    var position: Int?

    enum CodingKeys: String, CodingKey {
        case id, date, servings, position
        case mealType = "meal_type"
        case recipeId = "recipe_id"
        case customTitle = "custom_title"
    }
}

struct ShoppingListItem: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// Monday of the week, `YYYY-MM-DD`.
    var weekStart: String
    var name: String
    var quantity: Double?
    var unit: String?
    var ingredientId: UUID?
    var itemKey: String?
    var source: String?
    var sourceRecipeIds: [UUID]?
    var checked: Bool
    var checkedAt: Date?
    var checkedBy: UUID?
    var inStock: Bool?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, source, checked
        case weekStart = "week_start"
        case ingredientId = "ingredient_id"
        case itemKey = "item_key"
        case sourceRecipeIds = "source_recipe_ids"
        case checkedAt = "checked_at"
        case checkedBy = "checked_by"
        case inStock = "in_stock"
        case createdAt = "created_at"
    }
}

struct RecipeFavorite: Codable, Hashable, Sendable {
    var recipeId: UUID
    var userId: UUID
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case recipeId = "recipe_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct RecipeRating: Codable, Hashable, Sendable {
    var recipeId: UUID
    var userId: UUID
    var stars: Int

    enum CodingKeys: String, CodingKey {
        case stars
        case recipeId = "recipe_id"
        case userId = "user_id"
    }
}

struct RecipeComment: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var recipeId: UUID
    var userId: UUID?
    var parentId: UUID?
    var content: String
    var edited: Bool?
    var deleted: Bool?
    var createdAt: Date?
    var profiles: Profile?

    enum CodingKeys: String, CodingKey {
        case id, content, edited, deleted, profiles
        case recipeId = "recipe_id"
        case userId = "user_id"
        case parentId = "parent_id"
        case createdAt = "created_at"
    }
}

struct Profile: Codable, Hashable, Sendable {
    var id: UUID?
    var firstName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
    }
}

enum ReportReason: String, Codable, CaseIterable, Sendable, Identifiable {
    case copyright = "droits d'auteur"
    case inappropriate = "contenu inapproprié"
    case error = "erreur"
    var id: String { rawValue }
}

// MARK: - Enums from recipes-*.js

enum RecipeCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case apero = "apéro"
    case entree = "entrée"
    case soupe
    case salade
    case plat
    case pates = "pâtes"
    case quicheTarte = "quiche / tarte"
    case curry
    case legumes = "légumes"
    case sauce
    case dessert
    case gateau = "gâteau"
    case gouter = "goûter"
    case gaufreTartines = "gaufre / tartines"
    case painBrioche = "pain / brioche"
    case petitDejeuner = "petit-déjeuner"
    case boisson
    case repasDeFete = "repas de fête"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apero: String(localized: "Apéro")
        case .entree: String(localized: "Entrée")
        case .soupe: String(localized: "Soupe")
        case .salade: String(localized: "Salade")
        case .plat: String(localized: "Plat")
        case .pates: String(localized: "Pâtes")
        case .quicheTarte: String(localized: "Quiche / Tarte")
        case .curry: String(localized: "Curry")
        case .legumes: String(localized: "Légumes")
        case .sauce: String(localized: "Sauce")
        case .dessert: String(localized: "Dessert")
        case .gateau: String(localized: "Gâteau")
        case .gouter: String(localized: "Goûter")
        case .gaufreTartines: String(localized: "Gaufre / Tartines")
        case .painBrioche: String(localized: "Pain & brioche")
        case .petitDejeuner: String(localized: "Petit-déjeuner")
        case .boisson: String(localized: "Boisson")
        case .repasDeFete: String(localized: "Repas de fête")
        }
    }

    /// SF Symbols closest to the lucide icons used on the website.
    var symbol: String {
        switch self {
        case .apero: "wineglass"
        case .entree: "fork.knife"
        case .soupe: "takeoutbag.and.cup.and.straw"
        case .salade: "leaf"
        case .plat: "frying.pan"
        case .pates: "laurel.leading"
        case .quicheTarte: "chart.pie"
        case .curry: "flame"
        case .legumes: "carrot"
        case .sauce: "drop"
        case .dessert: "birthday.cake"
        case .gateau: "birthday.cake.fill"
        case .gouter: "cup.and.saucer"
        case .gaufreTartines: "square.grid.3x3"
        case .painBrioche: "basket"
        case .petitDejeuner: "sun.horizon"
        case .boisson: "mug"
        case .repasDeFete: "sparkles"
        }
    }

    /// Mirrors `normalizeCategories`: maps legacy values, drops unknown ones, keeps canonical order.
    static func normalize(_ values: [String]) -> [RecipeCategory] {
        let set = Set(values.map { $0 == "accompagnement" ? "légumes" : $0 })
        return allCases.filter { set.contains($0.rawValue) }
    }
}

enum Season: String, CaseIterable, Codable, Sendable, Identifiable {
    case printemps, ete = "été", automne, hiver, touteLAnnee = "toute l'année"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .printemps: String(localized: "Printemps")
        case .ete: String(localized: "Été")
        case .automne: String(localized: "Automne")
        case .hiver: String(localized: "Hiver")
        case .touteLAnnee: String(localized: "Toute l'année")
        }
    }

    static func current(_ date: Date = .now, calendar: Calendar = .current) -> Season {
        switch calendar.component(.month, from: date) {
        case 3...5: .printemps
        case 6...8: .ete
        case 9...11: .automne
        default: .hiver
        }
    }
}

enum ShoppingAisle: String, CaseIterable, Codable, Sendable, Identifiable {
    case fruitsLegumes = "fruits & légumes"
    case cremerie = "crèmerie"
    case boucherie
    case poissonnerie
    case epicerie = "épicerie"
    case surgeles = "surgelés"
    case boulangerie
    case boissons
    case autre
    var id: String { rawValue }
}

enum IngredientUnit {
    static let all = ["g", "kg", "ml", "cl", "l", "c. à soupe", "c. à café", "pièce", "pincée", "botte", "sachet", "tranche", "gousse", "verre"]
}

// MARK: - Date helpers

enum LocalDay {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ string: String) -> Date? { formatter.date(from: string) }

    static var mondayCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.timeZone = .current
        return c
    }

    /// Monday of the week containing `date`.
    static func weekStart(_ date: Date) -> Date {
        let cal = mondayCalendar
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return cal.startOfDay(for: start)
    }

    static func weekStartString(_ date: Date) -> String { string(weekStart(date)) }
}
