import SwiftUI

struct ProfileTab: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        NavigationStack {
            List { Button("Se déconnecter") { Task { await store.signOut() } } }
                .navigationTitle("Profil")
        }
    }
}

struct TermsView: View {
    var body: some View { ScrollView { Text("Conditions générales d'utilisation").padding() }.navigationTitle("Conditions") }
}

struct StoryView: View {
    var body: some View { ScrollView { Text("L'histoire de Tata Suzanne").padding() }.navigationTitle("Tata Suzanne") }
}
