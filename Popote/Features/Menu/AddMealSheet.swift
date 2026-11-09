import SwiftUI

/// Free-dish presets from `meal-plan-*.js` (exact strings).
private let freeDishPresets = ["🥡 Restes", "🥪 Sur le pouce", "🥣 Soupe & tartines", "🥗 Salade composée",
                       "🍕 Pizza / Livraison", "🍽️ Resto / Sortie", "🧺 Pique-nique", "🎉 Apéro / Invités"]

/// Adds a recipe or a free dish to the menu. With `fixedSlot` the day and meal are given (an empty
/// cell was tapped); without it (the "Recettes" shortcut) they are picked here, like AddToMenuDialog.
struct AddMealSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let fixedSlot: MealSlot?
    let weekStart: Date
    var onAdded: (String) -> Void

    enum Mode: Hashable { case recipe, free }
    @State private var mode: Mode = .recipe
    @State private var query = ""
    @State private var selectedRecipe: UUID?
    @State private var customTitle = ""
    @State private var servings = 4
    @State private var day = ""
    @State private var meal: MealType = .diner
    @FocusState private var titleFocused: Bool

    private var days: [Date] { (0..<7).map { PlanDates.adding(days: $0, to: weekStart) } }

    private var filteredRecipes: [Recipe] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.recipes }
        return store.recipes.filter { r in
            let names = (store.ingredientsByRecipe[r.id] ?? []).map(\.name).joined(separator: " ")
            return ShoppingListBuilder.matches(q, r.title + " " + names)
        }
    }

    private var canAdd: Bool {
        switch mode {
        case .recipe: selectedRecipe != nil
        case .free: !customTitle.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            content
                .scrollContentBackground(.hidden)
                .popoteBackground()
                .navigationTitle(fixedSlot.map { slotTitle($0) } ?? String(localized: "Ajouter au menu"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItem(placement: .principal) {
                        Picker("Type", selection: $mode) {
                            Text("Recette").tag(Mode.recipe)
                            Text("Plat libre").tag(Mode.free)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 240)
                    }
                }
                .safeAreaInset(edge: .bottom) { footer }
        }
        .onAppear {
            servings = store.defaultServings
            let today = LocalDay.string(.now)
            let week = days.map(LocalDay.string)
            day = fixedSlot?.date ?? (week.contains(today) ? today : week.first ?? today)
            meal = fixedSlot?.meal ?? .diner
        }
        .onChange(of: mode) { _, new in titleFocused = new == .free }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .recipe:
            List {
                if fixedSlot == nil { whenSection }
                Section {
                    if store.recipes.isEmpty {
                        Text("Aucune recette.").foregroundStyle(Palette.muted)
                    } else if filteredRecipes.isEmpty {
                        Text("Aucune recette ne correspond.").foregroundStyle(Palette.muted)
                    }
                    ForEach(filteredRecipes) { recipe in
                        recipeRow(recipe)
                    }
                }
                .listRowBackground(Palette.card)
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Titre ou ingrédient…"))
        case .free:
            List {
                if fixedSlot == nil { whenSection }
                Section {
                    TextField("Qu'est-ce que tu as prévu ? ex. Haricots verts et poulet", text: $customTitle, axis: .vertical)
                        .font(AppFont.body(16))
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onChange(of: customTitle) { _, v in
                            if v.count > 120 { customTitle = String(v.prefix(120)) }
                        }
                } header: {
                    Text("Un plat sans recette")
                }
                .listRowBackground(Palette.card)
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(freeDishPresets, id: \.self) { preset in
                            Button { customTitle = preset } label: {
                                ChipView(title: preset, isOn: customTitle == preset)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    private var whenSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { d in
                        let s = LocalDay.string(d)
                        Button { day = s } label: {
                            VStack(spacing: 2) {
                                Text(PlanDates.shortWeekday(d)).font(AppFont.body(12, weight: .bold))
                                Text(PlanDates.dayNumber(d)).font(AppFont.body(17, weight: .heavy))
                            }
                            .frame(width: 52, height: 58)
                            .foregroundStyle(day == s ? Palette.onPrimary : Palette.foreground)
                            .background(day == s ? Palette.primary : Palette.chip, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(PlanDates.long(d)))
                        .accessibilityAddTraits(day == s ? .isSelected : [])
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            Picker("Repas", selection: $meal) {
                ForEach(MealType.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Jour")
        }
        .listRowBackground(Palette.card)
    }

    private func recipeRow(_ recipe: Recipe) -> some View {
        let selected = selectedRecipe == recipe.id
        return Button {
            selectedRecipe = selected ? nil : recipe.id
        } label: {
            HStack(spacing: 12) {
                RecipePhotoView(path: recipe.listPhotoPath, category: recipe.primaryCategory, iconSize: 18)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.title)
                        .font(AppFont.body(15, weight: .bold))
                        .foregroundStyle(Palette.foreground)
                        .lineLimit(2)
                    if let minutes = Quantity.duration(recipe.totalMinutes) {
                        Text(minutes).font(AppFont.body(13)).foregroundStyle(Palette.muted)
                    }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Palette.primary : Palette.line)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            ServingsStepper(servings: $servings)
            Button("Ajouter au menu", action: add)
                .buttonStyle(.popotePrimary)
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : 0.5)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func slotTitle(_ slot: MealSlot) -> String {
        guard let d = LocalDay.date(slot.date) else { return slot.meal.label }
        return "\(slot.meal.label) · \(PlanDates.long(d))"
    }

    private func add() {
        guard let date = LocalDay.date(day) else { return }
        let title = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .recipe:
            guard let rid = selectedRecipe else { return }
            store.addMeal(date: date, mealType: meal, recipeId: rid, customTitle: nil, servings: servings)
        case .free:
            guard !title.isEmpty else { return }
            store.addMeal(date: date, mealType: meal, recipeId: nil, customTitle: String(title.prefix(120)), servings: servings)
        }
        onAdded(String(localized: "Ajouté au \(meal.label.lowercased()) du \(PlanDates.long(date))"))
        dismiss()
    }
}

/// Opens a menu entry: edit servings (and the title of a free dish), open the recipe, or remove it.
struct MealEntrySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    let entry: MealPlanEntry
    @State private var servings = 1
    @State private var title = ""

    private var recipe: Recipe? { store.recipe(entry.recipeId) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if entry.recipeId != nil {
                        HStack(spacing: 12) {
                            RecipePhotoView(path: recipe?.listPhotoPath, category: recipe?.primaryCategory ?? .plat, iconSize: 18)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(recipe?.title ?? String(localized: "Recette"))
                                .font(AppFont.display(18, bold: false, relativeTo: .headline))
                        }
                    } else {
                        TextField("Qu'est-ce que tu as prévu ? ex. Haricots verts et poulet", text: $title, axis: .vertical)
                            .font(AppFont.body(16))
                    }
                    ServingsStepper(servings: $servings)
                } header: {
                    if let d = LocalDay.date(entry.date) {
                        Text("\(entry.mealType.label) · \(PlanDates.long(d))")
                    }
                }
                .listRowBackground(Palette.card)

                Section {
                    if let recipe {
                        Button("Voir la recette", systemImage: "book") {
                            dismiss()
                            router.open(recipe: recipe.id)
                        }
                    }
                    Button("Retirer du menu", systemImage: "trash", role: .destructive) {
                        store.deleteMeal(entry.id)
                        dismiss()
                    }
                }
                .listRowBackground(Palette.card)
            }
            .scrollContentBackground(.hidden)
            .popoteBackground()
            .navigationTitle(entry.recipeId == nil ? Text("Plat libre") : Text("Au menu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(entry.recipeId == nil && title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            servings = entry.servings ?? store.defaultServings
            title = entry.customTitle ?? ""
        }
    }

    private func save() {
        var e = entry
        e.servings = servings
        if e.recipeId == nil { e.customTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)) }
        if e != entry { store.updateMeal(e) }
        dismiss()
    }
}
