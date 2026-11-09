import Foundation

/// Port of the cook-mode duration detection (SPEC §A.3.1).
enum CookTimerParser {
    struct Match: Equatable, Sendable {
        /// Range of the matched text in the step instruction.
        var range: Range<String.Index>
        /// One value, or two for a range ("10 à 15 min").
        var seconds: [Int]
    }

    private static let numberWords: [String: Double] = [
        "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8,
        "neuf": 9, "dix": 10, "quinze": 15, "vingt": 20, "trente": 30, "quarante": 40, "cinquante": 50,
    ]

    private static let num = #"(\d+(?:[.,]\d+)?|une|un|deux|trois|quatre|cinq|six|sept|huit|neuf|dix|quinze|vingt|trente|quarante|cinquante)"#
    private static let unit = #"(heures?|h|minutes?|mins?|mn|secondes?|secs?|s)"#

    private static let regex: NSRegularExpression = {
        let patterns = [
            #"(une\s+demi[- ]heure)"#,                                     // 1: half an hour
            #"(\d+)\s*h\s*(\d{1,2})(?:\s*(?:minutes?|mins?|mn))?"#,        // 2-3: 2 h 30
            num + #"\s*heures?\s+et\s+demie"#,                              // 4: n heures et demie
            #"(?:entre\s+)?"# + num + #"\s*(?:à|a|-|–|et)\s*"# + num + #"\s*"# + unit, // 5-7: range
            num + #"\s*"# + unit,                                           // 8-9: single
        ]
        let body = patterns.map { "(?:\($0))" }.joined(separator: "|")
        let pattern = #"(?<![\p{L}\p{N}])(?:"# + body + #")(?![\p{L}\p{N}])"#
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static func value(_ s: String) -> Double? {
        let lower = s.lowercased()
        if let w = numberWords[lower] { return w }
        return Double(lower.replacingOccurrences(of: ",", with: "."))
    }

    private static func isWord(_ s: String) -> Bool { numberWords[s.lowercased()] != nil }

    private static func unitSeconds(_ u: String) -> Double {
        let l = u.lowercased()
        if l.hasPrefix("h") { return 3600 }
        if l.hasPrefix("mi") || l.hasPrefix("mn") { return 60 }
        return 1
    }

    private static func valid(_ v: Double) -> Int? {
        let s = Int(v.rounded())
        return s > 0 && s <= 172_800 ? s : nil
    }

    static func detect(_ text: String) -> [Match] {
        let ns = text as NSString
        var out: [Match] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            func g(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            guard let range = Range(m.range, in: text) else { continue }
            var secs: [Int] = []
            if g(1) != nil {
                secs = [1800]
            } else if let h = g(2), let mm = g(3), let hv = Double(h), let mv = Double(mm) {
                secs = [valid(hv * 3600 + mv * 60)].compactMap { $0 }
            } else if let n = g(4), let v = value(n) {
                secs = [valid(v * 3600 + 1800)].compactMap { $0 }
            } else if let a = g(5), let b = g(6), let u = g(7), let va = value(a), let vb = value(b) {
                let k = unitSeconds(u)
                if u.lowercased() == "s", isWord(b) { continue }
                secs = [valid(va * k), valid(vb * k)].compactMap { $0 }
            } else if let n = g(8), let u = g(9), let v = value(n) {
                if u.lowercased() == "s", isWord(n) { continue }
                secs = [valid(v * unitSeconds(u))].compactMap { $0 }
            }
            if !secs.isEmpty { out.append(Match(range: range, seconds: secs)) }
        }
        return out
    }

    /// `F`: `1 h 05`, `1 h`, `5 min 30`, `5 min`, `45 s`.
    static func format(_ seconds: Int) -> String {
        if seconds >= 3600 {
            let h = seconds / 3600, m = (seconds % 3600) / 60
            return m == 0 ? "\(h) h" : String(format: "%d h %02d", h, m)
        }
        if seconds >= 60 {
            let m = seconds / 60, s = seconds % 60
            return s == 0 ? "\(m) min" : String(format: "%d min %02d", m, s)
        }
        return "\(seconds) s"
    }

    /// Countdown display: `h:mm:ss` or `m:ss`.
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// Timer label (`me`): the step type, followed by the first matched ingredient with a partitive.
    static func label(language: AppLanguage = .current, stepText: String, stepIndex: Int, matchedIngredient: String?) -> String {
        func has(_ p: String) -> Bool { stepText.range(of: p, options: [.regularExpression, .caseInsensitive]) != nil }
        if language == .en {
            // The website's English labeller (separate rules, "<Label> — <ingredient>").
            let kind: String? = has("four|enfourn|oven|bake") ? "Oven"
                : has("repos|reposer|réserv|lever|pousser|refroidir|rest|cool") ? "Rest"
                : has("marin") ? "Marinade"
                : has("cui|mijot|bouill|frire|dorer|cook|simmer|boil|fry") ? "Cooking" : nil
            guard let kind else { return "Step \(stepIndex + 1)" }
            if kind == "Rest" { return kind }
            if let name = matchedIngredient?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return "\(kind) — \(name)" }
            return kind
        }
        let kind: String?
        if has(#"cui(re|sson|ssez|s|t)|mijot|bouill|frire|frit|rôti|dorer"#) { kind = "Cuisson" }
        else if has(#"four|enfourn"#) { kind = "Four" }
        else if has(#"repos|reposer|réserv|lever|pousser|frigo|réfrigér|refroidir"#) { kind = "Repos" }
        else if has(#"mariner|marinade"#) { kind = "Marinade" }
        else { kind = nil }
        guard let kind else { return "Étape \(stepIndex + 1)" }
        if kind == "Repos" { return "Repos" }
        guard let name = matchedIngredient?.trimmingCharacters(in: .whitespaces), let first = name.lowercased().first else { return kind }
        let partitive: String
        if "aeiouyhàâäéèêëîïôöùûü".contains(first) { partitive = "de l'" }
        else if name.lowercased().hasSuffix("s") || name.lowercased().hasSuffix("x") { partitive = "des " }
        else { partitive = "du " }
        return "\(kind) \(partitive)\(name)"
    }
}

/// Port of the ingredient-to-step matching (SPEC §A.3.2).
enum StepIngredientMatcher {
    private static let stopWords: Set<String> = ["de", "du", "des", "la", "le", "les", "d", "l", "a", "au", "et", "en", "frais", "fraiche"]
    private static let adjectives: Set<String> = ["petit", "petite", "gros", "grosse", "grand", "grande", "bio", "fraichement", "rape", "sec", "seche", "blanc", "rouge", "noir"]

    static func normalize(_ s: String) -> String {
        let folded = s.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        return String(folded.map { ($0.isLetter || $0.isNumber) && $0.isASCII ? $0 : " " })
    }

    static func singular(_ t: String) -> String {
        t.replacingOccurrences(of: #"(aux|eaux|s|x)$"#, with: "", options: .regularExpression)
    }

    static func stepTokens(_ step: String) -> Set<String> {
        let cleaned = step.replacingOccurrences(of: #"(?:(é|e)pluche|presse|coupe|vide|casse|r(a|â)pe|ouvre)-[\p{L}]+"#,
                                                with: " ", options: [.regularExpression, .caseInsensitive])
        return Set(normalize(cleaned).split(separator: " ").map { singular(String($0)) }.filter { !$0.isEmpty })
    }

    static func ingredientTokens(_ name: String) -> [String] {
        let n = " " + normalize(name) + " "
        var head = n
        if let r = n.range(of: #"\s(de|du|des|d|a|au|aux|ou|pour)\s"#, options: .regularExpression), r.lowerBound > n.startIndex {
            head = String(n[..<r.lowerBound])
        }
        return head.split(separator: " ").map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) && !adjectives.contains($0) }
            .map(singular)
            .filter { !$0.isEmpty }
    }

    static func matches(ingredient name: String, stepTokens: Set<String>) -> Bool {
        ingredientTokens(name).contains { stepTokens.contains($0) }
    }

    static func ingredients(_ list: [RecipeIngredient], for step: String) -> [RecipeIngredient] {
        let tokens = stepTokens(step)
        return list.filter { matches(ingredient: $0.name, stepTokens: tokens) }
    }
}
