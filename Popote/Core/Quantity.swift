import Foundation

/// Port of the website's portion scaling and quantity formatting (docs/spec/SPEC.md §A.10).
enum Quantity {
    static func scale(_ q: Double?, base: Int?, target: Int) -> Double? {
        guard let q else { return nil }
        guard let base, base > 0 else { return q }
        return q * Double(target) / Double(base)
    }

    private static let fractions: [(Double, String)] = [(0.25, "¼"), (0.333, "⅓"), (0.5, "½"), (0.667, "⅔"), (0.75, "¾")]

    /// `fmtQty`: vulgar fractions below 10, integers from 100, otherwise one decimal with a comma.
    static func format(_ q: Double?) -> String {
        guard let q else { return "" }
        if q < 10 {
            let whole = q.rounded(.down)
            let frac = q - whole
            for (value, glyph) in fractions where abs(frac - value) <= 0.03 {
                return whole > 0 ? "\(Int(whole))\(glyph)" : glyph
            }
        }
        if q >= 100 { return String(Int(q.rounded())) }
        let rounded = (q * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }

    private static let pluralUnits = ["pincée": "pincées", "botte": "bottes", "sachet": "sachets",
                                      "tranche": "tranches", "gousse": "gousses", "verre": "verres"]

    /// `formatIngredient(q, unit, name)` → (quantity text, name text).
    static func formatIngredient(_ q: Double?, unit: String?, name: String) -> (qty: String, name: String) {
        var qty = format(q)
        let unit = unit?.trimmingCharacters(in: .whitespaces) ?? ""
        let many = (q ?? 0) >= 2
        if !unit.isEmpty, unit != "pièce", !qty.isEmpty {
            qty += " " + (many ? (pluralUnits[unit] ?? unit) : unit)
        }
        let displayName = (unit.isEmpty || unit == "pièce") && many ? pluralizeName(name) : name
        return (qty, displayName)
    }

    private static let invariantNames: Set<String> = ["maïs", "riz", "lait", "beurre", "sucre", "sel", "poivre", "farine", "huile", "eau", "crème", "levure", "persil", "basilic", "thym", "ciboulette", "chocolat", "miel", "vinaigre", "jus", "parmesan", "gruyère", "fromage", "râpé"]
    private static let keepWords: Set<String> = ["bio", "extra", "maison", "nature", "bis"]

    static func pluralizeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return name }
        if invariantNames.contains(trimmed.lowercased()) { return name }
        // Split at the first connector: only the head gets pluralised.
        let pattern = #"\s(de|du|des|d'|d’|à|au|aux|en|pour|sans|avec)(\s|$)"#
        var head = trimmed
        var tail = ""
        if let range = trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            head = String(trimmed[..<range.lowerBound])
            tail = String(trimmed[range.lowerBound...])
        } else if let range = trimmed.range(of: #"\s(d'|d’)"#, options: .regularExpression) {
            head = String(trimmed[..<range.lowerBound])
            tail = String(trimmed[range.lowerBound...])
        }
        let words = head.split(separator: " ", omittingEmptySubsequences: false).enumerated().map { index, word -> String in
            let w = String(word)
            if invariantNames.contains(w.lowercased()) { return w }
            if index > 0 && (keepWords.contains(w.lowercased()) || w.rangeOfCharacter(from: .decimalDigits) != nil) { return w }
            return pluralizeWord(w)
        }
        return words.joined(separator: " ") + tail
    }

    static func pluralizeWord(_ word: String) -> String {
        let lower = word.lowercased()
        if lower == "œil" || lower == "oeil" { return "yeux" }
        if lower == "ail" { return "aulx" }
        if lower.isEmpty || lower.hasSuffix("s") || lower.hasSuffix("x") || lower.hasSuffix("z") { return word }
        if ["landau", "sarrau", "bleu", "pneu"].contains(lower) { return word + "s" }
        if lower.hasSuffix("eau") || lower.hasSuffix("au") || lower.hasSuffix("eu") { return word + "x" }
        if lower.hasSuffix("al") {
            if ["bal", "carnaval", "festival", "chacal", "régal"].contains(lower) { return word + "s" }
            return String(word.dropLast(2)) + "aux"
        }
        if ["chou", "bijou", "caillou", "genou", "hibou", "joujou", "pou"].contains(lower) { return word + "x" }
        return word + "s"
    }

    /// Minutes as "1 h 05" / "45 min".
    static func duration(_ minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : String(format: "%d h %02d", h, m)
    }
}
