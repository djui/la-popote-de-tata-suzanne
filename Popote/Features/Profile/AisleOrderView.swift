import SwiftUI

/// "Mon magasin": drag the aisles into the order of your supermarket (SPEC §B.6.3).
struct AisleOrderView: View {
    @Environment(AppStore.self) private var store
    @State private var aisles: [IngredientCategory] = []
    @State private var banner: ProfileBanner?
    @State private var moves = 0

    var body: some View {
        List {
            Section {
                ForEach(aisles) { aisle in
                    HStack(spacing: 12) {
                        AisleIcon(style: AisleStyle(aisle), size: 32)
                        Text(aisle.displayName)
                            .font(AppFont.body(16, weight: .semibold))
                    }
                    .padding(.vertical, 2)
                }
                .onMove(perform: move)
                .moveDisabled(!store.isOnline)
            } header: {
                Text("Glisse les rayons dans l'ordre de ton supermarché, le panier suivra.")
                    .font(AppFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(Palette.muted)
                    .textCase(nil)
            } footer: {
                if !store.isOnline { OfflineHint() }
            }
            .listRowBackground(Palette.card)
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .popoteBackground()
        .navigationTitle("Mon magasin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    reset()
                } label: {
                    Label("Par défaut", systemImage: "arrow.counterclockwise")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(!store.isOnline || store.categoryOrders.isEmpty)
            }
        }
        .overlay {
            if aisles.isEmpty {
                ContentUnavailableView("Aucun rayon", systemImage: "cart",
                                       description: Text("Les rayons apparaîtront après la synchronisation."))
            }
        }
        .sensoryFeedback(.selection, trigger: moves)
        .profileBanner($banner)
        .onAppear { aisles = store.orderedAisles }
        .onChange(of: store.categoryOrders) { aisles = store.orderedAisles }
        .onChange(of: store.aisles) { aisles = store.orderedAisles }
    }

    private func move(from source: IndexSet, to destination: Int) {
        aisles.move(fromOffsets: source, toOffset: destination)
        moves += 1
        let ordered = aisles
        Task {
            do {
                try await store.saveAisleOrder(ordered)
            } catch {
                aisles = store.orderedAisles
                banner = .error(String(localized: "Impossible d'enregistrer l'ordre"))
            }
        }
    }

    private func reset() {
        Task {
            do {
                try await store.resetAisleOrder()
                aisles = store.orderedAisles
                banner = ProfileBanner(text: String(localized: "Ordre par défaut rétabli"))
            } catch {
                banner = .error(error.localizedDescription)
            }
        }
    }
}
