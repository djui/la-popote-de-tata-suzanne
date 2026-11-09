import SwiftUI

/// `/recettes/$id/modifier` (SPEC §A.4), presented full screen from the recipe page.
struct EditRecipeView: View {
    let recipeId: UUID

    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RecipeDraft?
    @State private var uploads: UploadSession?
    @State private var finished = false

    var body: some View {
        NavigationStack {
            Group {
                if let uploads, draft != nil {
                    RecipeForm(draft: Binding(get: { draft ?? .blank() }, set: { draft = $0 }),
                               highlightEmpty: false,
                               submitLabel: "Enregistrer les modifications",
                               uploads: uploads,
                               onSubmit: save)
                } else if store.recipe(recipeId) != nil {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).popoteBackground()
                } else {
                    ContentUnavailableView("Recette introuvable", systemImage: "book.closed",
                                           description: Text("Elle a peut-être été supprimée."))
                        .popoteBackground()
                }
            }
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { close() }
                }
                ToolbarItem(placement: .topBarTrailing) { SyncStatusButton() }
            }
        }
        .tint(Palette.primary)
        .onAppear(perform: load)
        .onDisappear { if !finished { uploads?.cleanup() } }
    }

    private func load() {
        guard draft == nil, let recipe = store.recipe(recipeId) else { return }
        uploads = UploadSession(client: store.client)
        draft = RecipeDraft(recipe: recipe,
                            ingredients: store.ingredientsByRecipe[recipeId] ?? [],
                            steps: store.stepsByRecipe[recipeId] ?? [])
    }

    private func save() async throws {
        guard let draft else { return }
        try await RecipeRepository(store: store).save(draft, id: recipeId)
        try? await store.refreshRecipe(recipeId)
        finished = true
        uploads?.cleanup()
        dismiss()
        router.open(recipe: recipeId)
    }

    private func close() {
        uploads?.cleanup()
        finished = true
        dismiss()
    }
}
