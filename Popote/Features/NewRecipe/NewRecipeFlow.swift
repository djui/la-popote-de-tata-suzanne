import PhotosUI
import SwiftUI
import UIKit

/// `/recettes/nouvelle`: the full-screen new-recipe wizard (SPEC Part N).
struct NewRecipeFlow: View {
    let startWithPhoto: Bool
    @Environment(AppStore.self) private var store

    @State private var model: NewRecipeModel?

    var body: some View {
        Group {
            if let model {
                NewRecipeFlowContent(model: model)
            } else {
                Color.clear.popoteBackground()
            }
        }
        .onAppear {
            if model == nil { model = NewRecipeModel(store: store, startWithPhoto: startWithPhoto) }
        }
    }
}

private struct NewRecipeFlowContent: View {
    @State var model: NewRecipeModel
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var similar: [RecipeRepository.SimilarRecipe] = []
    @State private var showSimilar = false
    @State private var finished = false

    var body: some View {
        NavigationStack(path: $model.path) {
            CategoryStepView(model: model)
                .navigationDestination(for: NewRecipeModel.Step.self) { step in
                    Group {
                        switch step {
                        case .source: SourceStepView(model: model)
                        case .photos: PhotosStepView(model: model)
                        case .text: TextStepView(model: model)
                        case .url: URLStepView(model: model, onOpen: open)
                        case .review: reviewStep
                        }
                    }
                    .toolbar { cancelItem }
                }
                .toolbar { cancelItem }
        }
        .tint(Palette.primary)
        .sheet(isPresented: $model.showPicker) { pickerSheet }
        .sheet(isPresented: $showSimilar) { similarSheet }
        .onDisappear { if !finished { model.cancel() } }
    }

    private var cancelItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Annuler", role: .cancel) {
                model.cancel()
                finished = true
                dismiss()
            }
            .disabled(model.busy)
        }
    }

    private var reviewStep: some View {
        @Bindable var model = model
        return RecipeForm(draft: $model.draft,
                          highlightEmpty: model.aiHighlight || !model.draft.title.isEmpty,
                          submitLabel: "Enregistrer la recette",
                          pages: model.pages,
                          detections: model.detections,
                          uploads: model.uploads,
                          onSubmit: { try await submit(force: false) })
            .safeAreaInset(edge: .top) {
                if let banner = model.banner {
                    BannerView(message: banner) { model.banner = nil }
                }
            }
            .navigationTitle(model.reviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SyncStatusButton() }
            }
    }

    // MARK: - Save

    private func submit(force: Bool) async throws {
        if !force {
            let matches = (try? await model.similarTitles()) ?? []
            if !matches.isEmpty {
                similar = matches
                showSimilar = true
                return
            }
        }
        let id = try await model.save()
        finished = true
        dismiss()
        try? await Task.sleep(for: .milliseconds(350))
        router.open(recipe: id)
    }

    private func open(_ id: UUID) {
        model.cancel()
        finished = true
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            router.open(recipe: id)
        }
    }

    // MARK: - Sheets

    private var pickerSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(model.candidates.enumerated()), id: \.offset) { i, recipe in
                        Button {
                            model.pick(recipe)
                        } label: {
                            HStack {
                                Text(recipe.title?.isEmpty == false ? recipe.title! : String(localized: "Recette \(i + 1)"))
                                    .font(AppFont.body(16, weight: .bold))
                                    .foregroundStyle(Palette.foreground)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
                            }
                        }
                    }
                } header: {
                    Text("Laquelle veux-tu importer ?")
                }
            }
            .navigationTitle("Plusieurs recettes trouvées")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .popoteBackground()
        }
        .presentationDetents([.medium, .large])
    }

    private var similarSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("La base commune contient une recette au titre très proche :")
                    .font(AppFont.body(15))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(similar) { r in
                        Label(r.title, systemImage: "book.closed")
                            .font(AppFont.body(16, weight: .bold))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .popoteCard()
                Spacer(minLength: 0)
                Button("Enregistrer quand même") {
                    showSimilar = false
                    Task {
                        do { try await submit(force: true) } catch {
                            model.banner = String(localized: "Enregistrement impossible")
                        }
                    }
                }
                .buttonStyle(.popotePrimary)
                Button("Revenir à ma recette") { showSimilar = false }
                    .buttonStyle(.popoteSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .popoteBackground()
            .navigationTitle("Cette recette existe peut-être déjà")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Steps

private struct StepScaffold<Content: View>: View {
    let title: LocalizedStringKey
    var intro: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let intro {
                    Text(intro).font(AppFont.body(16)).foregroundStyle(Palette.muted)
                }
                content
            }
            .padding()
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .popoteBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { SyncStatusButton() } }
    }
}

struct BannerView: View {
    let message: String
    let onClose: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.destructive)
            Text(message).font(AppFont.body(14, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
            Button { onClose() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Fermer"))
        }
        .padding(12)
        .popoteCard(radius: 14)
        .padding(.horizontal)
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

private struct CategoryStepView: View {
    let model: NewRecipeModel

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 12)], spacing: 20) {
                ForEach(RecipeCategory.allCases) { c in
                    CategoryTileButton(category: c, isOn: model.category == c) { model.choose(c) }
                }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .popoteBackground()
        .navigationTitle("Quel type de recette ?")
        .navigationBarTitleDisplayMode(.large)
        .sensoryFeedback(.selection, trigger: model.category)
    }
}

