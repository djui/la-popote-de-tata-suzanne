import SwiftUI

/// `AddToMenuDialog` (SPEC §A.7) as a sheet. Works offline through the store's outbox.
struct AddToMenuSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    /// Receives the confirmation text ("Ajouté au dîner du lundi 3 nov.").
    var onAdded: (String) -> Void = { _ in }

    @State private var dayIndex = 0
    @State private var mealType: MealType = .diner
    @State private var servings = 4
    @State private var added = false

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        RecipePhotoView(path: recipe.listPhotoPath, category: recipe.primaryCategory, iconSize: 20)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(recipe.title)
                            .font(AppFont.body(16, weight: .heavy, relativeTo: .headline))
                            .lineLimit(2)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Jour")
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                                        dayChip(d, selected: i == dayIndex) { dayIndex = i }
                                            .id(i)
                                    }
                                }
                                .padding(.horizontal, 2)
                            }
                            .onAppear { proxy.scrollTo(dayIndex) }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Repas")
                        Picker("Repas", selection: $mealType) {
                            ForEach(MealType.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Personnes")
                        ServingsStepperPill(value: $servings)
                    }
                }
                .padding()
            }
            .popoteBackground()
            .navigationTitle("Ajouter au menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Annuler") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Ajouter", action: add)
                    .buttonStyle(.popotePrimary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .sensoryFeedback(.success, trigger: added)
        }
        .presentationDetents([.medium, .large])
        .onAppear { servings = store.defaultServings }
    }

    private func sectionTitle(_ t: LocalizedStringKey) -> some View {
        Text(t).font(AppFont.display(17, relativeTo: .headline)).foregroundStyle(Palette.foreground)
    }

    private func dayChip(_ date: Date, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).capitalized)
                    .font(AppFont.body(12, weight: .semibold, relativeTo: .caption))
                Text(date.formatted(.dateTime.day()))
                    .font(AppFont.body(18, weight: .heavy))
            }
            .frame(width: 54, height: 60)
            .foregroundStyle(selected ? Palette.onPrimary : Palette.foreground)
            .background(selected ? Palette.primary : Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? .clear : Palette.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide))))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func add() {
        let date = days[dayIndex]
        store.addMeal(date: date, mealType: mealType, recipeId: recipe.id, customTitle: nil, servings: servings)
        added = true
        let day = date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        onAdded(String(localized: "Ajouté au \(mealType.label.lowercased()) du \(day)"))
        dismiss()
    }
}
