import SwiftUI

/// The advanced filters panel (SPEC §B.2.1) as a sheet.
struct RecipeFiltersSheet: View {
    @Binding var filters: RecipeFilterState
    let allTags: [String]
    let resultCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("Catégories") {
                        ForEach(RecipeCategory.allCases) { cat in
                            toggleChip(cat.label, isOn: filters.categories.contains(cat)) {
                                if filters.categories.contains(cat) { filters.categories.remove(cat) } else { filters.categories.insert(cat) }
                            }
                        }
                    }
                    section("Saison") {
                        ForEach(Season.allCases.prefix(4)) { s in
                            toggleChip(s.label, isOn: filters.seasons.contains(s)) {
                                if filters.seasons.contains(s) { filters.seasons.remove(s) } else { filters.seasons.insert(s) }
                            }
                        }
                    }
                    section("Temps total max") {
                        ForEach(RecipeFilterState.maxTimeOptions, id: \.self) { m in
                            toggleChip(String(localized: "≤ \(m) min"), isOn: filters.maxTime == m) {
                                filters.maxTime = filters.maxTime == m ? nil : m
                            }
                        }
                    }
                    section("Note minimum") {
                        ForEach(RecipeFilterState.minRatingOptions, id: \.self) { r in
                            let label = r == 4.5 ? String(localized: "4,5★ et +") : String(localized: "\(Int(r))★ et +")
                            toggleChip(label, isOn: filters.minRating == r) {
                                filters.minRating = filters.minRating == r ? nil : r
                            }
                        }
                    }
                    section("Favoris") {
                        toggleChip(String(localized: "Mes favoris ❤️"), isOn: filters.favorites) { filters.favorites.toggle() }
                    }
                    if !allTags.isEmpty {
                        section("Tags") {
                            ForEach(allTags, id: \.self) { tag in
                                toggleChip(tag, isOn: filters.tags.contains(tag)) {
                                    if filters.tags.contains(tag) { filters.tags.remove(tag) } else { filters.tags.insert(tag) }
                                }
                            }
                        }
                    }
                    TermsInput(title: "Contient", placeholder: "ex. tomate", values: $filters.include)
                    TermsInput(title: "Sans", placeholder: "ex. champignon", values: $filters.exclude)
                }
                .padding()
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .popoteBackground()
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if filters.activeCount > 0 {
                        Button("Tout effacer") { withAnimation { filters.clear() } }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() } label: { Text("OK") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { dismiss() } label: {
                    Text(RecipeFormat.recipeCount(resultCount))
                }
                .buttonStyle(.popotePrimary)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFont.display(17, relativeTo: .headline))
                .foregroundStyle(Palette.foreground)
            RecipeFlowLayout { content() }
        }
    }

    private func toggleChip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            ChipView(title: title, isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// Tag input: Return, a comma or leaving the field adds the value; values are removable chips.
private struct TermsInput: View {
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    @Binding var values: [String]
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFont.display(17, relativeTo: .headline))
                .foregroundStyle(Palette.foreground)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .font(AppFont.body(16))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .popoteCard(radius: 14)
                .onSubmit(commit)
                .onChange(of: text) { _, new in if new.contains(",") { commit() } }
                .onChange(of: focused) { _, f in if !f { commit() } }
            if !values.isEmpty {
                RecipeFlowLayout {
                    ForEach(values, id: \.self) { v in
                        Button {
                            withAnimation { values.removeAll { $0 == v } }
                        } label: {
                            ChipView(title: v, systemImage: "xmark", isOn: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Retirer \(v)"))
                    }
                }
            }
        }
    }

    private func commit() {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for p in parts where !values.contains(p) { values.append(p) }
        text = ""
    }
}
