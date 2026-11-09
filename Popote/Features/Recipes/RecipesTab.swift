import SwiftUI

/// `/recettes` (SPEC §B.2): searchable, filterable grid of every recipe in the shared base.
struct RecipesTab: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var filters = RecipeFilterState()
    @State private var sort: RecipeSortOrder = .recent
    @State private var showFilters = false
    @State private var newRecipe: NewRecipeLaunch?
    @State private var addToMenu: Recipe?
    @State private var toast: String?

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.recipesPath) {
            content
                .navigationTitle("Recettes")
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $filters.q, prompt: Text("Titre ou ingrédient…"))
                .toolbar { toolbar }
                .refreshable { await store.refresh() }
                .navigationDestination(for: UUID.self) { RecipeDetailView(recipeId: $0) }
                .popoteBackground()
        }
        .sheet(isPresented: $showFilters) {
            RecipeFiltersSheet(filters: $filters, allTags: allTags, resultCount: results.count)
        }
        .sheet(item: $addToMenu) { recipe in
            AddToMenuSheet(recipe: recipe) { toast = $0 }
        }
        .fullScreenCover(item: $newRecipe) { launch in
            newRecipeEntry(startWithPhoto: launch.withPhoto)
        }
        .recipeToast($toast)
    }

    // MARK: Data

    private var results: [Recipe] {
        filters.apply(to: store.recipes, ingredientsByRecipe: store.ingredientsByRecipe,
                      favorites: store.favorites, userId: store.userId, sort: sort)
    }

    private var allTags: [String] {
        let locale = Locale(identifier: "fr_FR")
        return Array(Set(store.recipes.flatMap { $0.tags ?? [] }).filter { !$0.isEmpty })
            .sorted { $0.compare($1, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) == .orderedAscending }
    }

    // MARK: Views

    @ViewBuilder private var content: some View {
        let list = results
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                chipRow
                if !store.recipes.isEmpty, !list.isEmpty {
                    Text(RecipeFormat.recipeCount(list.count))
                        .font(AppFont.body(14, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal)
                        .contentTransition(.numericText(value: Double(list.count)))
                        .animation(.snappy, value: list.count)
                }
                if list.isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 280), spacing: 14, alignment: .top)],
                              alignment: .leading, spacing: 18) {
                        ForEach(list) { recipe in
                            NavigationLink(value: recipe.id) {
                                RecipeGridCard(recipe: recipe)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { contextMenu(for: recipe) } preview: {
                                RecipeGridCard(recipe: recipe, showHeart: false)
                                    .frame(width: 240)
                                    .padding(12)
                                    .background(Palette.background)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var chipRow: some View {
        let current = Season.current()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { showFilters = true } label: {
                    ChipView(title: filters.activeCount > 0 ? String(localized: "Filtres (\(filters.activeCount))") : String(localized: "Filtres"),
                             systemImage: "line.3.horizontal.decrease", isOn: filters.activeCount > 0)
                }
                chip(String(localized: "Mes favoris ❤️"), isOn: filters.favorites) { filters.favorites.toggle() }
                chip(String(localized: "👤 Ajoutées par moi"), isOn: filters.mine) { filters.mine.toggle() }
                chip(String(localized: "🌿 De saison"), isOn: filters.isInSeasonFilter(current)) { filters.toggleSeasonal(current) }
                Divider().frame(height: 20)
                ForEach(RecipeCategory.allCases) { cat in
                    chip(cat.label, systemImage: cat.symbol, isOn: filters.categories.contains(cat)) {
                        if filters.categories.contains(cat) { filters.categories.remove(cat) } else { filters.categories.insert(cat) }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: filters)
    }

    private func chip(_ title: String, systemImage: String? = nil, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            ChipView(title: title, systemImage: systemImage, isOn: isOn)
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder private var emptyState: some View {
        if store.recipes.isEmpty {
            ContentUnavailableView {
                Label("La base de recettes est encore vide", systemImage: "frying.pan")
            } description: {
                Text("Prends une recette en photo, on s'occupe du reste.")
            } actions: {
                Button("+ Ajouter une recette") { newRecipe = NewRecipeLaunch(withPhoto: false) }
                    .buttonStyle(.popotePrimaryCompact)
            }
        } else {
            ContentUnavailableView {
                Label("Rien ne correspond… pour l'instant !", systemImage: "magnifyingglass")
            } description: {
                Text("Essaie d'enlever un filtre, ou ajoute cette recette à ton livre de cuisine.")
            } actions: {
                if filters.activeCount > 0 || filters.mine {
                    Button("Tout effacer") {
                        withAnimation { filters.clear(); filters.mine = false }
                    }
                    .buttonStyle(.popoteSecondary)
                }
                Button("+ Ajouter une recette") { newRecipe = NewRecipeLaunch(withPhoto: false) }
                    .buttonStyle(.popotePrimaryCompact)
            }
        }
    }

    @ViewBuilder private func contextMenu(for recipe: Recipe) -> some View {
        let fav = store.isFavorite(recipe.id)
        Button {
            store.toggleFavorite(recipe.id)
            toast = fav ? String(localized: "Retirée de tes favoris") : String(localized: "Ajoutée à tes favoris ❤️")
        } label: {
            Label(fav ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: fav ? "heart.slash" : "heart")
        }
        Button { addToMenu = recipe } label: {
            Label("Ajouter au menu", systemImage: "calendar.badge.plus")
        }
        ShareLink(item: RecipeFormat.webURL(recipe.id), subject: Text(recipe.title),
                  message: Text(RecipeFormat.shareText(recipe, ingredients: store.ingredientsByRecipe[recipe.id] ?? [],
                                                        steps: store.stepsByRecipe[recipe.id] ?? []))) {
            Label("Partager", systemImage: "square.and.arrow.up")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { SyncStatusButton() }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Trier", selection: $sort) {
                    ForEach(RecipeSortOrder.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel(Text("Trier"))
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button { newRecipe = NewRecipeLaunch(withPhoto: true) } label: {
                Image(systemName: "camera")
            }
            .accessibilityLabel(Text("Prendre une recette en photo"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { newRecipe = NewRecipeLaunch(withPhoto: false) } label: {
                Text("+ Ajouter").font(AppFont.body(15, weight: .heavy))
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.primary)
            .foregroundStyle(Palette.onPrimary)
        }
    }
}

struct NewRecipeLaunch: Identifiable, Hashable {
    let id = UUID()
    var withPhoto: Bool
}

/// A recipe card in the grid (SPEC §B.2).
struct RecipeGridCard: View {
    @Environment(AppStore.self) private var store
    let recipe: Recipe
    var showHeart = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { RecipePhotoView(path: recipe.listPhotoPath, category: recipe.primaryCategory) }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if showHeart {
                        RecipeHeartButton(recipeId: recipe.id).padding(8)
                    }
                }
            Text(recipe.title)
                .font(AppFont.body(15, weight: .heavy, relativeTo: .headline))
                .foregroundStyle(Palette.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            let cats = RecipeFormat.categories(recipe)
            if !cats.isEmpty {
                Text(cats)
                    .font(AppFont.body(12, relativeTo: .caption))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                if let total = recipe.totalMinutes {
                    Label("\(total) min", systemImage: "clock")
                }
                if let servings = recipe.servings {
                    Label("\(servings)", systemImage: "person.2")
                        .accessibilityLabel(Text("\(servings) personnes"))
                }
            }
            .labelStyle(CompactLabelStyle())
            .font(AppFont.body(12, weight: .semibold, relativeTo: .caption))
            .foregroundStyle(Palette.muted)
            RecipeRatingSummary(avg: recipe.ratingAvg, count: recipe.ratingCount, size: 12)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
