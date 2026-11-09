import SwiftUI
import UIKit

/// "Ma famille": members, invitations sent and received, leaving the household (SPEC §B.6.2, §C.7).
struct HouseholdSection: View {
    @Environment(AppStore.self) private var store
    @Binding var banner: ProfileBanner?

    @State private var inviteEmail = ""
    @State private var isInviting = false
    @State private var lastLink: URL?
    @State private var invitations: [HouseholdInvitation] = []
    @State private var incoming: [IncomingInvitation] = []
    @State private var memberToRemove: HouseholdMember?
    @State private var confirmLeave = false
    @State private var acceptCode: IncomingInvitation?

    var body: some View {
        Section {
            if let name = store.household?.name {
                Text("\(name) — le menu et la liste de courses sont partagés entre tous les membres.")
                    .font(AppFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(Palette.muted)
            }

            ForEach(incoming) { inv in
                VStack(alignment: .leading, spacing: 10) {
                    Text("**\(inv.inviter ?? "?")** t'invite à rejoindre « \(inv.householdName ?? "") »")
                        .font(AppFont.body(15))
                    Button("Rejoindre") { acceptCode = inv }
                        .buttonStyle(.popotePrimaryCompact)
                        .disabled(!store.isOnline)
                }
                .padding(.vertical, 6)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.primary, lineWidth: 1.5)
                        .background(Palette.card)
                )
            }

            ForEach(store.members) { member in
                memberRow(member)
            }
        } header: {
            ProfileSectionHeader(title: "Ma famille", systemImage: "person.2")
        }
        .listRowBackground(Palette.card)

