import Foundation

/// Port of the website's search normalisation (SPEC §B.1.5 `norm`, `tokens`, `matchesQuery`).
enum RecipeSearch {
    /// Lowercase, strip diacritics, œ → oe, æ → ae, then singularise (-aux → -al, trailing s/x dropped).
    static func norm(_ token: String) -> String {
        var t = token.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        if t.count > 3, t.hasSuffix("aux") {
            t = String(t.dropLast(3)) + "al"
        } else if t.count > 2, t.hasSuffix("s") || t.hasSuffix("x") {
            t = String(t.dropLast())
        }
        return t
    }

    /// Splits on anything that is not a letter or a digit, then normalises each token.
    static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map { norm(String($0)) }.filter { !$0.isEmpty }
    }

    /// Every query token must be a prefix of some token of the text. An empty query matches.
    static func matches(_ query: String, _ text: String) -> Bool {
        let q = tokens(query)
        guard !q.isEmpty else { return true }
        let t = tokens(text)
        return q.allSatisfy { qt in t.contains { $0.hasPrefix(qt) } }
    }
}

enum RecipeSortOrder: String, CaseIterable, Identifiable, Sendable {
    case recent, alpha, time, rating, favorited
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: String(localized: "Plus récentes")
        case .alpha: String(localized: "A → Z")
        case .time: String(localized: "Plus rapides")
        case .rating: String(localized: "Mieux notées")
        case .favorited: String(localized: "Ajoutées récemment aux favoris")
        }
    }
}

/// The filter state of the recipes list (SPEC §B.2.1). Kept in memory only, like the website.
struct RecipeFilterState: Equatable, Sendable {
    var q = ""
    var categories: Set<RecipeCategory> = []
    var seasons: Set<Season> = []
    var maxTime: Int?
    var tags: Set<String> = []
    var include: [String] = []
    var exclude: [String] = []
    var favorites = false
    var minRating: Double?
    var mine = false

    static let maxTimeOptions = [15, 30, 45, 60, 90]
    static let minRatingOptions: [Double] = [3, 4, 4.5]

    /// `Filtres ({count})`: everything but `q` and `mineOf`.
    var activeCount: Int {
        categories.count + seasons.count + tags.count + include.count + exclude.count
            + (maxTime != nil ? 1 : 0) + (minRating != nil ? 1 : 0) + (favorites ? 1 : 0)
    }

    /// `Tout effacer`: resets everything but keeps `q` and `mineOf`.
    mutating func clear() {
        self = RecipeFilterState(q: q, mine: mine)
    }

    func isInSeasonFilter(_ current: Season) -> Bool { seasons == [current] }

    mutating func toggleSeasonal(_ current: Season) {
        seasons = isInSeasonFilter(current) ? [] : [current]
    }

    /// `filterRecipes`: a recipe is kept only when every active criterion passes.
    func matches(_ r: Recipe, ingredientNames: [String], favorites favs: [UUID: Date], userId: UUID?) -> Bool {
        if !categories.isEmpty, !r.recipeCategories.contains(where: categories.contains) { return false }
        if favorites, favs[r.id] == nil { return false }
        if !seasons.isEmpty {
            let rs = Set(r.seasons ?? [])
            if !rs.contains(Season.touteLAnnee.rawValue), !seasons.contains(where: { rs.contains($0.rawValue) }) { return false }
        }
        if let maxTime {
            let total = (r.prepTimeMin ?? 0) + (r.cookTimeMin ?? 0)
            if total == 0 || total > maxTime { return false }
        }
        if !tags.isEmpty, !tags.isSubset(of: Set(r.tags ?? [])) { return false }
        if !include.isEmpty, !include.allSatisfy({ term in ingredientNames.contains { RecipeSearch.matches(term, $0) } }) { return false }
        if !exclude.isEmpty, exclude.contains(where: { term in ingredientNames.contains { RecipeSearch.matches(term, $0) } }) { return false }
        if let minRating, (r.ratingAvg ?? 0) < minRating { return false }
        if mine, r.createdBy == nil || r.createdBy != userId { return false }
        if !q.trimmingCharacters(in: .whitespaces).isEmpty {
            let haystack = ([r.title] + ingredientNames).joined(separator: " ")
            if !RecipeSearch.matches(q, haystack) { return false }
        }
        return true
    }

