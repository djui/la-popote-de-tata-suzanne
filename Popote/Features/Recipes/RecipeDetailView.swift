import SwiftUI

/// `/recettes/$id` (SPEC §A.2).
struct RecipeDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recipeId: UUID

    var body: some View {
        if let recipe = store.recipe(recipeId) {
            RecipeDetailContent(recipe: recipe, onDeleted: { dismiss() })
        } else if store.isSyncing || store.authState == .loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).popoteBackground()
        } else {
            ContentUnavailableView("Recette introuvable", systemImage: "fork.knife",
                                   description: Text("Elle a peut-être été supprimée."))
                .popoteBackground()
        }
    }
}

private struct RecipeDetailContent: View {
    @Environment(AppStore.self) private var store
    let recipe: Recipe
    let onDeleted: () -> Void

    @State private var servings: Int
    @State private var showCook = false
    @State private var showAddToMenu = false
    @State private var showReport = false
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var toast: String?
    @State private var favoriteCount: Int?
    @State private var favoriteNames: [String]?
    @State private var showFavoriteNames = false
    @State private var scrollToComments = false

    private let heroHeight: CGFloat = 360

    init(recipe: Recipe, onDeleted: @escaping () -> Void) {
        self.recipe = recipe
        self.onDeleted = onDeleted
        _servings = State(initialValue: recipe.servings ?? 4)
    }

