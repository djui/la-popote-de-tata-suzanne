import SwiftUI

struct InvitationCode: Identifiable, Hashable {
    let code: String
    var id: String { code }
}

/// Opened from an invitation link (`/invitation/<code>`), SPEC §C.8.
struct InvitationSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    let code: String

    enum Phase: Equatable {
        case loading, notFound, alreadyMember(String), expired(String), valid(InvitationInfo), failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var confirm = false
    @State private var isAccepting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ProfileTile(systemImage: "person.2.fill", size: 80)
                        .padding(.top, 24)
                    content
                    if let error {
                        Text(error)
                            .font(AppFont.body(14))
                            .foregroundStyle(Palette.destructive)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity)
                .popoteCard(radius: 28)
                .padding()
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .popoteBackground()
            .navigationTitle("Invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Retour au profil") { close() }
                }
            }
            .task(id: store.isOnline) { await load() }
            .alert("Rejoindre ce foyer ?", isPresented: $confirm) {
                Button("Annuler", role: .cancel) {}
                Button("Rejoindre") { accept() }
            } message: {
                Text("Tu quitteras ton foyer actuel : son menu et sa liste de courses ne te seront plus visibles.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var content: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Chargement…")
            case .notFound:
                Text("Cette invitation n'existe pas.")
            case .alreadyMember(let name):
                Text("Tu fais déjà partie de « \(name) ».")
            case .expired(let inviter):
                Text("Cette invitation a expiré. Demandes-en une nouvelle à \(inviter).")
            case .failed(let message):
                VStack(spacing: 12) {
                    Text(message)
                    Button("Réessayer") { Task { await load() } }
                        .buttonStyle(.popoteSecondary)
                        .disabled(!store.isOnline)
                }
            case .valid(let info):
                VStack(spacing: 20) {
                    Text("**\(info.inviter ?? "?")** t'invite à rejoindre **« \(info.householdName ?? "") »** pour partager le menu et la liste de courses.")
                    Button {
                        confirm = true
                    } label: {
                        if isAccepting { ProgressView() } else { Text("Rejoindre le foyer") }
                    }
                    .buttonStyle(.popotePrimary)
                    .disabled(isAccepting || !store.isOnline)
                    if !store.isOnline { OfflineHint() }
                }
            }
        }
        .font(AppFont.body(17))
        .foregroundStyle(Palette.foreground)
        .multilineTextAlignment(.center)
    }

    private func load() async {
        guard store.isOnline else {
            if phase == .loading { phase = .failed(String(localized: "Tu es hors ligne. Reviens quand le réseau est disponible.")) }
            return
        }
        phase = .loading
        do {
            guard let info = try await store.invitationInfo(code: code) else { phase = .notFound; return }
            if info.alreadyMember == true {
                phase = .alreadyMember(info.householdName ?? "")
            } else if info.expired == true {
                phase = .expired(info.inviter ?? "")
            } else {
                phase = .valid(info)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func accept() {
        guard case .valid = phase else { return }
        isAccepting = true
        error = nil
        Task {
            defer { isAccepting = false }
            do {
                try await store.acceptInvitation(code: code)
                router.pendingInvitation = nil
                router.tab = .menu
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func close() {
        router.pendingInvitation = nil
        dismiss()
    }
}