private struct SourceStepView: View {
    let model: NewRecipeModel
    @Environment(AppStore.self) private var store

    var body: some View {
        StepScaffold(title: "D'où vient ta recette ?") {
            Button {
                if model.path.first == .source { model.path.removeAll() }
            } label: {
                Label {
                    Text("\(model.category.label) · changer")
                } icon: {
                    Image(systemName: model.category.symbol)
                }
                .font(AppFont.body(15, weight: .bold))
                .foregroundStyle(Palette.primary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Palette.chip, in: Capsule())
            }
            .buttonStyle(.plain)

            if !store.isOnline { NewRecipeOfflineNotice() }

            VStack(spacing: 12) {
                SourceTile(title: "Photo", hint: "Livre, carnet, magazine", systemImage: "camera", disabled: !store.isOnline) {
                    model.path.append(.photos)
                }
                SourceTile(title: "Coller un texte", hint: "WhatsApp, e-mail, SMS…", systemImage: "doc.on.clipboard", disabled: !store.isOnline) {
                    model.path.append(.text)
                }
                SourceTile(title: "Lien web", hint: "Site de recettes, blog", systemImage: "link", disabled: !store.isOnline) {
                    model.path.append(.url)
                }
            }

            Button { model.manualEntry() } label: {
                Label("Saisir à la main", systemImage: "keyboard")
            }
            .buttonStyle(.popoteSecondary)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PhotosStepView: View {
    let model: NewRecipeModel
    @Environment(AppStore.self) private var store
    @State private var items: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var loading = false

    private var room: Int { NewRecipeModel.maxPages - model.pages.count }

    var body: some View {
        StepScaffold(title: "Photographie la recette",
                     intro: "Une ou plusieurs pages (jusqu'à 6). Les ingrédients et étapes seront lus automatiquement.") {
            categoryChip
            if !store.isOnline { NewRecipeOfflineNotice() }

            HStack(spacing: 12) {
                Button { showCamera = true } label: {
                    PhotoSourceTileLabel(title: "Appareil photo", systemImage: "camera")
                }
                .buttonStyle(.plain)
                .disabled(!CameraPicker.isAvailable || room <= 0 || model.busy)
                .opacity(CameraPicker.isAvailable && room > 0 ? 1 : 0.5)

                PhotosPicker(selection: $items, maxSelectionCount: max(room, 1), matching: .images) {
                    PhotoSourceTileLabel(title: "Galerie", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.plain)
                .disabled(room <= 0 || model.busy)
                .opacity(room > 0 ? 1 : 0.5)
            }

            if loading { ProgressView().frame(maxWidth: .infinity) }

            if !model.pages.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(Array(model.pages.enumerated()), id: \.offset) { i, page in
                        Color.clear
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .overlay { Image(uiImage: page).resizable().scaledToFill() }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .topLeading) {
                                Text("\(i + 1)")
                                    .font(AppFont.body(12, weight: .heavy))
                                    .foregroundStyle(Palette.onPrimary)
                                    .frame(width: 22, height: 22)
                                    .background(Palette.primary, in: Circle())
                                    .padding(6)
                            }
                            .overlay(alignment: .topTrailing) {
                                Button { model.removePage(at: i) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .font(.system(size: 22))
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                                .accessibilityLabel(Text("Retirer"))
                                .disabled(model.busy)
                            }
                    }
                }
            }

            if model.busy {
                AIProgressView(title: LocalizedStringKey(model.busyTitle), progress: model.progress)
            }

            if let banner = model.banner {
                InlineErrorBox(message: banner)
            }

            Button {
                Task { await model.analyzePhotos() }
            } label: {
                Label(model.pages.count > 1 ? "Analyser les \(model.pages.count) photos" : "Analyser la photo", systemImage: "sparkles")
            }
            .buttonStyle(.popotePrimary)
            .disabled(model.pages.isEmpty || model.busy || !store.isOnline)
            .opacity(model.pages.isEmpty || model.busy || !store.isOnline ? 0.6 : 1)

            Button { model.manualEntry() } label: { Label("Saisir à la main", systemImage: "keyboard") }
                .buttonStyle(.popoteSecondary)
                .frame(maxWidth: .infinity)
                .disabled(model.busy)
        }
        .onChange(of: items) { _, picked in
            guard !picked.isEmpty else { return }
            items = []
            loading = true
            Task {
                var images: [UIImage] = []
                for item in picked { if let img = await item.loadImage() { images.append(img) } }
                model.addPages(images)
                loading = false
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                Task {
                    let upright = await Task.detached { ImagePipeline.resized(image, maxPixel: 2400) }.value
                    model.addPages([upright])
                }
            }
            .ignoresSafeArea()
        }
        .navigationBarBackButtonHidden(model.busy)
    }

    private var categoryChip: some View {
        Menu {
            Picker("Catégorie", selection: Binding(get: { model.category }, set: { model.category = $0 })) {
                ForEach(RecipeCategory.allCases) { c in Label(c.label, systemImage: c.symbol).tag(c) }
            }
        } label: {
            Label { Text("\(model.category.label) · changer") } icon: { Image(systemName: model.category.symbol) }
                .font(AppFont.body(15, weight: .bold))
                .foregroundStyle(Palette.primary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Palette.chip, in: Capsule())
        }
    }
}

private struct PhotoSourceTileLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 30, weight: .light))
            Text(title).font(AppFont.body(15, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(Palette.tileGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct TextStepView: View {
    @Bindable var model: NewRecipeModel
    @Environment(AppStore.self) private var store
    @FocusState private var focused: Bool

    var body: some View {
        StepScaffold(title: "Coller un texte",
                     intro: "Une recette reçue par message ou par e-mail ? Copie-la puis colle-la ici, Tata Suzanne fait le tri.") {
            if !store.isOnline { NewRecipeOfflineNotice() }

            Button {
                Task { await model.pasteText() }
            } label: {
                Label("Coller depuis le presse-papiers", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.popoteSecondary)
            .disabled(model.busy || !store.isOnline)

            if model.textRevealed || !model.text.isEmpty {
                VStack(alignment: .trailing, spacing: 6) {
                    TextEditor(text: $model.text)
                        .focused($focused)
                        .frame(minHeight: 220)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .popoteCard(radius: 16)
                        .overlay(alignment: .topLeading) {
                            if model.text.isEmpty {
                                Text("Colle ta recette ici")
                                    .foregroundStyle(Palette.muted)
                                    .padding(.horizontal, 15).padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel(Text("Texte de la recette"))
                        .onChange(of: model.text) { _, t in
                            if t.count > NewRecipeModel.maxText { model.text = String(t.prefix(NewRecipeModel.maxText)) }
                        }
                    Text("\(model.text.count.formatted(.number.locale(Locale(identifier: "fr_FR")))) / 15 000")
                        .font(AppFont.body(12))
                        .foregroundStyle(Palette.muted)
                        .monospacedDigit()
                }
            } else {
                Button("Coller à la main") {
                    model.textRevealed = true
                    focused = true
                }
                .font(AppFont.body(15, weight: .bold))
            }

            if model.busy { AIProgressView(title: LocalizedStringKey(model.busyTitle)) }
            if let banner = model.banner { InlineErrorBox(message: banner) }

            Button {
                focused = false
                Task { await model.parseText() }
            } label: {
                Label(model.busy ? "Lecture de la recette…" : "Lire la recette", systemImage: "sparkles")
            }
            .buttonStyle(.popotePrimary)
            .disabled(model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy || !store.isOnline)
            .opacity(model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy || !store.isOnline ? 0.6 : 1)
        }
        .onAppear { if model.textRevealed { focused = true } }
        .navigationBarBackButtonHidden(model.busy)
    }
}

private struct URLStepView: View {
    @Bindable var model: NewRecipeModel
    let onOpen: (UUID) -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        StepScaffold(title: "Lien web", intro: "Colle le lien de la recette (site de cuisine, blog…).") {
            if !store.isOnline { NewRecipeOfflineNotice() }

            HStack(spacing: 10) {
                TextField("https://…", text: $model.url)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { Task { await model.importURL() } }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .popoteCard(radius: 14)
                    .accessibilityLabel(Text("Lien de la recette"))
                Button("Coller") { model.pasteURL() }
                    .buttonStyle(.popoteSecondary)
            }

            if model.busy { AIProgressView(title: LocalizedStringKey(model.busyTitle)) }

            if let error = model.urlError {
                InlineErrorBox(message: error) {
                    Button { model.switchToText() } label: { Label("Coller un texte", systemImage: "doc.on.clipboard") }
                        .buttonStyle(.popoteSecondary)
                }
            }

            Button {
                Task { await model.importURL() }
            } label: {
                Label(model.busy ? "Lecture de la page…" : "Importer la recette", systemImage: "sparkles")
            }
            .buttonStyle(.popotePrimary)
            .disabled(model.url.trimmingCharacters(in: .whitespaces).isEmpty || model.busy || !store.isOnline)
            .opacity(model.url.trimmingCharacters(in: .whitespaces).isEmpty || model.busy || !store.isOnline ? 0.6 : 1)
        }
        .navigationBarBackButtonHidden(model.busy)
        .alert("Déjà dans la Popote !", isPresented: Binding(get: { model.duplicate != nil }, set: { if !$0 { model.duplicate = nil } }),
               presenting: model.duplicate) { dup in
            Button("Importer quand même") {
                model.duplicate = nil
                Task { await model.importURL(force: true) }
            }
            Button("Ouvrir la recette") { onOpen(dup.id) }
            Button("Annuler", role: .cancel) {}
        } message: { dup in
            Text("Cette recette a déjà été importée : « \(dup.title) ».")
        }
    }
}