        Section {
            TextField("email@exemple.fr", text: $inviteEmail)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit { invite(email: inviteEmail) }
                .font(AppFont.body(16))

            Button {
                invite(email: inviteEmail)
            } label: {
                Label("Inviter", systemImage: "envelope")
            }
            .disabled(!canInviteByEmail)

            Button {
                invite(email: nil)
            } label: {
                Label("Copier un lien d'invitation", systemImage: "doc.on.doc")
            }
            .disabled(!store.isOnline || isInviting || store.household == nil)

            if let lastLink {
                ShareLink(item: lastLink, subject: Text("La Popote de Tata Suzanne"),
                          message: Text("Rejoins mon foyer sur La Popote de Tata Suzanne")) {
                    Label("Partager le lien", systemImage: "square.and.arrow.up")
                }
            }

            ForEach(invitations) { inv in
                invitationRow(inv)
            }

            if store.members.count > 1 {
                Button("Quitter le foyer", role: .destructive) { confirmLeave = true }
                    .disabled(!store.isOnline)
            }
        } header: {
            Text("Inviter un membre")
                .font(AppFont.body(13, weight: .bold, relativeTo: .footnote))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Valable 7 jours. La personne invitée par email verra aussi l'invitation dans son Profil.")
                if !store.isOnline { OfflineHint() }
            }
            .font(AppFont.body(12, relativeTo: .caption))
        }
        .listRowBackground(Palette.card)
        .task(id: "\(store.isOnline)-\(store.household?.id.uuidString ?? "-")") { await load() }
        .confirmationDialog(removeTitle, isPresented: removeBinding, titleVisibility: .visible, presenting: memberToRemove) { member in
            Button("Retirer", role: .destructive) { remove(member) }
            Button("Annuler", role: .cancel) {}
        }
        .alert(leaveTitle, isPresented: $confirmLeave) {
            Button("Annuler", role: .cancel) {}
            Button("Quitter", role: .destructive) { leave() }
        } message: {
            Text("Tu retrouveras un foyer personnel vide. Le menu et la liste partagés restent aux autres membres.")
        }
        .alert("Rejoindre ce foyer ?", isPresented: acceptBinding, presenting: acceptCode) { inv in
            Button("Annuler", role: .cancel) {}
            Button("Rejoindre") { accept(inv) }
        } message: { _ in
            Text("Tu quitteras ton foyer actuel : son menu et sa liste de courses ne te seront plus visibles.")
        }
    }

    // MARK: Rows

    private func memberRow(_ member: HouseholdMember) -> some View {
        let name = store.memberName(member)
        let isMe = member.userId == store.userId
        return HStack(spacing: 12) {
            Text(InvitationLink.initials(name))
                .font(AppFont.body(14, weight: .heavy))
                .foregroundStyle(Palette.onPrimary)
                .frame(width: 38, height: 38)
                .background(Palette.primary, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(isMe ? "\(name) (moi)" : "\(name)")
                    .font(AppFont.body(16, weight: .bold))
                Text(member.role == "owner" ? "Propriétaire" : "Membre")
                    .font(AppFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            if store.isHouseholdOwner && !isMe {
                Button {
                    memberToRemove = member
                } label: {
                    Image(systemName: "person.badge.minus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.destructive)
                .disabled(!store.isOnline)
                .accessibilityLabel(Text("Retirer \(name)"))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func invitationRow(_ inv: HouseholdInvitation) -> some View {
        let link = InvitationLink.url(code: inv.code)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: inv.code)
                    .font(.system(.subheadline, design: .monospaced))
                    .textSelection(.enabled)
                Group {
                    if let email = inv.email { Text(verbatim: email) } else { Text("lien") }
                }
                .font(AppFont.body(13, relativeTo: .footnote))
                .foregroundStyle(Palette.muted)
            }
            Spacer()
            Button {
                UIPasteboard.general.url = link
                banner = ProfileBanner(text: String(localized: "Lien copié"))
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Copier"))
            ShareLink(item: link) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Partager le lien"))
            Button {
                revoke(inv)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Palette.destructive)
            .disabled(!store.isOnline)
            .accessibilityLabel(Text("Annuler l'invitation"))
        }
        .swipeActions {
            Button("Annuler l'invitation", systemImage: "trash", role: .destructive) { revoke(inv) }
                .disabled(!store.isOnline)
        }
    }

    // MARK: State helpers

    private var canInviteByEmail: Bool {
        store.isOnline && !isInviting && store.household != nil
            && inviteEmail.contains("@") && inviteEmail.trimmingCharacters(in: .whitespaces).count >= 3
    }

    private var removeTitle: Text {
        Text("Retirer \(memberToRemove.map { store.memberName($0) } ?? "") ?")
    }

    private var leaveTitle: Text {
        Text("Quitter « \(store.household?.name ?? "") » ?")
    }

    private var removeBinding: Binding<Bool> {
        Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } })
    }

    private var acceptBinding: Binding<Bool> {
        Binding(get: { acceptCode != nil }, set: { if !$0 { acceptCode = nil } })
    }

    // MARK: Actions

    private func load() async {
        guard store.isOnline, store.authState == .signedIn else { return }
        async let sent = try? store.activeInvitations()
        async let received = try? store.myInvitations()
        if let sent = await sent { invitations = sent }
        if let received = await received { incoming = received }
    }

    private func invite(email: String?) {
        guard store.isOnline, !isInviting else { return }
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        if email != nil, trimmed?.isEmpty ?? true { return }
        isInviting = true
        Task {
            defer { isInviting = false }
            do {
                let code = try await store.createInvitation(email: trimmed)
                let link = InvitationLink.url(code: code)
                UIPasteboard.general.url = link
                lastLink = link
                if let trimmed {
                    banner = ProfileBanner(text: String(localized: "Invitation créée pour \(trimmed). Lien copié : envoyez-le-lui."))
                    inviteEmail = ""
                } else {
                    banner = ProfileBanner(text: String(localized: "Lien d'invitation copié"))
                }
                await load()
            } catch {
                banner = .error(String(localized: "Invitation impossible"))
            }
        }
    }

    private func revoke(_ inv: HouseholdInvitation) {
        let previous = invitations
        invitations.removeAll { $0.id == inv.id }
        Task {
            do {
                try await store.revokeInvitation(inv.id)
            } catch {
                invitations = previous
                banner = .error(error.localizedDescription)
            }
        }
    }

    private func remove(_ member: HouseholdMember) {
        Task {
            do {
                try await store.removeMember(member.userId)
            } catch {
                banner = .error(error.localizedDescription)
            }
        }
    }

    private func leave() {
        Task {
            do {
                try await store.leaveHousehold()
                await load()
            } catch {
                banner = .error(error.localizedDescription)
            }
        }
    }

    private func accept(_ inv: IncomingInvitation) {
        Task {
            do {
                try await store.acceptInvitation(code: inv.code)
                banner = ProfileBanner(text: String(localized: "Bienvenue dans « \(inv.householdName ?? "") » !"))
                await load()
            } catch {
                banner = .error(error.localizedDescription)
            }
        }
    }
}
