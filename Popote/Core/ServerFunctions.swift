import Foundation

/// Client for the website's TanStack Start server functions (`POST /_serverFn/<id>`).
/// Requests and responses use seroval's JSON node format (see docs/spec/SPEC.md §C.11).
struct ServerFunctions: Sendable {
    enum ID {
        static let photoToRecipe = "0aa253b0d610fbe837a4ec9ad4f338f5ca37a75a618338b85c58fafac32aa5ad"
        static let textToRecipes = "e4fe9f8721a74c14b325e4d6c34321d86241473f65a7b0dc9296ad046a4caf33"
        static let urlToRecipes = "a2b48a88e43523c600947bf17d04c7894e27a6228277bbd569d884062a5ba4ef"
        static let enrichIngredients = "789c6d723c3130a983ec35993e4ec23d1f75a48585adf43e2a4f87361d9321b5"
        static let deleteAccount = "27301031363e284184ead21ac910c33ebfbe9159435c975f26319c6a65fade88"
    }

    enum CallError: LocalizedError {
        case notSignedIn
        case http(Int, String)
        case server(String)
        case decoding

        var errorDescription: String? {
            switch self {
            case .notSignedIn: String(localized: "Non connecté")
            case .http(let code, _) where code == 404: String(localized: "Cette fonction du site a changé. Mets l'app à jour.")
            case .http(_, let body): body.isEmpty ? String(localized: "Le serveur ne répond pas.") : body
            case .server(let message): message
            case .decoding: String(localized: "Réponse inattendue du serveur.")
            }
        }
    }

    var baseURL: URL = Backend.webURL
    var session: URLSession = .shared
    var accessToken: @Sendable () async throws -> String?

    /// Calls a server function with `{data: input}` and returns the decoded `result`.
    func call(_ id: String, data: Any, timeout: TimeInterval = 180) async throws -> Any? {
        guard let token = try await accessToken() else { throw CallError.notSignedIn }
        var request = URLRequest(url: baseURL.appending(path: "_serverFn/\(id)"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("true", forHTTPHeaderField: "x-tsr-serverFn")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try Seroval.encodeRequest(["data": data])

        let (body, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw CallError.http(status, String(data: body, encoding: .utf8) ?? "")
        }
        let json = try JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])
        let decoded: Any?
        if (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-tss-serialized") != nil {
            decoded = try Seroval.decode(json)
        } else {
            decoded = json
        }
        if let dict = decoded as? [String: Any] {
            if let error = dict["error"], !(error is NSNull) {
                throw CallError.server(Seroval.message(from: error))
            }
            if dict.keys.contains("result") { return dict["result"] ?? nil }
        }
        return decoded
    }
}

/// Minimal seroval JSON encoder/decoder for plain data (objects, arrays, strings, numbers, booleans, null).
enum Seroval {
    static func encodeRequest(_ value: Any) throws -> Data {
        var counter = 0
        let tree = node(value, &counter)
        let wrapper: [String: Any] = ["t": tree, "f": 127, "m": [Any]()]
        return try JSONSerialization.data(withJSONObject: wrapper, options: [.withoutEscapingSlashes])
    }

    static func node(_ value: Any?, _ counter: inout Int) -> [String: Any] {
        switch value {
        case nil, is NSNull:
            return ["t": 2, "s": 0]
        case let b as Bool:
            return ["t": 2, "s": b ? 2 : 3]
        case let n as Int:
            return ["t": 0, "s": n]
        case let n as Double:
            if n.isNaN { return ["t": 2, "s": 7] }
            if n.isInfinite { return ["t": 2, "s": n > 0 ? 5 : 6] }
            return ["t": 0, "s": n]
        case let s as String:
            return ["t": 1, "s": escape(s)]
        case let a as [Any?]:
            let id = counter; counter += 1
            return ["t": 9, "i": id, "a": a.map { node($0, &counter) }, "o": 0]
        case let d as [String: Any?]:
            let id = counter; counter += 1
            let keys = d.keys.sorted()
            return ["t": 10, "i": id, "p": ["k": keys, "v": keys.map { node(d[$0] ?? nil, &counter) }], "o": 0]
        default:
            return ["t": 1, "s": escape(String(describing: value!))]
        }
    }