    func apply(to recipes: [Recipe], ingredientsByRecipe: [UUID: [RecipeIngredient]], favorites favs: [UUID: Date],
               userId: UUID?, sort: RecipeSortOrder) -> [Recipe] {
        let kept = recipes.filter { matches($0, ingredientNames: (ingredientsByRecipe[$0.id] ?? []).map(\.name), favorites: favs, userId: userId) }
        return RecipeSortOrder.sorted(kept, by: sort, favorites: favs)
    }
}

extension RecipeSortOrder {
    static func sorted(_ recipes: [Recipe], by order: RecipeSortOrder, favorites: [UUID: Date]) -> [Recipe] {
        // Stable: ties keep the query order (created_at desc).
        let indexed = Array(recipes.enumerated())
        func stable(_ less: (Recipe, Recipe) -> Bool?) -> [Recipe] {
            indexed.sorted { a, b in less(a.element, b.element) ?? (a.offset < b.offset) }.map(\.element)
        }
        switch order {
        case .recent:
            return stable { a, b in
                let da = a.createdAt ?? .distantPast, db = b.createdAt ?? .distantPast
                return da == db ? nil : da > db
            }
        case .alpha:
            let locale = Locale(identifier: "fr_FR")
            return stable { a, b in
                let c = a.title.compare(b.title, options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
                return c == .orderedSame ? nil : c == .orderedAscending
            }
        case .time:
            return stable { a, b in
                let ta = a.totalMinutes ?? 9999, tb = b.totalMinutes ?? 9999
                return ta == tb ? nil : ta < tb
            }
        case .rating:
            return stable { a, b in
                let ra = a.ratingAvg ?? 0, rb = b.ratingAvg ?? 0
                return ra == rb ? nil : ra > rb
            }
        case .favorited:
            return stable { a, b in
                let fa = favorites[a.id] ?? .distantPast, fb = favorites[b.id] ?? .distantPast
                return fa == fb ? nil : fa > fb
            }
        }
    }
}

enum RecipeFormat {
    /// `4,5` (one decimal, comma).
    static func rating(_ avg: Double) -> String {
        String(format: "%.1f", avg).replacingOccurrences(of: ".", with: ",")
    }

    static func recipeCount(_ n: Int) -> String {
        n == 1 ? String(localized: "1 recette") : String(localized: "\(n) recettes")
    }

    static func categories(_ r: Recipe) -> String {
        r.recipeCategories.map(\.label).joined(separator: " · ")
    }

    /// Names joined as `a, b et c`.
    static func names(_ list: [String]) -> String {
        guard list.count > 1 else { return list.first ?? "" }
        return list.dropLast().joined(separator: ", ") + " " + String(localized: "et") + " " + list.last!
    }

    static func initials(_ name: String?) -> String {
        let s = String((name ?? "?").trimmingCharacters(in: .whitespaces).prefix(2)).uppercased()
        return s.isEmpty ? "?" : s
    }

    /// Plain-text version of a recipe for the share sheet.
    static func shareText(_ r: Recipe, ingredients: [RecipeIngredient], steps: [RecipeStep]) -> String {
        var lines = [r.title, ""]
        if !ingredients.isEmpty {
            lines.append(String(localized: "Ingrédients"))
            for i in ingredients {
                let f = Quantity.formatIngredient(i.quantity, unit: i.unit, name: i.name)
                lines.append("• " + [f.qty, f.name].filter { !$0.isEmpty }.joined(separator: " "))
            }
            lines.append("")
        }
        if !steps.isEmpty {
            lines.append(String(localized: "Préparation"))
            for (n, s) in steps.enumerated() { lines.append("\(n + 1). \(s.instruction)") }
            lines.append("")
        }
        lines.append(webURL(r.id).absoluteString)
        return lines.joined(separator: "\n")
    }

    static func webURL(_ id: UUID) -> URL {
        Backend.webURL.appending(path: "recettes/\(id.uuidString.lowercased())")
    }
}
