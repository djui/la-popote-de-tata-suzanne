import SwiftUI

/// "Supprimer mon compte" (SPEC §C.7 item 9). Calls the `deleteAccount` server function, then signs out.
struct AccountDeletionSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var keepRecipes = false
    @State private var confirmation = ""
    @State private var isDeleting = false
    @State private var error: String?

    static let confirmationWord = "SUPPRIMER"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Cette action est définitive. Tes données personnelles et tes photos privées seront effacées.")
                        .font(AppFont.body(15))
                }
                .listRowBackground(Palette.card)

                Section {
                    Picker(selection: $keepRecipes) {
                        Text("Supprimer aussi mes recettes").tag(false)
                        Text("Les laisser à la communauté de façon anonyme").tag(true)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Tes recettes partagées")
                }
                .listRowBackground(Palette.card)

                Section {
                    TextField(Self.confirmationWord, text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Écris SUPPRIMER pour confirmer")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let error { Text(error).foregroundStyle(Palette.destructive) }
                        if !store.isOnline { OfflineHint() }
                    }
                }
                .listRowBackground(Palette.card)

                Section {
                    Button(role: .destructive) {
                        delete()
                    } label: {
                        HStack {
                            Spacer()
                            if isDeleting {
                                ProgressView()
                                Text("Suppression…")
                            } else {
                                Text("Supprimer définitivement").bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(confirmation != Self.confirmationWord || isDeleting || !store.isOnline)
                }
                .listRowBackground(Palette.card)
            }
            .scrollContentBackground(.hidden)
            .popoteBackground()
            .navigationTitle("Supprimer mon compte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .interactiveDismissDisabled(isDeleting)
        }
    }

    private func delete() {
        guard confirmation == Self.confirmationWord else { return }
        isDeleting = true
        error = nil
        Task {
            do {
                try await store.deleteAccount(keepRecipes: keepRecipes)
                // Signing out swaps the root view to the auth screen, which closes this sheet.
            } catch {
                isDeleting = false
                self.error = String(localized: "La suppression n’a pas pu être terminée. Réessaie.")
            }
        }
    }
}
