import SwiftUI

/// `Signaler un contenu` (SPEC §A.12). Online only.
struct ReportRecipeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recipe: Recipe
    var onSent: (String) -> Void = { _ in }

    @State private var reason: ReportReason = .copyright
    @State private var details = ""
    @State private var sending = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(recipe.title).font(AppFont.body(15, weight: .bold)).foregroundStyle(Palette.muted)
                }
                Section("Motif") {
                    Picker("Motif", selection: $reason) {
                        ForEach(ReportReason.allCases) { r in Text(label(r)).tag(r) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    TextField("Précisions (facultatif)", text: $details, axis: .vertical)
                        .lineLimit(4...10)
                        .onChange(of: details) { _, v in if v.count > 2000 { details = String(v.prefix(2000)) } }
                } header: {
                    Text("Précisions (facultatif)")
                } footer: {
                    Text(verbatim: "\(details.count)/2000").monospacedDigit()
                }
                if !store.isOnline {
                    Section { OfflineNotice() }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Palette.destructive) }
                }
            }
            .scrollContentBackground(.hidden)
            .popoteBackground()
            .navigationTitle("Signaler un contenu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Text("Annuler") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    send()
                } label: {
                    if sending { ProgressView().tint(Palette.onPrimary) } else { Text("Envoyer le signalement") }
                }
                .buttonStyle(.popotePrimary)
                .disabled(sending || !store.isOnline)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }

    private func label(_ r: ReportReason) -> String {
        switch r {
        case .copyright: String(localized: "Droits d'auteur")
        case .inappropriate: String(localized: "Contenu inapproprié")
        case .error: String(localized: "Erreur")
        }
    }

    private func send() {
        sending = true
        errorText = nil
        Task {
            do {
                try await store.reportRecipe(recipe, reason: reason, details: details)
                onSent(String(localized: "Signalement envoyé"))
                dismiss()
            } catch {
                errorText = String(localized: "Signalement impossible")
            }
            sending = false
        }
    }
}
