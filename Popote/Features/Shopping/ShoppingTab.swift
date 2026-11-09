import SwiftUI
import UIKit

/// `/courses`: the shopping list (SPEC Part B §5). Generation, quick add and every edit run offline
/// from the store's cached data and go through its optimistic methods.
struct ShoppingTab: View {
    @Environment(AppStore.self) private var store

    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var end = PlanDates.adding(days: 6, to: Calendar.current.startOfDay(for: .now))
    @State private var draft = ""
    @State private var showBought = false
    @State private var details: ShoppingListItem?
    @State private var toast: PlanToast?
    @State private var checkTick = 0
    @State private var generateTick = 0
    @State private var exporting = false
    @State private var remindersDenied = false
    @FocusState private var addFocused: Bool

    private var weekStart: String { LocalDay.weekStartString(start) }
    private var items: [ShoppingListItem] { store.shoppingItems(week: weekStart) }
    private var toBuy: [ShoppingListItem] { items.filter { !$0.checked && $0.inStock != true } }
    private var bought: [ShoppingListItem] {
        items.filter { $0.checked && $0.inStock != true }
            .sorted { ($0.checkedAt ?? .distantPast) > ($1.checkedAt ?? .distantPast) }
    }
    private var inStock: [ShoppingListItem] { items.filter { $0.inStock == true } }

    private var isDefaultPeriod: Bool {
        let today = Calendar.current.startOfDay(for: .now)
        return Calendar.current.isDate(start, inSameDayAs: today) && Calendar.current.isDate(end, inSameDayAs: PlanDates.adding(days: 6, to: today))
    }

    private var rangeText: String {
        String(localized: "Du \(PlanDates.dayMonth(start)) au \(PlanDates.dayMonth(end))")
    }

    private var sections: [ShoppingListBuilder.AisleSection] {
        ShoppingListBuilder.group(toBuy, aisles: store.orderedAisles.map { (id: $0.id, name: $0.displayName) },
                                  otherName: String(localized: "Autre")) { store.aisleId(for: $0.ingredientId) }
    }

    private var aislesById: [String: IngredientCategory] {
        Dictionary(store.aisles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// How often each ingredient was bought (checked), like the `['shopping-frequency']` query.
    private var frequency: [UUID: Int] {
        store.shoppingItems.reduce(into: [:]) { acc, item in
            if item.checked, let id = item.ingredientId { acc[id, default: 0] += 1 }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                addSection

                if toBuy.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("Le panier est vide, Tata Suzanne serait fière de toi !", systemImage: "basket")
                                .font(AppFont.display(19, bold: false, relativeTo: .headline))
                        }
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                } else {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        aisleSection(section, first: index == 0)
                    }
                }

                if !bought.isEmpty { boughtSection }
                if !inStock.isEmpty { inStockSection }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .popoteBackground()
            .navigationTitle("Courses")
            .toolbar { toolbar }
            .sheet(item: $details) { ShoppingItemSheet(item: $0, toast: $toast) }
            .alert("Accès aux Rappels refusé", isPresented: $remindersDenied) {
                Button("Ouvrir les Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Autorise La Popote à accéder à tes rappels dans les Réglages pour y exporter ta liste.")
            }
            .planToast($toast)
            .sensoryFeedback(.impact(weight: .light), trigger: checkTick)
            .sensoryFeedback(.success, trigger: generateTick)
            .task { housekeeping() }
            .onChange(of: start) { _, new in if new > end { end = new } }
            .onChange(of: end) { _, new in if new < start { start = new } }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(rangeText) · \(items.count) article(s)")
                    .font(AppFont.body(15, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                HStack(spacing: 6) {
                    DatePicker("Du", selection: $start, displayedComponents: .date)
                        .fixedSize()
                    DatePicker("au", selection: $end, displayedComponents: .date)
                        .fixedSize()
                    Spacer(minLength: 0)
                }
                .font(AppFont.body(14, weight: .semibold))
                .environment(\.locale, AppLanguage.current.locale)
                if !isDefaultPeriod {
                    Button("Cette semaine") {
                        withAnimation {
                            start = Calendar.current.startOfDay(for: .now)
                            end = PlanDates.adding(days: 6, to: start)
                        }
                    }
                    .font(AppFont.body(14, weight: .bold))
                    .buttonStyle(.borderless)
                }
                Button(action: generate) {
                    Label("Générer depuis le menu", systemImage: "wand.and.stars")
                }
                .buttonStyle(.popotePrimary)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
    }

    // MARK: Quick add

    private var parsedDraft: ShoppingListBuilder.ParsedItem { ShoppingListBuilder.parseQuick(draft) }

    private var suggestions: [Ingredient] {
        ShoppingListBuilder.searchIngredients(store.ingredients, query: parsedDraft.name, frequency: frequency)
    }

    private var quickChips: [Ingredient] {
        let onList = Set(toBuy.compactMap(\.ingredientId))
        return frequency.filter { $0.value >= 2 && !onList.contains($0.key) }
            .sorted { $0.value > $1.value }
            .compactMap { store.ingredient($0.key) }
            .prefix(8).map { $0 }
    }

    @ViewBuilder
    private var addSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("Que veux-tu acheter ?", text: $draft)
                    .font(AppFont.body(16))
                    .focused($addFocused)
                    .submitLabel(.done)
                    .onSubmit { addFromDraft(nil) }
                    .accessibilityLabel(Text("Que veux-tu acheter ?"))
                    .padding(.horizontal, 18)
                    .frame(minHeight: 48)
                    .background(Palette.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.line))
                Button { addFromDraft(nil) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Palette.onPrimary)
                        .frame(width: 48, height: 48)
                        .background(Palette.primary, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("Ajouter"))
            }

