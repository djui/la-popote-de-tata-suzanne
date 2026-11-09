import Foundation

/// The app's UI language (French or English), mirroring the website's FR | EN toggle.
/// Stored locally and synced with `profiles.preferred_language`.
enum AppLanguage: String, CaseIterable, Sendable, Identifiable {
    case fr, en
    var id: String { rawValue }

    static let storageKey = "popote_lang"

    /// Explicit choice if the user made one, otherwise the device language (English devices get English).
    static var current: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: storageKey), let lang = AppLanguage(rawValue: raw) { return lang }
        let preferred = Locale.preferredLanguages.first?.prefix(2) ?? "fr"
        return preferred == "en" ? .en : .fr
    }

    static var hasExplicitChoice: Bool { UserDefaults.standard.string(forKey: storageKey) != nil }

    /// Makes `String(localized:)` and `Text("…")` resolve in `language` without restarting the app.
    @MainActor
    static func applyToBundle(_ language: AppLanguage) {
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        LocalizedBundle.select(language.rawValue)
    }

    var locale: Locale { Locale(identifier: self == .en ? "en_GB" : "fr_FR") }
    var label: String { self == .en ? "EN" : "FR" }
}

/// Redirects `Bundle.main` string lookups to the chosen `.lproj`, so a language switch applies immediately.
private final class LocalizedBundle: Bundle, @unchecked Sendable {
    nonisolated(unsafe) static var override: Bundle?

    static func select(_ code: String) {
        object_setClass(Bundle.main, LocalizedBundle.self)
        override = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let override = Self.override, self === Bundle.main || Bundle.main.bundlePath == bundlePath {
            return override.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