    private var ingredients: [RecipeIngredient] { store.ingredientsByRecipe[recipe.id] ?? [] }
    private var steps: [RecipeStep] { store.stepsByRecipe[recipe.id] ?? [] }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        actions
                        myRating
                        ingredientsCard
                        stepsSection
                        notesAndSource
                        tagsSection
                        reportButton
                        RecipeCommentsSection(recipe: recipe)
                            .id("commentaires")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .background(Palette.background)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            .onChange(of: scrollToComments) { _, go in
                guard go else { return }
                withAnimation { proxy.scrollTo("commentaires", anchor: .top) }
                scrollToComments = false
            }
        }
        .popoteBackground()
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        .toolbar(removing: .title)
        .toolbar { toolbar }
        .fullScreenCover(isPresented: $showCook) {
            CookModeView(recipe: recipe, onLeaveComment: { scrollToComments = true })
        }
        .sheet(isPresented: $showAddToMenu) {
            AddToMenuSheet(recipe: recipe) { toast = $0 }
        }
        .sheet(isPresented: $showReport) {
            ReportRecipeSheet(recipe: recipe) { toast = $0 }
        }
        .fullScreenCover(isPresented: $showEdit) {
            editRecipeEntry(recipeId: recipe.id)
        }
        .confirmationDialog("Supprimer cette recette ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive, action: delete)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette action est définitive.")
        }
        .recipeToast($toast)
        .userActivity(SpotlightIndexer.activityType) { activity in
            activity.title = recipe.title
            activity.userInfo = ["recipeId": recipe.id.uuidString]
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.isEligibleForHandoff = true
            activity.webpageURL = RecipeFormat.webURL(recipe.id)
            activity.persistentIdentifier = recipe.id.uuidString
        }
        .task(id: store.isOnline) { await loadFavoriteCount() }
    }

    // MARK: Hero

    private var hero: some View {
        RecipePhotoView(path: recipe.photoUrl, category: recipe.primaryCategory, iconSize: 80)
            .frame(height: heroHeight)
            .frame(maxWidth: .infinity)
            .clipped()
            .visualEffect { content, geo in
                let minY = geo.frame(in: .scrollView).minY
                let stretch = max(0, minY)
                return content
                    .scaleEffect(1 + stretch / heroHeight, anchor: .bottom)
                    .offset(y: minY < 0 ? -minY * 0.35 : 0)
            }
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                    .allowsHitTesting(false)
            }
            .zIndex(-1)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !recipe.recipeCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recipe.recipeCategories) { ChipView(title: $0.label, systemImage: $0.symbol, isOn: true) }
                        ForEach(recipe.seasons ?? [], id: \.self) { s in
                            ChipView(title: Season(rawValue: s)?.label ?? s.capitalized)
                        }
                    }
                }
                .scrollClipDisabled()
            }

            Text(recipe.title)
                .font(AppFont.display(32, relativeTo: .largeTitle))
                .foregroundStyle(Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 14) {
                if let prep = recipe.prepTimeMin { metaLabel("\(prep) min", systemImage: "clock", a11y: "Préparation \(prep) min") }
                if let cook = recipe.cookTimeMin { metaLabel("\(cook) min", systemImage: "flame", a11y: "Cuisson \(cook) min") }
                if let s = recipe.servings { metaLabel("\(s)", systemImage: "person.2", a11y: "\(s) personnes") }
                if let d = recipe.difficulty, !d.isEmpty { metaLabel(LocalizedStringKey(d.capitalized), systemImage: "chart.bar", a11y: LocalizedStringKey(d)) }
            }
            .font(AppFont.body(14, weight: .bold, relativeTo: .subheadline))
            .foregroundStyle(Palette.muted)

            HStack(spacing: 12) {
                RecipeRatingSummary(avg: recipe.ratingAvg, count: recipe.ratingCount, size: 14)
                if let favoriteCount, favoriteCount > 0 {
                    Button {
                        showFavoriteNames = true
                    } label: {
                        Text(verbatim: "❤️ \(favoriteCount)").font(AppFont.body(14, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Voir qui l'a en favori"))
                    .popover(isPresented: $showFavoriteNames) {
                        Group {
                            if let favoriteNames {
                                Text("Ajoutée aux favoris par **\(RecipeFormat.names(favoriteNames))**")
                            } else {
                                Text("Chargement…")
                            }
                        }
                        .font(AppFont.body(14))
                        .padding()
                        .frame(maxWidth: 280)
                        .presentationCompactAdaptation(.popover)
                        .task { await loadFavoriteNames() }
                    }
                }
            }

            Text("Ajoutée par \(recipe.createdBy.flatMap { store.authorNames[$0] } ?? String(localized: "un membre"))")
                .font(AppFont.body(14, relativeTo: .subheadline))
                .foregroundStyle(Palette.muted)

            if recipe.isPrivate == true {
                Text("🔒 Recette privée : visible seulement par le foyer de l'auteur")
                    .font(AppFont.body(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private func metaLabel(_ text: LocalizedStringKey, systemImage: String, a11y: LocalizedStringKey) -> some View {
        Label(text, systemImage: systemImage)
            .labelStyle(CompactLabelStyle())
            .accessibilityLabel(Text(a11y))
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            Button { showCook = true } label: {
                Label("Cuisiner", systemImage: "frying.pan")
            }
            .buttonStyle(.popotePrimary)
            Button { showAddToMenu = true } label: {
                Label("Ajouter au menu", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.popoteSecondary)
        }
    }

    private var myRating: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ma note").font(AppFont.body(14, weight: .heavy, relativeTo: .headline))
                RecipeStarInput(value: store.myRatings[recipe.id]) { stars in
                    store.setRating(recipe.id, stars: stars)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .popoteCard()
    }

    // MARK: Ingredients

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Ingrédients").font(AppFont.display(22, relativeTo: .title2)).accessibilityAddTraits(.isHeader)
                Spacer()
                ServingsStepperPill(value: $servings)
            }
            if ingredients.isEmpty {
                Text("Aucun ingrédient.").font(AppFont.body(15)).foregroundStyle(Palette.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ingredients.enumerated()), id: \.element.id) { index, ing in
                        let scaled = Quantity.scale(ing.quantity, base: recipe.servings, target: servings)
                        let f = Quantity.formatIngredient(scaled, unit: ing.unit, name: ing.name)
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(f.qty)
                                .font(AppFont.body(15, weight: .bold))
                                .foregroundStyle(Palette.primary)
                                .frame(width: 92, alignment: .leading)
                                .contentTransition(.numericText())
                            (Text(f.name) + (ing.optional == true ? Text(" (facultatif)").foregroundStyle(Palette.muted) : Text(verbatim: "")))
                                .font(AppFont.body(15))
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                        if index < ingredients.count - 1 { Divider() }
                    }
                }
                .animation(.snappy, value: servings)
            }
        }
        .padding(20)
        .popoteCard(radius: 24)
    }

    // MARK: Steps

    @ViewBuilder private var stepsSection: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: AppLanguage.current == .en ? "Method" : "Préparation").font(AppFont.display(22, relativeTo: .title2)).accessibilityAddTraits(.isHeader)
                ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: "\(i + 1)")
                            .font(AppFont.body(15, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Palette.tileGradient, in: Circle())
                            .accessibilityHidden(true)
                        Text(step.instruction)
                            .font(AppFont.body(16))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .accessibilityLabel(Text("Étape \(i + 1) : \(step.instruction)"))
                    }
                }
            }
        }
    }

    @ViewBuilder private var notesAndSource: some View {
        if let notes = recipe.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes").font(AppFont.display(18, relativeTo: .headline))
                Text(notes).font(AppFont.body(15)).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .popoteCard()
        }
        let inspiration = recipe.sourceInspiration?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = recipe.sourceUrl.flatMap { $0.range(of: #"^https?://"#, options: .regularExpression) != nil ? URL(string: $0) : nil }
        if !inspiration.isEmpty || url != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Source / inspiration").font(AppFont.display(18, relativeTo: .headline))
                if !inspiration.isEmpty { Text(inspiration).font(AppFont.body(15)) }
                if let url {
                    Link(destination: url) {
                        Text("Voir la recette d'origine ↗").font(AppFont.body(15, weight: .bold))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .popoteCard()
        }
    }

    @ViewBuilder private var tagsSection: some View {
        let tags = (recipe.tags ?? []).filter { !$0.isEmpty }
        if !tags.isEmpty {
            RecipeFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(tags, id: \.self) { ChipView(title: "#\($0)") }
            }
        }
    }

    private var reportButton: some View {
        Button { showReport = true } label: {
            Label("Signaler un contenu", systemImage: "flag")
                .font(AppFont.body(13, weight: .semibold))
                .foregroundStyle(Palette.muted)
        }
        .buttonStyle(.plain)
        .disabled(!store.isOnline)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                let wasOn = store.isFavorite(recipe.id)
                store.toggleFavorite(recipe.id)
                if let c = favoriteCount { favoriteCount = max(0, c + (wasOn ? -1 : 1)) }
                favoriteNames = nil
                toast = wasOn ? String(localized: "Retirée de tes favoris") : String(localized: "Ajoutée à tes favoris ❤️")
            } label: {
                Image(systemName: store.isFavorite(recipe.id) ? "heart.fill" : "heart")
                    .contentTransition(.symbolEffect(.replace))
            }
            .sensoryFeedback(.selection, trigger: store.isFavorite(recipe.id))
            .accessibilityLabel(store.isFavorite(recipe.id) ? Text("Retirer des favoris") : Text("Ajouter aux favoris"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: RecipeFormat.shareText(recipe, ingredients: ingredients, steps: steps),
                      subject: Text(recipe.title)) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel(Text("Partager"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if store.canEdit(recipe) {
                    Button { showEdit = true } label: { Label("Modifier", systemImage: "pencil") }
                        .disabled(!store.isOnline)
                }
                Button { showReport = true } label: { Label("Signaler", systemImage: "flag") }
                    .disabled(!store.isOnline)
                if store.canEdit(recipe) {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Supprimer", systemImage: "trash") }
                        .disabled(!store.isOnline || deleting)
                }
                if !store.isOnline {
                    Section { Text("Hors ligne : modifier, signaler et supprimer reviendront avec le réseau.") }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel(Text("Plus d'actions"))
        }
    }

    // MARK: Network

    private func loadFavoriteCount() async {
        guard store.isOnline else { return }
        favoriteCount = try? await store.favoriteCount(recipe.id)
    }

    private func loadFavoriteNames() async {
        guard favoriteNames == nil, store.isOnline else { return }
        favoriteNames = try? await store.favoriteNames(recipe.id)
    }

    private func delete() {
        deleting = true
        Task {
            do {
                try await store.deleteRecipe(recipe.id)
                onDeleted()
            } catch {
                toast = String(localized: "Suppression impossible")
            }
            deleting = false
        }
    }
}
