import SwiftUI

/// `/mes-recettes`, "Mon livre de cuisine" (SPEC §B.3). Pushed from the profile tab's NavigationStack.
struct MyCookbookView: View {
    @Environment(AppStore.self) private var store

    enum Tab: Hashable { case mine, favorites }
    @State private var tab: Tab = .mine
    @State private var newRecipe: NewRecipeLaunch?
    @State private var editing: UUID?
    @State private var pendingDelete: Recipe?
    @State private var toast: String?

    init() {}

    private var mine: [Recipe] {
        guard let uid = store.userId else { return [] }
        return store.recipes.filter { $0.createdBy == uid }
    }

    private var favorites: [Recipe] {
        store.recipes.filter { store.favorites[$0.id] != nil }
            .sorted { (store.favorites[$0.id] ?? .distantPast) > (store.favorites[$1.id] ?? .distantPast) }
    }

    var body: some View {
        let list = tab == .mine ? mine : favorites
        List {
            Section {
                Picker("Mon livre de cuisine", selection: $tab) {
                    Text("Mes recettes (\(mine.count))").tag(Tab.mine)
                    Text("Mes favoris (\(favorites.count))").tag(Tab.favorites)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            if list.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(tab == .mine ? "Mon livre de cuisine" : "Mes favoris",
                              systemImage: tab == .mine ? "book.closed" : "heart")
                    } description: {
                        Text(tab == .mine
                             ? "Ton livre de cuisine est encore tout neuf. Ajoute ta première recette !"
                             : "Pas encore de favoris. Tape sur le cœur d'une recette pour la retrouver ici !")
                    } actions: {
                        if tab == .mine {
                            Button("+ Ajouter") { newRecipe = NewRecipeLaunch(withPhoto: false) }
                                .buttonStyle(.popotePrimaryCompact)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(list) { recipe in row(recipe) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .popoteBackground()
        .navigationTitle("Mon livre de cuisine")
        .navigationBarTitleDisplayMode(.large)
        .animation(.snappy, value: tab)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SyncStatusButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { newRecipe = NewRecipeLaunch(withPhoto: false) } label: {
                    Text("+ Ajouter").font(AppFont.body(15, weight: .heavy))
                }
            }
        }
        .fullScreenCover(item: $newRecipe) { newRecipeEntry(startWithPhoto: $0.withPhoto) }
        .fullScreenCover(item: Binding(get: { editing.map(EditTarget.init) }, set: { editing = $0?.id })) {
            editRecipeEntry(recipeId: $0.id)
        }
        .confirmationDialog(pendingDelete.map { String(localized: "Supprimer « \($0.title) » ?") } ?? "",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { recipe in
            Button("Supprimer", role: .destructive) { delete(recipe) }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("Elle disparaîtra de la base commune pour tout le monde.")
        }
        .recipeToast($toast)
    }

    private struct EditTarget: Identifiable { let id: UUID }

    private func row(_ recipe: Recipe) -> some View {
        NavigationLink {
            RecipeDetailView(recipeId: recipe.id)
        } label: {
            HStack(spacing: 12) {
                RecipePhotoView(path: recipe.listPhotoPath, category: recipe.primaryCategory, iconSize: 22)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.title)
                        .font(AppFont.body(16, weight: .heavy, relativeTo: .headline))
                        .lineLimit(2)
                    let cats = RecipeFormat.categories(recipe)
                    if !cats.isEmpty {
                        Text(cats).font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    RecipeRatingSummary(avg: recipe.ratingAvg, count: recipe.ratingCount, size: 12)
                }
                Spacer(minLength: 0)
                RecipeHeartButton(recipeId: recipe.id, size: 34)
            }
        }
        .listRowBackground(Palette.card)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if store.canEdit(recipe) {
                Button(role: .destructive) { pendingDelete = recipe } label: { Label("Supprimer", systemImage: "trash") }
                    .disabled(!store.isOnline)
                Button { editing = recipe.id } label: { Label("Modifier", systemImage: "pencil") }
                    .tint(Palette.sage)
                    .disabled(!store.isOnline)
            }
        }
        .contextMenu {
            if store.canEdit(recipe) {
                Button { editing = recipe.id } label: { Label("Modifier", systemImage: "pencil") }
                    .disabled(!store.isOnline)
                Button(role: .destructive) { pendingDelete = recipe } label: { Label("Supprimer", systemImage: "trash") }
                    .disabled(!store.isOnline)
            }
        }
    }

    private func delete(_ recipe: Recipe) {
        guard store.isOnline else {
            toast = String(localized: "Hors ligne : la suppression sera possible au retour du réseau.")
            return
        }
        Task {
            do {
                try await store.deleteRecipe(recipe.id)
                toast = String(localized: "Recette supprimée")
            } catch {
                toast = String(localized: "Suppression impossible")
            }
        }
    }
}
