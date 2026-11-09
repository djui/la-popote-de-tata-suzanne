import SwiftUI
import UniformTypeIdentifiers

/// Profil (SPEC §C.7, §B.6): account, household, store order, offline storage, data, help, legal.
struct ProfileTab: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL

    @State private var banner: ProfileBanner?
    @State private var language = AppLanguage.current
    @State private var firstName = ""
    @FocusState private var firstNameFocused: Bool
    @State private var servingsTask: Task<Void, Never>?
    @State private var servingsChanges = 0
    @State private var disk: (files: Int, bytes: Int64) = (0, 0)
    @State private var isExporting = false
    @State private var exportFile: ExportFile?
    @State private var showDeleteAccount = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                languageSection
                accountSection
                linksSection
                HouseholdSection(banner: $banner)
                servingsSection
                storeSection
                offlineSection
                if store.isAdmin { adminSection }
                dataSection
                faqSection
                contactSection
                legalSection
            }
            .scrollContentBackground(.hidden)
            .popoteBackground()
            .navigationTitle("Profil")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SyncStatusButton() }
            }
            .refreshable { await store.refresh() }
            .profileBanner($banner)
            .sheet(item: invitationBinding) { invitation in
                InvitationSheet(code: invitation.code)
            }
            .sheet(isPresented: $showDeleteAccount) {
                AccountDeletionSheet()
            }
            .fileExporter(isPresented: exportBinding, item: exportFile, contentTypes: [.json],
                          defaultFilename: "mes-recettes-popote.json") { result in
                if case .success = result {
                    banner = ProfileBanner(text: String(localized: "Tes recettes sont exportées"))
                }
                exportFile = nil
            }
            .task(id: store.photoProgress.done) { disk = await store.photos.diskUsage() }
            .onAppear { firstName = store.profile?.firstName ?? "" }
            .onChange(of: store.profile?.firstName) { _, new in
                if !firstNameFocused { firstName = new ?? "" }
            }
        }
    }

    // MARK: Language

    private var languageSection: some View {
        Section {
            Picker(selection: $language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(verbatim: lang.label).tag(lang)
                }
            } label: {
                Text(verbatim: language == .en ? "Language" : "Langue")
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .onChange(of: language) { _, new in
                Task {
                    if let message = await store.setLanguage(new) { banner = .error(message) }
                }
            }
        }
    }

    // MARK: Account

    private var accountSection: some View {
        Section {
            if let email = store.email {
                Text("Connecté en tant que \(Text(verbatim: email).bold())")
                    .font(AppFont.body(15))
                    .foregroundStyle(Palette.foreground)
            }
            TextField("Prénom", text: $firstName)
                .font(AppFont.body(17, weight: .semibold))
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($firstNameFocused)
                .onSubmit(saveFirstName)
                .onChange(of: firstNameFocused) { _, focused in if !focused { saveFirstName() } }
                .disabled(!store.isOnline)
                .accessibilityLabel(Text("Prénom"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Affiché sur les recettes que tu partages : « Ajoutée par \(displayedFirstName) ».")
                if !store.isOnline { OfflineHint() }
            }
            .font(AppFont.body(12, relativeTo: .caption))
        }
        .listRowBackground(Palette.card)
    }

    private var displayedFirstName: String {
        let trimmed = firstName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "…" : trimmed
    }

    private func saveFirstName() {
        let trimmed = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != store.profile?.firstName, store.isOnline else { return }
        Task {
            do {
                try await store.updateFirstName(trimmed)
                banner = ProfileBanner(text: String(localized: "Prénom enregistré"))
            } catch {
                banner = .error(String(localized: "Impossible d'enregistrer"))
            }
        }
    }

    // MARK: Links

    private var linksSection: some View {
        Section {
            NavigationLink {
                MyCookbookView()
            } label: {
                ProfileLinkLabel(title: "Mon livre de cuisine", subtitle: "Celles que tu as ajoutées, avec leurs notes.", systemImage: "book.pages")
            }
            NavigationLink {
                StoryView()
            } label: {
                ProfileLinkLabel(title: "L'histoire de Tata Suzanne", subtitle: "Mais qui se cache derrière la Popote ?", systemImage: "heart")
            }
        }
        .listRowBackground(Palette.card)
    }

    // MARK: Servings

    private var servingsSection: some View {
        Section {
            HStack(spacing: 16) {
                Button {
                    changeServings(-1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 40, height: 40)
                        .background(Palette.chip, in: Circle())
                }
                .buttonStyle(.borderless)
                .disabled(store.defaultServings <= 1 || !canEditServings)
                .accessibilityLabel(Text("Moins"))

                Text(verbatim: "\(store.defaultServings)")
                    .font(AppFont.display(28, relativeTo: .title))
                    .monospacedDigit()
                    .frame(minWidth: 44)
                    .contentTransition(.numericText())
                    .accessibilityLabel(Text("\(store.defaultServings) personnes"))

                Button {
                    changeServings(1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 40, height: 40)
                        .background(Palette.chip, in: Circle())
                }
                .buttonStyle(.borderless)
                .disabled(store.defaultServings >= 50 || !canEditServings)
                .accessibilityLabel(Text("Plus"))

                Spacer()
            }
            .foregroundStyle(Palette.foreground)
            .sensoryFeedback(.increase, trigger: servingsChanges)
        } header: {
            ProfileSectionHeader(title: "Personnes par défaut", systemImage: "person.3")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Réglage du foyer, utilisé quand on ajoute une recette au menu.")
                if !store.isOnline { OfflineHint() }
            }
            .font(AppFont.body(12, relativeTo: .caption))
        }
        .listRowBackground(Palette.card)
    }

    private var canEditServings: Bool { store.isOnline && store.household != nil }

    private func changeServings(_ delta: Int) {
        let previous = store.defaultServings
        let next = min(50, max(1, previous + delta))
        guard next != previous else { return }
        withAnimation(.snappy) { store.setDefaultServingsLocally(next) }
        servingsChanges += 1
        servingsTask?.cancel()
        servingsTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do {
                try await store.saveDefaultServings(next)
            } catch {
                if !AppStore.isCancellation(error) {
                    store.setDefaultServingsLocally(previous)
                    banner = .error(String(localized: "Impossible d'enregistrer"))
                }
            }
        }
    }

    // MARK: Mon magasin

    private var storeSection: some View {
        Section {
            NavigationLink {
                AisleOrderView()
            } label: {
                ProfileLinkLabel(title: "Mon magasin", subtitle: "Glisse les rayons dans l'ordre de ton supermarché, le panier suivra.", systemImage: "storefront")
            }
        }
        .listRowBackground(Palette.card)
    }

    // MARK: Offline storage

    private var offlineSection: some View {
        Section {
            LabeledContent("Recettes disponibles hors ligne") {
                Text(verbatim: "\(store.recipes.count)")
            }
            LabeledContent("Photos") {
                Text("\(disk.files) · \(ByteCountFormatter.string(fromByteCount: disk.bytes, countStyle: .file))")
            }
            if store.photoProgress.total > 0 && store.photoProgress.done < store.photoProgress.total {
                ProgressView(value: Double(store.photoProgress.done), total: Double(store.photoProgress.total)) {
                    Text("Téléchargement des photos…")
                }
            }
            LabeledContent("Dernière synchronisation") {
                if let last = store.lastSync {
                    Text(last, format: .relative(presentation: .named))
                } else {
                    Text("Jamais")
                }
            }
            if !store.pendingOps.isEmpty {
                LabeledContent("Modifications en attente") {
                    Text(verbatim: "\(store.pendingOps.count)")
                }
            }
            Button {
                Task { await store.refresh() }
            } label: {
                HStack {
                    Label("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath")
                    if store.isSyncing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!store.isOnline || store.isSyncing)
            if let error = store.lastError {
                Text(error)
                    .font(AppFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.destructive)
            }
        } header: {
            ProfileSectionHeader(title: "Hors ligne", systemImage: "arrow.down.circle")
        } footer: {
            Text(store.isOnline
                 ? "Tes recettes, le menu et la liste de courses restent disponibles sans réseau."
                 : "Tu es hors ligne. Tes modifications seront envoyées dès le retour du réseau.")
                .font(AppFont.body(12, relativeTo: .caption))
        }
        .font(AppFont.body(15))
        .listRowBackground(Palette.card)
    }

    // MARK: Admin

    private var adminSection: some View {
        Section {
            Button {
                openURL(Backend.webURL.appending(path: "admin/ingredients"))
            } label: {
                ProfileLinkLabel(title: "Ingrédients à vérifier", subtitle: "Valider ce que l'IA a rangé, fusionner les doublons.", systemImage: "checkmark.shield")
            }
            Button {
                openURL(Backend.webURL.appending(path: "admin/signalements"))
            } label: {
                ProfileLinkLabel(title: "Signalements de contenus", subtitle: "S'ouvre sur le site web.", systemImage: "flag")
            }
        } header: {
            ProfileSectionHeader(title: "Administration", systemImage: "lock.shield")
        }
        .listRowBackground(Palette.card)
    }

    // MARK: Mes données

    private var dataSection: some View {
        Section {
            Button {
                export()
            } label: {
                HStack {
                    Label("Exporter mes recettes (JSON)", systemImage: "square.and.arrow.down")
                    if isExporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)

            Button(role: .destructive) {
                showDeleteAccount = true
            } label: {
                Label("Supprimer mon compte", systemImage: "person.crop.circle.badge.xmark")
            }
            .disabled(!store.isOnline)
        } header: {
            ProfileSectionHeader(title: "Mes données", systemImage: "externaldrive")
        }
        .listRowBackground(Palette.card)
    }

    private var exportBinding: Binding<Bool> {
        Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } })
    }

    private func export() {
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let url = try await store.exportMyRecipes()
                exportFile = ExportFile(url: url)
            } catch {
                banner = .error(String(localized: "Export impossible"))
            }
        }
    }

    // MARK: FAQ & contact

    private var faqSection: some View {
        Section {
            ForEach(Array(LegalTexts.faq.enumerated()), id: \.offset) { _, item in
                DisclosureGroup {
                    Text(item.answer.current)
                        .font(AppFont.body(15))
                        .foregroundStyle(Palette.muted)
                        .padding(.vertical, 4)
                } label: {
                    Text(item.question.current)
                        .font(AppFont.body(15, weight: .bold))
                        .foregroundStyle(Palette.foreground)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle").imageScale(.small)
                Text(LegalTexts.faqTitle.current)
            }
            .font(AppFont.display(19, bold: false, relativeTo: .title3))
            .foregroundStyle(Palette.foreground)
            .textCase(nil)
        }
        .listRowBackground(Palette.card)
    }

    private var contactSection: some View {
        Section {
            Text(LegalTexts.contactText.current)
                .font(AppFont.body(15))
            Button {
                openURL(LegalTexts.contactMailto)
            } label: {
                Label(LegalTexts.sendEmail.current, systemImage: "envelope")
            }
            Text(verbatim: LegalTexts.contactAddress)
                .font(AppFont.body(14, relativeTo: .footnote))
                .foregroundStyle(Palette.muted)
                .textSelection(.enabled)
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "envelope").imageScale(.small)
                Text(LegalTexts.contactTitle.current)
            }
            .font(AppFont.display(19, bold: false, relativeTo: .title3))
            .foregroundStyle(Palette.foreground)
            .textCase(nil)
        }
        .listRowBackground(Palette.card)
    }

    // MARK: Legal & sign out

    private var legalSection: some View {
        Section {
            NavigationLink("Conditions générales d'utilisation") { TermsView() }
            Button(role: .destructive) {
                confirmSignOut = true
            } label: {
                Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .confirmationDialog("Se déconnecter ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Se déconnecter", role: .destructive) { Task { await store.signOut() } }
                Button("Annuler", role: .cancel) {}
            } message: {
                if !store.pendingOps.isEmpty {
                    Text("\(store.pendingOps.count) modification(s) pas encore synchronisée(s) seront perdues.")
                }
            }
        }
        .listRowBackground(Palette.card)
    }

    // MARK: Invitation deep link

    private var invitationBinding: Binding<InvitationCode?> {
        Binding(
            get: { router.pendingInvitation.flatMap(InvitationLink.code(from:)).map(InvitationCode.init) },
            set: { if $0 == nil { router.pendingInvitation = nil } }
        )
    }
}

/// The exported JSON file, handed to `fileExporter`.
struct ExportFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { SentTransferredFile($0.url) }
    }
}
