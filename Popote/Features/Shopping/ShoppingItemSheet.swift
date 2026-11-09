import SwiftUI

/// The details dialog of a shopping item: where it comes from, quantity and unit, "in stock",
/// change aisle (online only) and delete.
struct ShoppingItemSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: ShoppingListItem
    @Binding var toast: PlanToast?

    @State private var quantityText = ""
    @State private var unit = ""
    @State private var inStock = false
    @State private var showAisles = false

    private var sourceTitles: [String] {
        (item.sourceRecipeIds ?? []).compactMap { store.recipe($0)?.title }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vient de") {
                    if !sourceTitles.isEmpty {
                        ForEach(sourceTitles, id: \.self) { Text($0) }
                    } else if item.source == "manuel" {
                        Text("Ajouté à la main").foregroundStyle(Palette.muted)
                    } else {
                        Text(verbatim: "—").foregroundStyle(Palette.muted)
                    }
                }
                .listRowBackground(Palette.card)

                Section {
                    TextField("Quantité", text: $quantityText)
                        .keyboardType(.decimalPad)
                    Picker("Unité", selection: $unit) {
                        Text(verbatim: "—").tag("")
                        ForEach(IngredientUnit.all, id: \.self) { Text(verbatim: $0).tag($0) }
                    }
                    Toggle("Déjà en stock (exclu de la liste)", isOn: $inStock)
                }
                .listRowBackground(Palette.card)

                Section {
                    if item.ingredientId != nil {
                        Button("Changer de rayon", systemImage: "square.grid.2x2") { showAisles = true }
                            .disabled(!store.isOnline)
                        if !store.isOnline {
                            Text("Disponible uniquement en ligne.")
                                .font(AppFont.body(13))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                        store.deleteShoppingItem(item.id)
                        dismiss()
                    }
                }
                .listRowBackground(Palette.card)
            }
            .font(AppFont.body(16))
            .scrollContentBackground(.hidden)
            .popoteBackground()
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                }
            }
            .sheet(isPresented: $showAisles) {
                AislePickerSheet(item: item, toast: $toast)
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            quantityText = item.quantity.map(Self.format) ?? ""
            unit = item.unit ?? ""
            inStock = item.inStock ?? false
        }
    }

    static func format(_ q: Double) -> String {
        q.formatted(.number.precision(.fractionLength(0...2)).locale(AppLanguage.current.locale).grouping(.never))
    }

    static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private func save() {
        var updated = item
        updated.quantity = Self.parse(quantityText)
        updated.unit = unit.isEmpty ? nil : unit
        updated.inStock = inStock
        if updated != item { store.updateShoppingItem(updated) }
        dismiss()
    }
}

/// `Changer de rayon : {name}`: a household-level aisle override via `set_ingredient_category`.
struct AislePickerSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: ShoppingListItem
    @Binding var toast: PlanToast?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(store.orderedAisles) { aisle in
                        let current = store.aisleId(for: item.ingredientId) == aisle.id
                        Button { pick(aisle) } label: {
                            HStack(spacing: 10) {
                                AisleIcon(style: AisleStyle(aisle), size: 30)
                                Text(aisle.displayName)
                                    .font(AppFont.body(14, weight: .bold))
                                    .foregroundStyle(Palette.foreground)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(current ? Palette.primary.opacity(0.12) : Palette.card, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(current ? Palette.primary : Palette.line, lineWidth: current ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(saving || !store.isOnline)
                        .accessibilityAddTraits(current ? .isSelected : [])
                    }
                }
                .padding()
            }
            .popoteBackground()
            .navigationTitle(Text("Changer de rayon : \(item.name)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func pick(_ aisle: IngredientCategory) {
        guard let ingredientId = item.ingredientId else { return }
        saving = true
        Task {
            struct Params: Encodable { let _ingredient: UUID; let _category: String }
            do {
                try await store.client.rpc("set_ingredient_category", params: Params(_ingredient: ingredientId, _category: aisle.id)).execute()
                store.ingredientOverrides.removeAll { $0.ingredientId == ingredientId }
                store.ingredientOverrides.append(HouseholdIngredientOverride(ingredientId: ingredientId, categoryId: aisle.id))
                store.saveSnapshot()
                toast = PlanToast(text: String(localized: "Rayon mis à jour"), systemImage: "checkmark.circle")
                dismiss()
            } catch {
                toast = PlanToast(text: String(localized: "Impossible de changer le rayon"), systemImage: "exclamationmark.triangle")
            }
            saving = false
        }
    }
}
