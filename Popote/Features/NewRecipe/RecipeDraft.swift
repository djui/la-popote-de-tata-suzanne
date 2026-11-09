import Foundation

/// Form values shared by the new-recipe wizard and the edit screen (SPEC §A.16).
struct RecipeDraft: Equatable, Sendable {
    var title = ""
    var categories: [RecipeCategory] = [.plat]
    var seasons: [Season] = []
    var servings: Int? = 4
    var prepTimeMin: Int?
    var cookTimeMin: Int?
    var difficulty: String?
    var tags: [String] = []
    var notes: String?
    var sourceInspiration: String?
    /// `nil` means "not set by this flow", so the column is left untouched on insert (SPEC §A.5).
    var sourceUrl: String?
    var isPrivate = false
    var photoUrl: String?
    var photoThumbUrl: String?
    var sourceImageUrls: [String] = []
    var ingredients: [DraftIngredient] = []
    var steps: [DraftStep] = []
    var rightsCertified = false

    /// `newRecipe(category)` from the website.
    static func blank(category: RecipeCategory = .plat) -> RecipeDraft {
        RecipeDraft(categories: [category])
    }

    /// Edit screen: `initial` built from the stored recipe (SPEC §A.4).
    init(recipe: Recipe, ingredients: [RecipeIngredient], steps: [RecipeStep]) {
        title = recipe.title
        categories = recipe.recipeCategories
        seasons = (recipe.seasons ?? []).compactMap(Season.init(rawValue:))
        servings = recipe.servings
        prepTimeMin = recipe.prepTimeMin
        cookTimeMin = recipe.cookTimeMin
        difficulty = recipe.difficulty
        tags = recipe.tags ?? []
        notes = recipe.notes
        sourceInspiration = recipe.sourceInspiration
        sourceUrl = recipe.sourceUrl
        isPrivate = recipe.isPrivate ?? false
        photoUrl = recipe.photoUrl
        photoThumbUrl = recipe.photoThumbUrl
        sourceImageUrls = recipe.sourceImageUrls ?? []
        self.ingredients = ingredients.sorted { $0.position < $1.position }.map {
            DraftIngredient(rawText: $0.rawText, name: $0.name, quantity: $0.quantity, unit: $0.unit,
                            shoppingCategory: $0.shoppingCategory ?? ShoppingAisle.autre.rawValue, optional: $0.optional ?? false)
        }
        self.steps = steps.sorted { $0.position < $1.position }.map { DraftStep(instruction: $0.instruction) }
    }

    init(title: String = "", categories: [RecipeCategory] = [.plat]) {
        self.title = title
        self.categories = categories
    }