    /// Same escaping as seroval's `serializeString`.
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "<": out += "\\x3C"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    static func unescape(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = ""
        var it = s.unicodeScalars.makeIterator()
        while let c = it.next() {
            guard c == "\\", let n = it.next() else { out.unicodeScalars.append(c); continue }
            switch n {
            case "n": out += "\n"
            case "r": out += "\r"
            case "t": out += "\t"
            case "b": out += "\u{8}"
            case "f": out += "\u{c}"
            case "v": out += "\u{b}"
            case "0": out += "\0"
            case "x":
                var hex = ""
                for _ in 0..<2 { if let h = it.next() { hex.unicodeScalars.append(h) } }
                if let v = UInt32(hex, radix: 16), let u = Unicode.Scalar(v) { out.unicodeScalars.append(u) }
            case "u":
                var hex = ""
                for _ in 0..<4 { if let h = it.next() { hex.unicodeScalars.append(h) } }
                if let v = UInt32(hex, radix: 16), let u = Unicode.Scalar(v) { out.unicodeScalars.append(u) }
            default: out.unicodeScalars.append(n)
            }
        }
        return out
    }

    /// Decodes a seroval JSON tree (either the bare root node or a `{t, f, m}` wrapper) into Foundation values.
    static func decode(_ json: Any) throws -> Any? {
        var refs: [Int: Any] = [:]
        if let dict = json as? [String: Any], let root = dict["t"] as? [String: Any], dict["f"] != nil {
            return try value(root, &refs)
        }
        guard let root = json as? [String: Any] else { return json }
        return try value(root, &refs)
    }

    private static func value(_ node: [String: Any], _ refs: inout [Int: Any]) throws -> Any? {
        guard let type = node["t"] as? Int else { throw ServerFunctions.CallError.decoding }
        switch type {
        case 0: return node["s"]
        case 1: return unescape(node["s"] as? String ?? "")
        case 2:
            switch node["s"] as? Int {
            case 2: return true
            case 3: return false
            case 5: return Double.infinity
            case 6: return -Double.infinity
            case 7: return Double.nan
            case 4: return -0.0
            default: return nil
            }
        case 3: return Double(node["s"] as? String ?? "") ?? node["s"]
        case 4:
            if let id = node["i"] as? Int { return refs[id] }
            return nil
        case 5:
            let s = node["s"] as? String ?? ""
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s) ?? s
        case 9:
            let items = node["a"] as? [Any] ?? []
            let result = try items.map { item -> Any? in
                guard let n = item as? [String: Any] else { return nil }
                return try value(n, &refs)
            }
            let array = result.map { $0 ?? NSNull() }
            if let id = node["i"] as? Int { refs[id] = array }
            return array
        case 10, 11:
            var dict: [String: Any] = [:]
            if let p = node["p"] as? [String: Any],
               let keys = p["k"] as? [String],
               let vals = p["v"] as? [Any] {
                for (k, v) in zip(keys, vals) {
                    if let n = v as? [String: Any] { dict[unescape(k)] = try value(n, &refs) ?? NSNull() }
                }
            }
            if let id = node["i"] as? Int { refs[id] = dict }
            return dict
        default:
            // Unsupported node kinds (Map, Set, Error, …) are not used by the app's server functions.
            if let s = node["s"] { return s }
            return nil
        }
    }

    static func message(from error: Any) -> String {
        if let s = error as? String { return s }
        if let d = error as? [String: Any], let m = d["message"] as? String { return m }
        return String(localized: "Une erreur est survenue.")
    }
}
