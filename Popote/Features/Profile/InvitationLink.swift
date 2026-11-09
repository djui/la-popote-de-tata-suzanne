import Foundation

/// Building and parsing household invitation links (`https://…/invitation/<code>`, `popote://invitation/<code>`).
enum InvitationLink {
    static func url(code: String, base: URL = Backend.webURL) -> URL {
        base.appending(path: "invitation").appending(path: code)
    }

    /// Accepts a full link (web or app scheme, with or without query/fragment) or a bare code.
    static func code(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("/") || trimmed.contains(":") {
            guard let comps = URLComponents(string: trimmed) else { return nil }
            var parts = comps.path.split(separator: "/").map(String.init)
            if let host = comps.host, comps.scheme?.hasPrefix("http") == false { parts.insert(host, at: 0) }
            guard let i = parts.firstIndex(of: "invitation"), parts.indices.contains(i + 1) else { return nil }
            return sanitize(parts[i + 1].removingPercentEncoding ?? parts[i + 1])
        }
        return sanitize(trimmed)
    }

    private static func sanitize(_ raw: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !raw.isEmpty, raw.count <= 128, raw.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return raw
    }

    /// Initials helper from household-*.js: `(name ?? '?').trim().slice(0,2).toUpperCase() || '?'`.
    static func initials(_ name: String?) -> String {
        let s = String((name ?? "?").trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased()
        return s.isEmpty ? "?" : s
    }
}