    /// Merges an AI result into the base recipe (SPEC §N.5 step 5).
    func merging(_ ai: AiRecipe, chosen: RecipeCategory? = nil) -> RecipeDraft {
        var d = self
        if let t = ai.title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { d.title = t }
        d.servings = ai.servings ?? d.servings
        d.prepTimeMin = ai.prepTimeMin
        d.cookTimeMin = ai.cookTimeMin
        d.seasons = Season.allCases.filter { s in ai.suggestedSeasons.contains(s.rawValue) }
        d.tags = Self.unique(ai.suggestedTags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let base = chosen.map { [$0] } ?? d.categories
        d.categories = RecipeCategory.normalize(base.map(\.rawValue) + ai.suggestedCategories)
        if d.categories.isEmpty { d.categories = [.plat] }
        d.ingredients = ai.ingredients.map {
            DraftIngredient(rawText: $0.rawText, name: $0.name, quantity: $0.quantity, unit: $0.unit,
                            shoppingCategory: $0.shoppingCategory ?? ShoppingAisle.autre.rawValue, optional: false)
        }
        d.steps = ai.steps.map { DraftStep(instruction: $0) }
        return d
    }

    /// Keeps the first occurrence of each value, in order.
    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    // MARK: Highlighting (SPEC §A.16)

    var titleMissing: Bool { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The four key checks that trigger the warning banner.
    var hasKeyGaps: Bool { titleMissing || servings == nil || ingredients.isEmpty || steps.isEmpty }

    /// Tags as typed in the comma-separated field.
    static func parseTags(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// `Number(value.replace(',', '.'))`, empty → nil.
    static func parseNumber(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty else { return nil }
        return Double(t)
    }
}

struct DraftIngredient: Identifiable, Equatable, Sendable {
    var id = UUID()
    var rawText: String?
    var name = ""
    var quantity: Double?
    var unit: String?
    var shoppingCategory = ShoppingAisle.autre.rawValue
    var optional = false

    /// A quantity that the AI should have read: `raw_text` has a digit but `quantity` is empty.
    var quantityMissing: Bool {
        quantity == nil && (rawText?.contains(where: \.isNumber) ?? false)
    }

    var nameMissing: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Unit options for this row: the standard list, plus an unknown unit appended (SPEC §A.6).
    var unitOptions: [String] {
        guard let unit, !unit.isEmpty, !IngredientUnit.all.contains(unit) else { return IngredientUnit.all }
        return IngredientUnit.all + [unit]
    }
}

struct DraftStep: Identifiable, Equatable, Sendable {
    var id = UUID()
    var instruction = ""
}

// MARK: - AI result (SPEC §N.6)

struct AiDetection: Equatable, Sendable {
    var imageIndex: Int
    /// `[ymin, xmin, ymax, xmax]`, normalised 0–1000.
    var box: [Double]
    var isMain: Bool
    var confidence: Double

    init(imageIndex: Int, box: [Double], isMain: Bool = false, confidence: Double = 0) {
        self.imageIndex = imageIndex; self.box = box; self.isMain = isMain; self.confidence = confidence
    }

    init?(json: Any) {
        guard let d = json as? [String: Any] else { return nil }
        let box = (d["box_2d"] as? [Any])?.compactMap(AiJSON.double) ?? []
        guard box.count == 4 else { return nil }
        imageIndex = AiJSON.int(d["image_index"]) ?? 0
        self.box = box
        isMain = d["is_main"] as? Bool ?? false
        confidence = AiJSON.double(d["confidence"]) ?? 0
    }

    /// `is_main`, else the highest confidence.
    static func main(_ list: [AiDetection]) -> AiDetection? {
        list.first(where: \.isMain) ?? list.max { $0.confidence < $1.confidence }
    }
}

struct AiIngredient: Equatable, Sendable {
    var rawText: String?
    var name: String
    var quantity: Double?
    var unit: String?
    var shoppingCategory: String?
}

struct AiRecipe: Equatable, Sendable {
    var title: String?
    var servings: Int?
    var prepTimeMin: Int?
    var cookTimeMin: Int?
    var ingredients: [AiIngredient] = []
    var steps: [String] = []
    var suggestedSeasons: [String] = []
    var suggestedTags: [String] = []
    var suggestedCategories: [String] = []
    var dishPhotos: [AiDetection] = []

    init?(json: Any?) {
        guard let d = json as? [String: Any] else { return nil }
        title = AiJSON.string(d["title"])
        servings = AiJSON.int(d["servings"])
        prepTimeMin = AiJSON.int(d["prep_time_min"])
        cookTimeMin = AiJSON.int(d["cook_time_min"])
        ingredients = (d["ingredients"] as? [Any] ?? []).compactMap { item in
            guard let i = item as? [String: Any] else { return nil }
            let raw = AiJSON.string(i["raw_text"])
            let name = AiJSON.string(i["name"]) ?? raw ?? ""
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let unit = AiJSON.string(i["unit"]).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            return AiIngredient(rawText: raw, name: name, quantity: AiJSON.double(i["quantity"]), unit: unit,
                                shoppingCategory: AiJSON.string(i["shopping_category"]))
        }
        steps = (d["steps"] as? [Any] ?? []).compactMap(AiJSON.string).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        suggestedSeasons = (d["suggested_seasons"] as? [Any] ?? []).compactMap(AiJSON.string)
        suggestedTags = (d["suggested_tags"] as? [Any] ?? []).compactMap(AiJSON.string)
        suggestedCategories = (d["suggested_categories"] as? [Any] ?? []).compactMap(AiJSON.string)
        dishPhotos = (d["dish_photos"] as? [Any] ?? []).compactMap(AiDetection.init(json:))
    }

    init(title: String?) { self.title = title }
}

/// Lenient readers for the Foundation values decoded from seroval.
enum AiJSON {
    static func string(_ v: Any?) -> String? {
        switch v {
        case let s as String: s
        case let n as NSNumber: n.stringValue
        default: nil
        }
    }

    static func double(_ v: Any?) -> Double? {
        switch v {
        case let n as Double: n.isFinite ? n : nil
        case let n as Int: Double(n)
        case let n as NSNumber: n.doubleValue
        case let s as String: RecipeDraft.parseNumber(s)
        default: nil
        }
    }

    static func int(_ v: Any?) -> Int? {
        guard let d = double(v), d.isFinite else { return nil }
        return Int(d.rounded())
    }
}

// MARK: - Title similarity (SPEC §A.13 `similarity`)

enum TitleSimilarity {
    static let duplicateThreshold = 0.75

    /// `norm`: lowercase, strip diacritics, œ→oe, æ→ae, simple singularisation.
    static func norm(_ word: String) -> String {
        var w = word.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
        w = w.applyingTransform(.stripDiacritics, reverse: false) ?? w
        if w.count > 3, w.hasSuffix("aux") {
            w = String(w.dropLast(3)) + "al"
        } else if w.count > 2, w.hasSuffix("s") || w.hasSuffix("x") {
            w = String(w.dropLast())
        }
        return w
    }

    /// `tokens(s)`: split on anything that isn't a letter or digit, then `norm`.
    static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map { norm(String($0)) }
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        func prep(_ s: String) -> String {
            tokens(s).filter { $0.count > 2 || $0.contains(where: \.isNumber) }.joined(separator: " ")
        }
        let x = prep(a), y = prep(b)
        if x.isEmpty || y.isEmpty { return 0 }
        if x == y { return 1 }
        let bx = bigrams(x), by = bigrams(y)
        guard !bx.isEmpty, !by.isEmpty else { return 0 }
        var counts: [String: Int] = [:]
        for g in bx { counts[g, default: 0] += 1 }
        var common = 0
        for g in by where (counts[g] ?? 0) > 0 {
            counts[g]! -= 1
            common += 1
        }
        return 2 * Double(common) / Double(bx.count + by.count)
    }

    private static func bigrams(_ s: String) -> [String] {
        let chars = Array(s)
        guard chars.count >= 2 else { return [] }
        return (0..<(chars.count - 1)).map { String(chars[$0...$0 + 1]) }
    }
}

// MARK: - URL safety (SPEC §N.4 `isSafeUrl`)

enum URLSafety {
    static func isSafe(_ string: String) -> Bool {
        guard let comps = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = comps.scheme?.lowercased(), scheme == "http" || scheme == "https",
              comps.user == nil, comps.password == nil,
              var host = comps.host?.lowercased(), !host.isEmpty else { return false }
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }

        if host.contains(":") { return isSafeIPv6(host) }
        if let octets = ipv4(host) { return isSafeIPv4(octets) }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".internal") { return false }
        if !host.contains(".") { return false }
        // Numeric-looking hosts that aren't valid dotted IPv4 (e.g. "2130706433") are refused too.
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
        return true
    }

