import Foundation

extension Notification.Name {
    /// Posted after the user picks FR or EN; the root view re-renders with the new language.
    static let popoteLanguageChanged = Notification.Name("popoteLanguageChanged")
}

extension AppStore {
    /// Mirrors the website's `setLanguage`: local choice first, then `profiles.preferred_language`.
    /// Returns an error message to display when the profile could not be updated.
    @discardableResult
    func setLanguage(_ language: AppLanguage) async -> String? {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
        profile?.preferredLanguage = language.rawValue
        NotificationCenter.default.post(name: .popoteLanguageChanged, object: language)
        saveSnapshot()
        guard authState == .signedIn, isOnline, let userId else { return nil }
        struct Row: Encodable { let preferred_language: String }
        do {
            try await client.from("profiles").update(Row(preferred_language: language.rawValue)).eq("id", value: userId).execute()
            return nil
        } catch {
            return String(localized: "Impossible d'enregistrer")
        }
    }
}
