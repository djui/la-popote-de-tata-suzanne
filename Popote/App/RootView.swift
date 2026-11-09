import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            switch store.authState {
            case .loading:
                LaunchView()
            case .signedOut:
                AuthView()
                    .transition(.opacity)
            case .signedIn:
                MainTabView()
                    .sheet(isPresented: termsSheetBinding) {
                        TermsGateView()
                            .interactiveDismissDisabled()
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.authState)
    }

    private var termsSheetBinding: Binding<Bool> {
        Binding(get: { store.termsAccepted == false }, set: { _ in })
    }
}

struct LaunchView: View {
    var body: some View {
        Wordmark(size: 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .popoteBackground()
    }
}

struct MainTabView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Recettes", systemImage: "book", value: Router.Tab.recipes) {
                RecipesTab()
            }
            Tab("Menu", systemImage: "calendar", value: Router.Tab.menu) {
                MenuTab()
            }
            Tab("Courses", systemImage: "basket", value: Router.Tab.shopping) {
                ShoppingTab()
            }
            Tab("Profil", systemImage: "person", value: Router.Tab.profile) {
                ProfileTab()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// Small toolbar indicator: offline, or changes waiting to sync.
struct SyncStatusButton: View {
    @Environment(AppStore.self) private var store
    @State private var showInfo = false

    var body: some View {
        if !store.isOnline || !store.pendingOps.isEmpty {
            Button {
                showInfo = true
            } label: {
                Image(systemName: store.isOnline ? "arrow.triangle.2.circlepath.icloud" : "icloud.slash")
            }
            .accessibilityLabel(store.isOnline ? Text("Synchronisation en attente") : Text("Hors ligne"))
            .popover(isPresented: $showInfo) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.isOnline ? "Synchronisation en cours" : "Tu es hors ligne")
                        .font(AppFont.body(15, weight: .bold))
                    Text(store.pendingOps.isEmpty
                         ? String(localized: "Toutes tes recettes restent disponibles.")
                         : String(localized: "\(store.pendingOps.count) modification(s) seront envoyées dès le retour du réseau."))
                        .font(AppFont.body(13))
                        .foregroundStyle(Palette.muted)
                }
                .padding()
                .frame(maxWidth: 280)
                .presentationCompactAdaptation(.popover)
            }
        }
    }
}