            if draft.trimmingCharacters(in: .whitespaces).isEmpty {
                if !quickChips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickChips) { ing in
                                Button { addFromDraft(ing, text: ing.displayName ?? ing.name) } label: {
                                    ChipView(title: "+ \(ing.displayName ?? ing.name)")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(suggestions) { ing in
                        Button { addFromDraft(ing) } label: {
                            HStack(spacing: 10) {
                                AisleIcon(style: AisleStyle(store.aisleId(for: ing.id).flatMap { aislesById[$0] }), size: 24)
                                Text(ing.displayName ?? ing.name).font(AppFont.body(15, weight: .semibold))
                                Spacer()
                                if (frequency[ing.id] ?? 0) > 0 {
                                    Text("souvent acheté").font(AppFont.body(12)).foregroundStyle(Palette.muted)
                                }
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                    if ShoppingListBuilder.exactIngredient(named: parsedDraft.name, in: store.ingredients) == nil {
                        Button { addFromDraft(nil) } label: {
                            Label("Ajouter « \(parsedDraft.name) »", systemImage: "plus")
                                .font(AppFont.body(15, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.primary)
                    }
                }
                .padding(.horizontal, 14)
                .popoteCard(radius: 14)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    // MARK: Sections

    private func aisleSection(_ section: ShoppingListBuilder.AisleSection, first: Bool) -> some View {
        Section {
            ForEach(section.items) { item in
                row(item)
            }
        } header: {
            VStack(alignment: .leading, spacing: 10) {
                if first {
                    Text("À acheter · \(toBuy.count) article(s) restant(s)")
                        .font(AppFont.display(18, bold: false, relativeTo: .headline))
                        .foregroundStyle(Palette.foreground)
                }
                HStack(spacing: 8) {
                    AisleIcon(style: AisleStyle(section.id.flatMap { aislesById[$0] }), size: 22)
                    Text(section.name.uppercased())
                        .font(AppFont.body(12, weight: .heavy, relativeTo: .caption))
                        .foregroundStyle(Palette.muted)
                }
            }
            .textCase(nil)
        }
        .listRowBackground(Palette.card)
    }

    private var boughtSection: some View {
        Section {
            if showBought {
                ForEach(bought) { row($0) }
            }
        } header: {
            HStack {
                Button {
                    withAnimation(.snappy) { showBought.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Acheté récemment · \(bought.count)")
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(showBought ? 90 : 0))
                            .imageScale(.small)
                    }
                    .font(AppFont.body(14, weight: .bold))
                    .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Vider", systemImage: "trash") {
                    withAnimation { bought.map(\.id).forEach(store.deleteShoppingItem) }
                }
                .font(AppFont.body(13, weight: .bold))
                .foregroundStyle(Palette.destructive)
                .buttonStyle(.borderless)
            }
            .textCase(nil)
        }
        .listRowBackground(Palette.card)
    }

    private var inStockSection: some View {
        Section {
            ForEach(inStock) { row($0) }
        } header: {
            Text("Déjà en stock (\(inStock.count))")
                .font(AppFont.body(14, weight: .bold))
                .foregroundStyle(Palette.muted)
                .textCase(nil)
        }
        .listRowBackground(Palette.card)
    }

    private func row(_ item: ShoppingListItem) -> some View {
        ShoppingItemRow(item: item, onToggle: { toggle(item) }, onDetails: { details = item })
            .swipeActions(edge: .trailing) {
                Button("Supprimer", systemImage: "trash", role: .destructive) {
                    withAnimation { store.deleteShoppingItem(item.id) }
                }
                Button("Détails", systemImage: "slider.horizontal.3") { details = item }
                    .tint(Palette.sage)
            }
            .swipeActions(edge: .leading) {
                Button(item.inStock == true ? "À acheter" : "En stock",
                       systemImage: item.inStock == true ? "cart.badge.plus" : "archivebox") { toggleStock(item) }
                    .tint(Palette.primary)
            }
            .contextMenu {
                Button(item.checked ? "Remettre dans la liste" : "Acheté", systemImage: item.checked ? "arrow.uturn.backward" : "checkmark.circle") { toggle(item) }
                Button("Modifier", systemImage: "pencil") { details = item }
                Button(item.inStock == true ? "Remettre dans la liste" : "Déjà en stock", systemImage: "archivebox") { toggleStock(item) }
                Divider()
                Button("Supprimer", systemImage: "trash", role: .destructive) { store.deleteShoppingItem(item.id) }
            }
    }

    // MARK: Toolbar

    private var shareText: String {
        ShoppingListBuilder.shareText(
            title: String(localized: "Courses du \(PlanDates.dayMonth(start)) au \(PlanDates.dayMonth(end))"),
            sections: sections)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { SyncStatusButton() }
        ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: shareText) {
                Label("Partager la liste", systemImage: "square.and.arrow.up")
            }
            .disabled(toBuy.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Exporter vers Rappels", systemImage: "checklist", action: exportToReminders)
                    .disabled(toBuy.isEmpty || exporting)
                Button("Vider les articles achetés", systemImage: "trash", role: .destructive) {
                    bought.map(\.id).forEach(store.deleteShoppingItem)
                }
                .disabled(bought.isEmpty)
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel(Text("Plus d'options"))
        }
    }

    // MARK: Actions

    private func toggle(_ item: ShoppingListItem) {
        let previous = item
        withAnimation(.snappy) { store.setChecked(item.id, !item.checked) }
        checkTick += 1
        let text = item.checked ? String(localized: "\(item.name) remis dans la liste") : String(localized: "\(item.name) acheté")
        toast = PlanToast(text: text, systemImage: item.checked ? "arrow.uturn.backward" : "checkmark.circle",
                          actionTitle: "Annuler") {
            guard var current = store.shoppingItems.first(where: { $0.id == previous.id }) else { return }
            current.checked = previous.checked
            current.checkedAt = previous.checkedAt
            current.checkedBy = previous.checkedBy
            withAnimation(.snappy) { store.updateShoppingItem(current) }
        }
    }

    private func toggleStock(_ item: ShoppingListItem) {
        var i = item
        i.inStock = !(item.inStock ?? false)
        withAnimation(.snappy) { store.updateShoppingItem(i) }
    }

    private func addFromDraft(_ picked: Ingredient?, text: String? = nil) {
        let parsed = ShoppingListBuilder.parseQuick(text ?? draft)
        guard !parsed.name.isEmpty else { return }
        let ingredient = picked ?? ShoppingListBuilder.exactIngredient(named: parsed.name, in: store.ingredients)
        let item = ShoppingListItem(
            id: UUID(), weekStart: weekStart, name: ingredient.map { $0.displayName ?? $0.name } ?? parsed.name,
            quantity: parsed.quantity, unit: parsed.unit, ingredientId: ingredient?.id, itemKey: nil,
            source: "manuel", sourceRecipeIds: [], checked: false, checkedAt: nil, checkedBy: nil,
            inStock: false, createdAt: .now)
        withAnimation(.snappy) { store.addShoppingItem(item) }
        if text == nil { draft = "" }
    }

    private func generate() {
        let recipeServings = Dictionary(store.recipes.map { ($0.id, $0.servings) }, uniquingKeysWith: { a, _ in a })
        let rows = ShoppingListBuilder.menuRows(entries: store.mealPlan, from: LocalDay.string(start), to: LocalDay.string(end),
                                                recipeServings: recipeServings, ingredientsByRecipe: store.ingredientsByRecipe)
        guard !rows.isEmpty else {
            toast = PlanToast(text: String(localized: "Aucune recette au menu sur ces jours"), systemImage: "info.circle")
            return
        }
        let computed = ShoppingListBuilder.aggregate(rows, defaultServings: store.defaultServings)
        let plan = ShoppingListBuilder.plan(existing: items, computed: computed, weekStart: weekStart,
                                            displayName: { store.ingredient($0)?.displayName })
        withAnimation(.snappy) {
            plan.deletes.forEach(store.deleteShoppingItem)
            for item in plan.updates where item != store.shoppingItems.first(where: { $0.id == item.id }) {
                store.updateShoppingItem(item)
            }
            plan.inserts.forEach(store.addShoppingItem)
        }
        generateTick += 1
        toast = PlanToast(text: String(localized: "Liste générée : \(computed.count) articles"), systemImage: "wand.and.stars")
    }

    /// Like the website on mount: checked items older than 7 days are removed.
    private func housekeeping() {
        let limit = Date.now.addingTimeInterval(-7 * 24 * 3600)
        let stale = store.shoppingItems.filter { $0.checked && ($0.checkedAt ?? .distantFuture) < limit }
        stale.map(\.id).forEach(store.deleteShoppingItem)
    }

    private func exportToReminders() {
        let titles = sections.flatMap(\.items).map(ShoppingListBuilder.line)
        exporting = true
        Task {
            let outcome = await RemindersExporter.export(titles: titles)
            exporting = false
            switch outcome {
            case let .exported(added, _):
                toast = PlanToast(text: String(localized: "\(added) rappel(s) ajouté(s) dans « \(RemindersExporter.listTitle) »"),
                                  systemImage: "checklist")
            case .denied:
                remindersDenied = true
            case .failed:
                toast = PlanToast(text: String(localized: "L'export vers Rappels a échoué"), systemImage: "exclamationmark.triangle")
            }
        }
    }
}

// MARK: - Row

struct ShoppingItemRow: View {
    let item: ShoppingListItem
    var onToggle: () -> Void
    var onDetails: () -> Void

    var body: some View {
        let f = Quantity.formatIngredient(item.quantity, unit: item.unit, name: item.name)
        HStack(spacing: 12) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(item.checked ? Palette.sage : Palette.line)
                        .contentTransition(.symbolEffect(.replace))
                    Text(f.name)
                        .font(AppFont.body(16, weight: .semibold))
                        .foregroundStyle(item.checked ? Palette.muted : Palette.foreground)
                        .strikethrough(item.checked, color: Palette.muted)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if !f.qty.isEmpty {
                        Text(f.qty)
                            .font(AppFont.body(15, weight: .bold))
                            .foregroundStyle(Palette.muted)
                            .monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(f.qty.isEmpty ? f.name : "\(f.name), \(f.qty)"))
            .accessibilityValue(item.checked ? Text("Acheté") : Text("À acheter"))
            .accessibilityHint(Text("Touche deux fois pour cocher ou décocher"))

            Button(action: onDetails) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 19))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Détails \(item.name)"))
        }
        .padding(.vertical, 2)
    }
}