    static func ipv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let nums = parts.compactMap { p -> Int? in
            guard !p.isEmpty, p.count <= 3, p.allSatisfy(\.isNumber) else { return nil }
            return Int(p)
        }
        guard nums.count == 4, nums.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return nums
    }

    static func isSafeIPv4(_ o: [Int]) -> Bool {
        let (a, b) = (o[0], o[1])
        if a == 10 || a == 127 || a == 0 || a >= 224 { return false }
        if a == 169 && b == 254 { return false }
        if a == 172 && (16...31).contains(b) { return false }
        if a == 192 && b == 168 { return false }
        if a == 100 && (64...127).contains(b) { return false }
        return true
    }

    static func isSafeIPv6(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "::1" || h == "::" { return false }
        if h.hasPrefix("fc") || h.hasPrefix("fd") { return false }
        if ["fe8", "fe9", "fea", "feb"].contains(where: h.hasPrefix) { return false }
        if h.hasPrefix("::ffff:") { return false }
        return true
    }

    /// First http(s) URL in a pasted text.
    static func extractURL(from text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return url.absoluteString
            }
        }
        return nil
    }

    /// A pasted text that is essentially one URL: one http(s) URL plus at most 40 other
    /// non-punctuation characters (SPEC §N.3 step 1).
    static func singleURL(in text: String) -> String? {
        let pattern = #"https?://[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count == 1, let m = matches.first else { return nil }
        let url = ns.substring(with: m.range)
        let rest = ns.replacingCharacters(in: m.range, with: "")
        let meaningful = rest.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.symbols.contains($0)
        }
        return meaningful.count <= 40 ? url : nil
    }
}

// MARK: - Quick ingredient parser (SPEC §A.13 `parseQuick`), used for "paste a list"

enum IngredientLineParser {
    static func parse(_ line: String) -> DraftIngredient? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bullets and list markers.
        while let first = text.first, "-•*·–—".contains(first) { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
        guard !text.isEmpty else { return nil }
        var item = DraftIngredient(rawText: text, name: text)
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+([.,]\d+)?)\s*(.*)$"#),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let qRange = Range(m.range(at: 1), in: text), let restRange = Range(m.range(at: 3), in: text) else { return item }
        item.quantity = RecipeDraft.parseNumber(String(text[qRange]))
        var rest = String(text[restRange])
        let units = IngredientUnit.all.sorted { $0.count > $1.count }
        for unit in units where rest.lowercased().hasPrefix(unit + " ") {
            item.unit = unit
            rest = String(rest.dropFirst(unit.count + 1))
            break
        }
        rest = rest.trimmingCharacters(in: .whitespaces)
        if rest.lowercased().hasPrefix("de ") { rest = String(rest.dropFirst(3)) }
        else if rest.lowercased().hasPrefix("d'") || rest.lowercased().hasPrefix("d’") { rest = String(rest.dropFirst(2)) }
        item.name = rest.trimmingCharacters(in: .whitespaces)
        return item.name.isEmpty ? nil : item
    }

    static func parseList(_ text: String) -> [DraftIngredient] {
        text.split(whereSeparator: \.isNewline).compactMap { parse(String($0)) }
    }
}
