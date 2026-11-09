import SwiftUI

/// A cell of the week grid: one day and one meal.
struct MealSlot: Hashable, Identifiable {
    var date: String
    var meal: MealType
    var id: String { "cell|\(date)|\(meal.rawValue)" }
}

/// `/menu`: the weekly meal plan (SPEC Part B §4). All writes go through the store's optimistic
/// methods, so it works offline.
struct MenuTab: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    @State private var weekStart = LocalDay.weekStart(.now)
    @State private var addSlot: MealSlot?
    @State private var editing: MealPlanEntry?
    @State private var showRecipes = false
    @State private var confirmClear = false
    @State private var toast: PlanToast?
    @State private var dropTarget: MealSlot?
    @State private var changeCount = 0

    private var days: [Date] { (0..<7).map { PlanDates.adding(days: $0, to: weekStart) } }
    private var startString: String { LocalDay.string(weekStart) }
    private var endString: String { LocalDay.string(PlanDates.adding(days: 6, to: weekStart)) }
    private var todayString: String { LocalDay.string(.now) }
    private var isCurrentWeek: Bool { LocalDay.weekStart(.now) == weekStart }
    private var rangeText: String { PlanDates.range(weekStart, PlanDates.adding(days: 6, to: weekStart)) }

    private var weekEntries: [MealPlanEntry] {
        store.mealPlan.filter { $0.date >= startString && $0.date <= endString }
    }

    private func entries(_ slot: MealSlot) -> [MealPlanEntry] {
        store.mealPlan
            .filter { $0.date == slot.date && $0.mealType == slot.meal }
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    weekNavigator
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))

                ForEach(days, id: \.self) { day in
                    daySection(day)
                }

                Section {
                    Text("Glisse un plat d'une case à l'autre pour le déplacer, ou balaie-le pour le retirer.")
                        .font(AppFont.body(13))
                        .foregroundStyle(Palette.muted)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 72, for: .scrollContent)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .popoteBackground()
            .navigationTitle("Menu")
            .toolbar { toolbar }
            .overlay(alignment: .bottomTrailing) { recipesButton }
            .sheet(item: $addSlot) { slot in
                AddMealSheet(fixedSlot: slot, weekStart: weekStart, onAdded: added)
            }
            .sheet(isPresented: $showRecipes) {
                AddMealSheet(fixedSlot: nil, weekStart: weekStart, onAdded: added)
            }
            .sheet(item: $editing) { entry in
                MealEntrySheet(entry: entry)
            }
            .alert("Vider la semaine ?", isPresented: $confirmClear) {
                Button("Annuler", role: .cancel) {}
                Button("Vider", role: .destructive, action: clearWeek)
            } message: {
                Text("Tous les repas du \(rangeText) seront retirés du menu (les recettes restent dans ton livre de cuisine).")
            }
            .planToast($toast)
            .sensoryFeedback(.success, trigger: changeCount)
        }
    }

    // MARK: Header

    private var weekNavigator: some View {
        HStack {
            Button {
                withAnimation(.snappy) { weekStart = PlanDates.adding(days: -7, to: weekStart) }
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Semaine précédente"))

            Spacer()
            VStack(spacing: 2) {
                Text(rangeText)
                    .font(AppFont.display(19, bold: false, relativeTo: .headline))
                    .foregroundStyle(Palette.foreground)
                    .contentTransition(.numericText())
                if !isCurrentWeek {
                    Button("Cette semaine") {
                        withAnimation(.snappy) { weekStart = LocalDay.weekStart(.now) }
                    }
                    .font(AppFont.body(13, weight: .bold))
                }
            }
            Spacer()

            Button {
                withAnimation(.snappy) { weekStart = PlanDates.adding(days: 7, to: weekStart) }
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Semaine suivante"))
        }
        .buttonStyle(.borderless)
        .font(.title3.weight(.semibold))
        .foregroundStyle(Palette.primary)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { SyncStatusButton() }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Copier la semaine précédente", systemImage: "doc.on.doc", action: copyPreviousWeek)
                Button("Vider la semaine", systemImage: "eraser", role: .destructive) { confirmClear = true }
                    .disabled(weekEntries.isEmpty)
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel(Text("Options de la semaine"))
        }
    }

    private var recipesButton: some View {
        Button {
            showRecipes = true
        } label: {
            Label("Recettes", systemImage: "book")
        }
        .buttonStyle(.popotePrimaryCompact)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        .padding(.trailing, 20)
        .padding(.bottom, 16)
        .accessibilityHint(Text("Ajouter une recette au menu"))
    }

    // MARK: Days

    private func daySection(_ day: Date) -> some View {
        let date = LocalDay.string(day)
        let isToday = date == todayString
        return Section {
            ForEach(MealType.allCases) { meal in
                slotRows(MealSlot(date: date, meal: meal))
            }
            .listRowBackground(isToday ? Palette.primary.opacity(0.09) : Palette.card)
        } header: {
            HStack(spacing: 8) {
                Text(PlanDates.dayTitle(day))
                    .font(AppFont.display(17, bold: isToday, relativeTo: .headline))
                    .foregroundStyle(isToday ? Palette.primary : Palette.foreground)
                if isToday {
                    Text("Aujourd'hui")
                        .font(AppFont.body(11, weight: .heavy))
                        .foregroundStyle(Palette.onPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.primary, in: Capsule())
                }
            }
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private func slotRows(_ slot: MealSlot) -> some View {
        let list = entries(slot)
        if list.isEmpty {
            EmptySlotRow(meal: slot.meal, highlighted: dropTarget == slot) { addSlot = slot }
                .dropDestination(for: String.self) { ids, _ in
                    ids.first.map { move($0, to: slot) } ?? false
                } isTargeted: { dropTarget = $0 ? slot : (dropTarget == slot ? nil : dropTarget) }
        } else {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                entryRow(entry, slot: slot, showLabel: index == 0)
            }
        }
    }

    private func entryRow(_ entry: MealPlanEntry, slot: MealSlot, showLabel: Bool) -> some View {
        let recipe = store.recipe(entry.recipeId)
        return Button {
            if let recipe { router.open(recipe: recipe.id) } else { editing = entry }
        } label: {
            MealEntryRow(entry: entry, recipe: recipe, slotLabel: showLabel ? slot.meal.label : nil,
                         highlighted: dropTarget == slot)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Retirer", systemImage: "trash", role: .destructive) { store.deleteMeal(entry.id) }
            Button("Modifier", systemImage: "pencil") { editing = entry }
                .tint(Palette.sage)
        }
        .swipeActions(edge: .leading) {
            Button("Ajouter", systemImage: "plus") { addSlot = slot }
                .tint(Palette.primary)
        }
        .contextMenu {
            if let recipe {
                Button("Voir la recette", systemImage: "book") { router.open(recipe: recipe.id) }
            }
            Button("Modifier", systemImage: "pencil") { editing = entry }
            Button("Plus de personnes", systemImage: "plus") { changeServings(entry, by: 1) }
            Button("Moins de personnes", systemImage: "minus") { changeServings(entry, by: -1) }
                .disabled((entry.servings ?? store.defaultServings) <= 1)
            Button("Dupliquer", systemImage: "plus.square.on.square") { duplicate(entry) }
            Menu("Déplacer vers", systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
                ForEach(days, id: \.self) { day in
                    Menu(PlanDates.dayTitle(day)) {
                        ForEach(MealType.allCases) { meal in
                            Button(meal.label) { _ = move(entry.id.uuidString, to: MealSlot(date: LocalDay.string(day), meal: meal)) }
                        }
                    }
                }
            }
            Button("Ajouter un plat ici", systemImage: "plus.circle") { addSlot = slot }
            Divider()
            Button("Retirer", systemImage: "trash", role: .destructive) { store.deleteMeal(entry.id) }
        }
        .draggable(entry.id.uuidString) {
            MealEntryRow(entry: entry, recipe: recipe, slotLabel: nil, highlighted: false)
                .padding(10)
                .frame(width: 280)
                .popoteCard(radius: 14)
        }
        .dropDestination(for: String.self) { ids, _ in
            ids.first.map { move($0, to: slot) } ?? false
        } isTargeted: { dropTarget = $0 ? slot : (dropTarget == slot ? nil : dropTarget) }
    }

    // MARK: Actions

    private func added(_ message: String) {
        changeCount += 1
        toast = PlanToast(text: message, systemImage: "checkmark.circle")
    }

    /// Moves an entry to another cell, appended at the end (positions are not reordered, like the website).
    private func move(_ idString: String, to slot: MealSlot) -> Bool {
        dropTarget = nil
        guard let id = UUID(uuidString: idString), var entry = store.mealPlan.first(where: { $0.id == id }) else { return false }
        guard entry.date != slot.date || entry.mealType != slot.meal else { return false }
        entry.position = entries(slot).count
        entry.date = slot.date
        entry.mealType = slot.meal
        withAnimation(.snappy) { store.updateMeal(entry) }
        changeCount += 1
        return true
    }

    private func changeServings(_ entry: MealPlanEntry, by delta: Int) {
        var e = entry
        let n = (e.servings ?? store.defaultServings) + delta
        guard n >= 1 else { return }
        e.servings = n
        store.updateMeal(e)
    }

    private func duplicate(_ entry: MealPlanEntry) {
        guard let day = LocalDay.date(entry.date) else { return }
        store.addMeal(date: day, mealType: entry.mealType, recipeId: entry.recipeId,
                      customTitle: entry.customTitle, servings: entry.servings)
        changeCount += 1
    }

    private func clearWeek() {
        let ids = weekEntries.map(\.id)
        withAnimation { ids.forEach(store.deleteMeal) }
        toast = PlanToast(text: String(localized: "Semaine vidée"), systemImage: "eraser")
    }

    private func copyPreviousWeek() {
        let prevStart = LocalDay.string(PlanDates.adding(days: -7, to: weekStart))
        let prevEnd = LocalDay.string(PlanDates.adding(days: -1, to: weekStart))
        let previous = store.mealPlan
            .filter { $0.date >= prevStart && $0.date <= prevEnd }
            .sorted { ($0.date, $0.mealType.rawValue, $0.position ?? 0) < ($1.date, $1.mealType.rawValue, $1.position ?? 0) }
        guard !previous.isEmpty else {
            toast = PlanToast(text: String(localized: "La semaine précédente est vide"), systemImage: "info.circle")
            return
        }
        withAnimation {
            for e in previous {
                guard let d = LocalDay.date(e.date) else { continue }
                store.addMeal(date: PlanDates.adding(days: 7, to: d), mealType: e.mealType, recipeId: e.recipeId,
                              customTitle: e.customTitle, servings: e.servings)
            }
        }
        changeCount += 1
        toast = PlanToast(text: String(localized: "\(previous.count) repas copiés"), systemImage: "doc.on.doc")
    }
}

// MARK: - Rows

private let slotLabelWidth: CGFloat = 74

private struct SlotLabel: View {
    let text: String?
    var body: some View {
        Text(text?.uppercased() ?? "")
            .font(AppFont.body(11, weight: .heavy, relativeTo: .caption))
            .foregroundStyle(Palette.muted)
            .frame(width: slotLabelWidth, alignment: .leading)
            .accessibilityHidden(text == nil)
    }
}

struct EmptySlotRow: View {
    let meal: MealType
    var highlighted = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SlotLabel(text: meal.label)
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Ajouter")
                }
                .font(AppFont.body(14, weight: .bold))
                .foregroundStyle(highlighted ? Palette.primary : Palette.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(highlighted ? Palette.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(highlighted ? Palette.primary : Palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Ajouter un plat : \(meal.label)"))
        }
        .padding(.vertical, 2)
    }
}

struct MealEntryRow: View {
    @Environment(AppStore.self) private var store
    let entry: MealPlanEntry
    let recipe: Recipe?
    var slotLabel: String?
    var highlighted = false

    private var title: String {
        if entry.recipeId != nil { return recipe?.title ?? String(localized: "Recette") }
        return entry.customTitle ?? ""
    }

    var body: some View {
        HStack(spacing: 10) {
            SlotLabel(text: slotLabel)
            thumbnail
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(AppFont.body(15, weight: .bold))
                    .italic(entry.recipeId == nil)
                    .foregroundStyle(Palette.foreground)
                    .lineLimit(2)
                Text("· \(entry.servings ?? store.defaultServings) pers.")
                    .font(AppFont.body(13, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .background(highlighted ? Palette.primary.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(slotLabel ?? entry.mealType.label), \(title), \(entry.servings ?? store.defaultServings) personnes"))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if entry.recipeId != nil {
            RecipePhotoView(path: recipe?.listPhotoPath, category: recipe?.primaryCategory ?? .plat, iconSize: 18)
        } else {
            ZStack {
                Palette.chip
                Image(systemName: "note.text").foregroundStyle(Palette.muted)
            }
        }
    }
}
