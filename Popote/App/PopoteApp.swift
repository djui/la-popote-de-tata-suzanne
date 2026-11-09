import SwiftUI

@main
struct PopoteApp: App {
    @State private var store = AppStore()
    @State private var router = Router()
    @State private var language = AppLanguage.current
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Appearance.configure()
        AppLanguage.applyToBundle(AppLanguage.current)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(\.locale, language.locale)
                .id(language)
                .tint(Palette.primary)
                .onReceive(NotificationCenter.default.publisher(for: .popoteLanguageChanged)) { _ in
                    AppLanguage.applyToBundle(AppLanguage.current)
                    language = AppLanguage.current
                }
                .onAppear { store.start() }
                .onOpenURL { router.handle(url: $0) }
                .onContinueUserActivity(SpotlightIndexer.activityType) { router.handle(activity: $0) }
                .onContinueUserActivity("com.apple.corespotlightitem") { router.handle(activity: $0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { router.handle(url: url) }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }
}

/// App-wide navigation state (tabs + deep links).
@MainActor
@Observable
final class Router {
    enum Tab: Hashable { case recipes, menu, shopping, profile }
    var tab: Tab = .recipes
    var recipesPath: [UUID] = []
    /// Invitation code received via a link, kept across sign-in.
    var pendingInvitation: String?

    func open(recipe id: UUID) {
        tab = .recipes
        recipesPath = [id]
    }

    func handle(url: URL) {
        // popote://recette/<id>, popote://invitation/<code>, https://…/recettes/<id>, …/invitation/<code>
        let parts = ([url.host()].compactMap { $0 } + url.pathComponents).filter { $0 != "/" }
        guard let i = parts.firstIndex(where: { ["recette", "recettes", "invitation", "menu", "courses"].contains($0) }) else { return }
        let next = parts.indices.contains(i + 1) ? parts[i + 1] : nil
        switch parts[i] {
        case "recette", "recettes":
            if let next, let id = UUID(uuidString: next) { open(recipe: id) } else { tab = .recipes }
        case "invitation":
            if let next { pendingInvitation = next; tab = .profile }
        case "menu": tab = .menu
        case "courses": tab = .shopping
        default: break
        }
    }

    func handle(activity: NSUserActivity) {
        if let id = SpotlightIndexer.recipeId(from: activity) { open(recipe: id) }
    }
}
