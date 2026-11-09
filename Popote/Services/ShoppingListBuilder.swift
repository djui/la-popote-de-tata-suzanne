import Foundation

/// Pure shopping-list logic ported from the website's `ingredients-*.js` and `courses-*.js`
/// (docs/spec/SPEC.md §A.13 and Part B §5). No UI or store dependency: it only takes arrays.
enum ShoppingListBuilder {
    // MARK: - Text normalisation (`norm`, `tokens`, `key`, `matches`)

    /// `norm(token)`: lowercase, strip diacritics, œ→oe, æ→ae, then a naive French singular.
    static func norm(_ word: String) -> String {
        var w = word.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        if w.count > 3, w.hasSuffix("aux") {
            w = String(w.dropLast(3)) + "al"
        } else if w.count > 2, w.hasSuffix("s") || w.hasSuffix("x") {
            w = String(w.dropLast())
        }
        return w
    }

    /// Splits on anything that is not a letter or a digit, then normalises each token.
    static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map { norm(String($0)) }
    }

    /// `key(s)`: the normalised tokens joined with spaces.
    static func key(_ s: String) -> String { tokens(s).joined(separator: " ") }

    /// Every query token must be a prefix of some text token. An empty query matches everything.
    static func matches(_ query: String, _ text: String) -> Bool {
        let q = tokens(query)
        guard !q.isEmpty else { return true }
        let t = tokens(text)
        return q.allSatisfy { qt in t.contains { $0.hasPrefix(qt) } }
    }

    // MARK: - Pantry staples

    private static let stapleNames: Set<String> = [
        "eau", "eau froide", "eau chaude", "eau tiède", "sel", "gros sel", "sel fin", "fleur de sel",
        "poivre", "poivre noir", "poivre blanc", "sel et poivre", "sel poivre",
    ].reduce(into: []) { $0.insert(fold($1)) }

    private static func fold(_ s: String) -> String {
        s.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Water, salt and pepper variants, and anything starting with `huile` or `vinaigre`, are never shopped.
    static func isStaple(_ name: String) -> Bool {
        let n = fold(name)
        return stapleNames.contains(n) || n.hasPrefix("huile") || n.hasPrefix("vinaigre")
    }

    // MARK: - Units

    enum UnitFamily: Hashable, Sendable {
        case mass, volume, other(String)

        /// The family as it appears in `item_key` (`mass`/`vol` for the converted families, else the unit).
        var keyPart: String {
            switch self {
            case .mass: "mass"
            case .volume: "vol"
            case let .other(u): u
            }
        }
    }

    static let countableUnits: Set<String> = ["pièce", "gousse", "tranche", "sachet", "botte", "verre", "pincée"]
    static let spoonUnits: Set<String> = ["c. à soupe", "c. à café"]

    /// Unit family and the factor that converts to its base unit (g, ml). No unit means `pièce`.
    static func unitFamily(_ unit: String?) -> (family: UnitFamily, factor: Double) {
        let u = (unit ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        switch u {
        case "g": return (.mass, 1)
        case "kg": return (.mass, 1000)
        case "ml": return (.volume, 1)
        case "cl": return (.volume, 10)
        case "l": return (.volume, 1000)
        case "": return (.other("pièce"), 1)
        default: return (.other(u), 1)
        }
    }

    /// Rounds an aggregated total (in g or ml for mass/volume) back to a display quantity and unit.
    static func round(_ total: Double, family: UnitFamily) -> (quantity: Double, unit: String?) {
        // Steps are expressed as "per unit" counts where possible to avoid binary noise (1.25 / 0.1 ≠ 12.5).
        func nearest(_ x: Double, _ step: Double) -> Double { (x / step).rounded() * step }
        func ceilTo(_ x: Double, perUnit n: Double) -> Double { (x * n - 1e-9).rounded(.up) / n }
        switch family {
        case .mass:
            if total >= 1000 { return ((total / 100).rounded() / 10, "kg") }
            if total >= 250 { return (nearest(total, 50), "g") }
            if total >= 50 { return (nearest(total, 10), "g") }
            return (max(5, nearest(total, 5)), "g")
        case .volume:
            if total >= 1000 { return ((total / 100).rounded() / 10, "l") }
            if total >= 100 { return (nearest(total / 10, 5), "cl") }
            return (max(5, nearest(total, 5)), "ml")
        case let .other(u):
            let unit: String? = u  // the website keeps "pièce" as the stored unit
            if spoonUnits.contains(u) { return (max(0.5, ceilTo(total, perUnit: 2)), unit) }
            if countableUnits.contains(u) { return (max(1, (total - 0.05).rounded(.up)), unit) }
            return (ceilTo(total, perUnit: 10), unit)
        }
    }

    // MARK: - Menu → rows

    /// One ingredient line of one menu entry.
    struct MenuRow: Hashable, Sendable {
        var recipeId: UUID
        var recipeServings: Int?
        var mealServings: Int?
        var name: String
        var quantity: Double?
        var unit: String?
        var ingredientId: UUID?
    }

    /// Flattens the menu entries in `[from, to]` (inclusive, `YYYY-MM-DD`) into ingredient rows.
    /// Free dishes (no recipe) are skipped.
    static func menuRows(entries: [MealPlanEntry], from: String, to: String,
                         recipeServings: [UUID: Int?], ingredientsByRecipe: [UUID: [RecipeIngredient]]) -> [MenuRow] {
        entries
            .filter { $0.date >= from && $0.date <= to }
            .sorted { ($0.date, $0.mealType.rawValue, $0.position ?? 0) < ($1.date, $1.mealType.rawValue, $1.position ?? 0) }
            .flatMap { entry -> [MenuRow] in
                guard let rid = entry.recipeId else { return [] }
                return (ingredientsByRecipe[rid] ?? []).map {
                    MenuRow(recipeId: rid, recipeServings: recipeServings[rid] ?? nil, mealServings: entry.servings,
                            name: $0.name, quantity: $0.quantity, unit: $0.unit, ingredientId: $0.ingredientId)
                }
            }
    }

    // MARK: - Aggregation (`aggregate`)

    struct AggregatedItem: Hashable, Sendable {
        var key: String
        var name: String
        var quantity: Double?
        var unit: String?
        var ingredientId: UUID?
        var sourceRecipeIds: [UUID]
    }

    /// The website's ids are lowercase UUID strings; item keys must match theirs.
    static func idString(_ id: UUID) -> String { id.uuidString.lowercased() }

    static func aggregate(_ rows: [MenuRow], defaultServings: Int = 4) -> [AggregatedItem] {
        struct Acc {
            var name: String
            var total: Double?
            var family: UnitFamily
            var ingredientId: UUID?
            var recipeIds: [UUID]
        }
        var order: [String] = []
        var acc: [String: Acc] = [:]
        for row in rows {
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !isStaple(name) else { continue }
            let (family, unitFactor) = unitFamily(row.unit)
            let base = row.ingredientId.map(idString) ?? key(name)
            let k = base + "|" + (row.quantity != nil ? family.keyPart : "-")
            let divisor = (row.recipeServings ?? 0) > 0 ? row.recipeServings! : (defaultServings > 0 ? defaultServings : 4)
            let scale = Double(row.mealServings ?? divisor) / Double(divisor)
            let amount = row.quantity.map { $0 * scale * unitFactor }
            if var a = acc[k] {
                if let amount { a.total = (a.total ?? 0) + amount }
                if !a.recipeIds.contains(row.recipeId) { a.recipeIds.append(row.recipeId) }
                acc[k] = a
            } else {
                order.append(k)
                acc[k] = Acc(name: name, total: amount, family: family, ingredientId: row.ingredientId, recipeIds: [row.recipeId])
            }
        }
        return order.compactMap { k in
            guard let a = acc[k] else { return nil }
            var quantity: Double?
            var unit: String? = nil
            if let total = a.total {
                (quantity, unit) = round(total, family: a.family)
            }
            return AggregatedItem(key: k, name: a.name, quantity: quantity, unit: unit, ingredientId: a.ingredientId, sourceRecipeIds: a.recipeIds)
        }
    }

    // MARK: - Regeneration (`diffAuto`)

    struct Plan: Sendable {
        var inserts: [ShoppingListItem] = []
        var updates: [ShoppingListItem] = []
        var deletes: [UUID] = []
    }

    /// Diffs freshly aggregated items against the week's existing list. Only `source == "auto"` items
    /// with an `item_key` take part: same key → update (checked / in-stock state kept), new key → insert,
    /// leftover auto items → delete. Manual items are never touched.
    /// - Parameter displayName: the linked ingredient's `display_name`, used as the item name when set.
    static func plan(existing: [ShoppingListItem], computed: [AggregatedItem], weekStart: String,
                     displayName: (UUID) -> String? = { _ in nil }, newId: () -> UUID = UUID.init) -> Plan {
        var autoByKey: [String: ShoppingListItem] = [:]
        var leftovers: [UUID] = []
        for item in existing where item.source == "auto" {
            guard let k = item.itemKey, autoByKey[k] == nil else { leftovers.append(item.id); continue }
            autoByKey[k] = item
        }
        var plan = Plan()
        var used: Set<String> = []
        for c in computed {
            let name = c.ingredientId.flatMap(displayName) ?? c.name
            if var item = autoByKey[c.key] {
                used.insert(c.key)
                item.name = name
                item.quantity = c.quantity
                item.unit = c.unit
                item.ingredientId = c.ingredientId
                item.sourceRecipeIds = c.sourceRecipeIds
                plan.updates.append(item)
            } else {
                plan.inserts.append(ShoppingListItem(
                    id: newId(), weekStart: weekStart, name: name, quantity: c.quantity, unit: c.unit,
                    ingredientId: c.ingredientId, itemKey: c.key, source: "auto", sourceRecipeIds: c.sourceRecipeIds,
                    checked: false, checkedAt: nil, checkedBy: nil, inStock: false, createdAt: .now))
            }
        }
        plan.deletes = leftovers + autoByKey.filter { !used.contains($0.key) }.map(\.value.id)
        return plan
    }

    // MARK: - Quick add (`parseFreeText`)

    struct ParsedItem: Hashable, Sendable {
        var name: String
        var quantity: Double?
        var unit: String?
    }

    /// Parses `"2 kg pommes"`, `"200 g de farine"`, `"1,5 l d'eau"`, `"3 oeufs"`, `"persil"`.
    static func parseQuick(_ text: String, units: [String] = IngredientUnit.all) -> ParsedItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.wholeMatch(of: /^(\d+(?:[.,]\d+)?)\s*(.*)$/),
              let qty = Double(match.1.replacingOccurrences(of: ",", with: ".")) else {
            return ParsedItem(name: trimmed, quantity: nil, unit: nil)
        }
        var rest = String(match.2).trimmingCharacters(in: .whitespaces)
        var unit: String?
        let lower = rest.lowercased()
        for u in units.sorted(by: { $0.count > $1.count }) where lower.hasPrefix(u.lowercased() + " ") {
            unit = u
            rest = String(rest.dropFirst(u.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        let restLower = rest.lowercased()
        if restLower.hasPrefix("de ") {
            rest = String(rest.dropFirst(3))
        } else if restLower.hasPrefix("d'") || restLower.hasPrefix("d’") {
            rest = String(rest.dropFirst(2))
        }
        rest = rest.trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return ParsedItem(name: trimmed, quantity: nil, unit: nil) }
        return ParsedItem(name: rest, quantity: qty, unit: unit)
    }

    // MARK: - Ingredient search (`searchIngredients`)

    private static func candidates(_ ing: Ingredient) -> [String] {
        ([ing.name, ing.displayName].compactMap { $0 } + (ing.aliases ?? [])).map(key).filter { !$0.isEmpty }
    }

    /// The ingredient whose name, display name or alias normalises to the same key as `name`.
    static func exactIngredient(named name: String, in ingredients: [Ingredient]) -> Ingredient? {
        let k = key(name)
        guard !k.isEmpty else { return nil }
        return ingredients.first { candidates($0).contains(k) }
    }

    /// Autocomplete: exact = 3, prefix = 2, word prefix = 1; sorted by purchase frequency, score, then name.
    static func searchIngredients(_ ingredients: [Ingredient], query: String, frequency: [UUID: Int] = [:], limit: Int = 8) -> [Ingredient] {
        let q = key(query)
        guard !q.isEmpty else { return [] }
        let scored: [(Ingredient, Int)] = ingredients.compactMap { ing in
            var best = 0
            for c in candidates(ing) {
                if c == q { best = max(best, 3) }
                else if c.hasPrefix(q) { best = max(best, 2) }
                else if c.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { best = max(best, 1) }
            }
            return best > 0 ? (ing, best) : nil
        }
        return scored.sorted { a, b in
            let fa = frequency[a.0.id] ?? 0, fb = frequency[b.0.id] ?? 0
            if fa != fb { return fa > fb }
            if a.1 != b.1 { return a.1 > b.1 }
            return (a.0.displayName ?? a.0.name).compare(b.0.displayName ?? b.0.name, locale: Locale(identifier: "fr_FR")) == .orderedAscending
        }.prefix(limit).map(\.0)
    }

    // MARK: - Grouping and sharing

    struct AisleSection: Identifiable {
        var id: String?
        var name: String
        var items: [ShoppingListItem]
    }

    /// Groups items by aisle in the given order. Items without a known aisle go to the last section
    /// (`otherName`), merged with an aisle of the same name if the household has one. Empty aisles are hidden.
    static func group(_ items: [ShoppingListItem], aisles: [(id: String, name: String)], otherName: String,
                      aisleOf: (ShoppingListItem) -> String?) -> [AisleSection] {
        let known = Set(aisles.map(\.id))
        let otherAisle = aisles.first { fold($0.name) == fold(otherName) }?.id
        var buckets: [String?: [ShoppingListItem]] = [:]
        for item in items {
            var aisle = aisleOf(item)
            if let a = aisle, !known.contains(a) { aisle = nil }
            if aisle == otherAisle { aisle = nil }
            buckets[aisle, default: []].append(item)
        }
        var sections = aisles.compactMap { a -> AisleSection? in
            guard a.id != otherAisle, let list = buckets[a.id], !list.isEmpty else { return nil }
            return AisleSection(id: a.id, name: a.name, items: list)
        }
        if let rest = buckets[nil], !rest.isEmpty {
            sections.append(AisleSection(id: otherAisle, name: otherName, items: rest))
        }
        return sections
    }

    /// `name — qty unit` (or just the name).
    static func line(_ item: ShoppingListItem) -> String {
        let f = Quantity.formatIngredient(item.quantity, unit: item.unit, name: item.name)
        return f.qty.isEmpty ? f.name : "\(f.name) — \(f.qty)"
    }

    /// The plain-text list shared from the website: a title, then one uppercase block per aisle.
    static func shareText(title: String, sections: [AisleSection]) -> String {
        var out = "🛒 \(title)"
        for s in sections where !s.items.isEmpty {
            out += "\n\n\(s.name.uppercased())"
            for item in s.items { out += "\n• \(line(item))" }
        }
        return out
    }
}
