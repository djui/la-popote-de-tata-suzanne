import PhotosUI
import SwiftUI
import UIKit

/// The recipe form shared by the new-recipe wizard and the edit screen (SPEC §A.16).
struct RecipeForm: View {
    @Binding var draft: RecipeDraft
    var highlightEmpty = false
    let submitLabel: LocalizedStringKey
    /// Photographed recipe pages (photo import only), upright at scale 1.
    var pages: [UIImage] = []
    var detections: [AiDetection] = []
    let uploads: UploadSession
    let onSubmit: () async throws -> Void

    @Environment(AppStore.self) private var store

    @State private var tagsText = ""
    @State private var localPreview: UIImage?
    @State private var uploading = false
    @State private var uploadProgress: Double = 0
    @State private var photoError: String?
    @State private var notice: String?
    @State private var submitError: String?
    @State private var isSaving = false
    @State private var showLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showOtherPhotos = false
    @State private var cropRequest: CropRequest?
    @State private var selectedDetection: Int?
    @State private var detectionThumbs: [Int: UIImage] = [:]
    @State private var didInit = false
    @State private var savedTick = 0

    struct CropRequest: Identifiable {
        let id = UUID()
        let image: UIImage
        let box: [Double]?
    }

    var body: some View {
        Form {
            if highlightEmpty && draft.hasKeyGaps {
                Section {
                    Label {
                        Text("Vérifie les champs surlignés : ils sont vides ou n'ont pas pu être lus sur la photo.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                    }
                    .font(AppFont.body(14, weight: .semibold))
                    .listRowBackground(Palette.warning.opacity(0.18))
                }
            }

            photoSection
            titleSection
            categoriesSection
            numbersSection
            seasonsSection
            ingredientsSection
            stepsSection
            tagsNotesSection
            sourceSection
            privacyRightsSection
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .popoteBackground()
        .safeAreaInset(edge: .bottom) { submitBar }
        .font(AppFont.body(16))
        .onAppear(perform: initialize)
        .onChange(of: tagsText) { _, new in draft.tags = RecipeDraft.parseTags(new) }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            Task {
                guard let image = await item.loadImage() else { photoError = String(localized: "Oups, cette photo n'a pas pu être lue"); return }
                cropRequest = CropRequest(image: image, box: nil)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                Task {
                    let upright = await Task.detached { ImagePipeline.resized(image, maxPixel: 2400) }.value
                    cropRequest = CropRequest(image: upright, box: nil)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $cropRequest) { req in
            PhotoCropView(image: req.image, initialBox: req.box) { result in
                Task { await setDishPhoto(result) }
            }
        }
        .task(id: detections.count) { await buildDetectionThumbs() }
        .sensoryFeedback(.success, trigger: savedTick)
    }

    // MARK: - Sections

    @ViewBuilder private var photoSection: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                photoPreview
                    .frame(width: pages.isEmpty ? 112 : 144, height: pages.isEmpty ? 112 : 144)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        if uploading { ProgressView().tint(.white) }
                    }
                VStack(alignment: .leading, spacing: 8) {
                    if !pages.isEmpty {
                        if detections.isEmpty {
                            Text("Aucune photo de plat n'a été repérée sur tes pages.")
                                .font(AppFont.body(13)).foregroundStyle(Palette.muted)
                        } else if let d = currentDetection, d.confidence < 0.6 {
                            Text("Est-ce bien la photo du plat ?")
                                .font(AppFont.body(13, weight: .bold)).foregroundStyle(Palette.warning)
                        }
                        if let d = currentDetection, pages.indices.contains(d.imageIndex) {
                            Button { cropRequest = CropRequest(image: pages[d.imageIndex], box: d.box) } label: {
                                Label("Ajuster le cadrage", systemImage: "crop")
                            }
                        }
                        Button { withAnimation { showOtherPhotos.toggle() } } label: {
                            Label("Choisir une autre photo", systemImage: "photo.on.rectangle")
                        }
                    }
                    Menu {
                        if CameraPicker.isAvailable {
                            Button { showCamera = true } label: { Label("Appareil photo", systemImage: "camera") }
                        }
                        Button { showLibrary = true } label: { Label("Galerie", systemImage: "photo") }
                    } label: {
                        Label(pages.isEmpty ? "Photo du plat" : "Ajouter ma propre photo", systemImage: "camera")
                    }
                    if draft.photoUrl != nil {
                        Button(role: .destructive) { removePhoto() } label: {
                            Label("Retirer la photo", systemImage: "trash")
                        }
                    }
                }
                .font(AppFont.body(15, weight: .semibold))
                .buttonStyle(.borderless)
                .disabled(uploading || !store.isOnline)
            }
            if uploading {
                ProgressView(value: uploadProgress).tint(Palette.primary)
            }
            if let photoError {
                Text(photoError).font(AppFont.body(13)).foregroundStyle(Palette.destructive)
            }
            if showOtherPhotos && !pages.isEmpty {
                otherPhotosPicker
            }
        } header: {
            Text("Photo du plat")
        } footer: {
            if !store.isOnline { Text("La photo pourra être ajoutée dès le retour du réseau.") }
        }
    }

    @ViewBuilder private var photoPreview: some View {
        if let localPreview {
            Image(uiImage: localPreview).resizable().scaledToFill()
        } else {
            RecipePhotoView(path: draft.photoThumbUrl ?? draft.photoUrl, category: draft.categories.first ?? .plat)
        }
    }

    private var currentDetection: AiDetection? {
        if let selectedDetection, detections.indices.contains(selectedDetection) { return detections[selectedDetection] }
        return AiDetection.main(detections)
    }

    @ViewBuilder private var otherPhotosPicker: some View {
        if !detections.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Photos repérées sur tes pages").font(AppFont.body(13, weight: .bold)).foregroundStyle(Palette.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(detections.indices, id: \.self) { i in
                            Button { chooseDetection(i) } label: {
                                ZStack {
                                    if let thumb = detectionThumbs[i] {
                                        Image(uiImage: thumb).resizable().scaledToFill()
                                    } else {
                                        Rectangle().fill(Palette.chip)
                                        Text("Page \(detections[i].imageIndex + 1)").font(AppFont.body(12, weight: .bold))
                                    }
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    if currentDetection == detections[i] {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.primary, lineWidth: 3)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Ou trace une zone à la main sur une page").font(AppFont.body(13, weight: .bold)).foregroundStyle(Palette.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(pages.indices, id: \.self) { i in
                        Button { cropRequest = CropRequest(image: pages[i], box: nil) } label: {
                            Image(uiImage: pages[i]).resizable().scaledToFill()
                                .frame(width: 60, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Page \(i + 1)"))
                    }
                }
            }
        }
    }

    private var titleSection: some View {
        Section("Titre") {
            TextField("Ex. Gratin dauphinois", text: $draft.title)
                .font(AppFont.display(20, bold: false, relativeTo: .title3))
                .textInputAutocapitalization(.sentences)
                .accessibilityLabel(Text("Titre"))
                .listRowBackground(rowBackground(highlightEmpty && draft.titleMissing))
        }
    }

    private var categoriesSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 96), spacing: 10)], spacing: 12) {
                ForEach(RecipeCategory.allCases) { c in
                    CategoryTileButton(category: c, isOn: draft.categories.contains(c), compact: true) { toggle(c) }
                }
            }
            .padding(.vertical, 6)
            if let notice {
                Text(notice).font(AppFont.body(13, weight: .semibold)).foregroundStyle(Palette.destructive)
            }
        } header: {
            Text("Catégories (une ou plusieurs)")
        }
    }

    private var numbersSection: some View {
        Section {
            numberRow("Personnes", value: $draft.servings)
            numberRow("Préparation (min)", value: $draft.prepTimeMin)
            numberRow("Cuisson (min)", value: $draft.cookTimeMin)
        }
    }

    private func numberRow(_ label: LocalizedStringKey, value: Binding<Int?>) -> some View {
        LabeledContent(label) {
            TextField(label, text: Binding(
                get: { value.wrappedValue.map(String.init) ?? "" },
                set: { value.wrappedValue = RecipeDraft.parseNumber($0).map { Int($0.rounded()) } }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 90)
        }
        .listRowBackground(rowBackground(highlightEmpty && value.wrappedValue == nil))
    }

    private var seasonsSection: some View {
        Section("Saisons") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Season.allCases) { s in
                        Button {
                            if let i = draft.seasons.firstIndex(of: s) { draft.seasons.remove(at: i) } else {
                                draft.seasons = Season.allCases.filter { draft.seasons.contains($0) || $0 == s }
                            }
                        } label: { ChipView(title: s.label, isOn: draft.seasons.contains(s)) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(draft.seasons.contains(s) ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var ingredientsSection: some View {
        Section {
            if draft.ingredients.isEmpty {
                Text("Aucun ingrédient.")
                    .foregroundStyle(Palette.muted)
                    .listRowBackground(rowBackground(highlightEmpty))
            }
            ForEach($draft.ingredients) { $ing in
                IngredientEditorRow(ingredient: $ing, highlight: highlightEmpty)
                    .listRowBackground(rowBackground(highlightEmpty && (ing.nameMissing || ing.quantityMissing)))
                    .contextMenu { moveMenu(id: ing.id, in: \.ingredients) }
                    .swipeActions {
                        Button(role: .destructive) { draft.ingredients.removeAll { $0.id == ing.id } } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
            }
            .onMove { draft.ingredients.move(fromOffsets: $0, toOffset: $1) }
            HStack {
                Button { draft.ingredients.append(DraftIngredient()) } label: { Label("Ajouter", systemImage: "plus") }
                Spacer()
                Button { pasteIngredients() } label: { Label("Coller une liste", systemImage: "doc.on.clipboard") }
            }
            .buttonStyle(.borderless)
            .font(AppFont.body(15, weight: .bold))
        } header: {
            Text("Ingrédients")
        }
    }

    private var stepsSection: some View {
        Section {
            if draft.steps.isEmpty {
                Text("Aucune étape.")
                    .foregroundStyle(Palette.muted)
                    .listRowBackground(rowBackground(highlightEmpty))
            }
            ForEach(Array($draft.steps.enumerated()), id: \.element.id) { index, $step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(AppFont.body(14, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Palette.tileGradient, in: Circle())
                    TextField("Étape \(index + 1)", text: $step.instruction, axis: .vertical)
                        .lineLimit(2...10)
                }
                .listRowBackground(rowBackground(highlightEmpty && step.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                .contextMenu { moveMenu(id: step.id, in: \.steps) }
                .swipeActions {
                    Button(role: .destructive) { draft.steps.removeAll { $0.id == step.id } } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            }
            .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }
            Button { draft.steps.append(DraftStep()) } label: { Label("Ajouter", systemImage: "plus") }
                .buttonStyle(.borderless)
                .font(AppFont.body(15, weight: .bold))
        } header: {
            Text("Étapes")
        } footer: {
            if draft.steps.count > 1 || draft.ingredients.count > 1 {
                Text("Touche longuement une ligne pour la monter, la descendre ou la supprimer.")
            }
        }
    }

    private var tagsNotesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tags (séparés par des virgules)").font(AppFont.body(13, weight: .bold)).foregroundStyle(Palette.muted)
                TextField("Tags (séparés par des virgules)", text: $tagsText)
                    .textInputAutocapitalization(.never)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(AppFont.body(13, weight: .bold)).foregroundStyle(Palette.muted)
                TextField("Notes", text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
                    .lineLimit(3...8)
            }
        }
    }

    private var sourceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Source / inspiration (facultatif)").font(AppFont.body(13, weight: .bold)).foregroundStyle(Palette.muted)
                TextField("Inspiré de Saveurs, déc. 2025", text: Binding(
                    get: { draft.sourceInspiration ?? "" },
                    set: { draft.sourceInspiration = $0.isEmpty ? nil : String($0.prefix(1000)) }
                ), axis: .vertical)
                .lineLimit(1...4)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Lien de la recette").font(AppFont.body(13, weight: .bold)).foregroundStyle(Palette.muted)
                TextField("https://…", text: Binding(
                    get: { draft.sourceUrl ?? "" },
                    set: { draft.sourceUrl = $0 }
                ))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
        }
    }

    private var privacyRightsSection: some View {
        Section {
            Toggle(isOn: $draft.isPrivate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("🔒 Recette privée").font(AppFont.body(16, weight: .bold))
                    Text("Visible seulement par toi et les membres de ton foyer.")
                        .font(AppFont.body(13)).foregroundStyle(Palette.muted)
                }
            }
            Button { draft.rightsCertified.toggle() } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: draft.rightsCertified ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundStyle(draft.rightsCertified ? Palette.primary : Palette.muted)
                    Text("Je certifie avoir le droit de partager ce contenu : la photo du plat est la mienne et le texte est rédigé avec mes propres mots ou appartient au domaine familial. J'indique la source si la recette est inspirée d'un livre, d'un magazine ou d'un site.")
                        .font(AppFont.body(14))
                        .foregroundStyle(Palette.foreground)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(draft.rightsCertified ? [.isSelected] : [])
            .sensoryFeedback(.selection, trigger: draft.rightsCertified)
        }
    }

    private var submitBar: some View {
        VStack(spacing: 8) {
            if let submitError {
                Text(submitError)
                    .font(AppFont.body(13, weight: .semibold))
                    .foregroundStyle(Palette.destructive)
                    .multilineTextAlignment(.center)
            }
            if !store.isOnline {
                Text("Hors ligne : l'enregistrement sera possible dès le retour du réseau.")
                    .font(AppFont.body(13))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            Button { submit() } label: {
                HStack(spacing: 8) {
                    if isSaving { ProgressView().tint(Palette.onPrimary) }
                    Text(submitLabel)
                }
            }
            .buttonStyle(.popotePrimary)
            .disabled(isSaving || uploading || !draft.rightsCertified || !store.isOnline)
            .opacity(isSaving || uploading || !draft.rightsCertified || !store.isOnline ? 0.6 : 1)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: - Helpers

    private func rowBackground(_ highlighted: Bool) -> some View {
        ZStack {
            Palette.card
            if highlighted {
                Palette.warning.opacity(0.16)
                RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.warning.opacity(0.7), lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder
    private func moveMenu<Item: Identifiable>(id: Item.ID, in keyPath: WritableKeyPath<RecipeDraft, [Item]>) -> some View {
        let items = draft[keyPath: keyPath]
        if let i = items.firstIndex(where: { $0.id == id }) {
            Button { draft[keyPath: keyPath].swapAt(i, i - 1) } label: { Label("Monter", systemImage: "arrow.up") }
                .disabled(i == 0)
            Button { draft[keyPath: keyPath].swapAt(i, i + 1) } label: { Label("Descendre", systemImage: "arrow.down") }
                .disabled(i >= items.count - 1)
            Button(role: .destructive) { draft[keyPath: keyPath].remove(at: i) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func initialize() {
        guard !didInit else { return }
        didInit = true
        tagsText = draft.tags.joined(separator: ", ")
    }

    private func toggle(_ c: RecipeCategory) {
        if draft.categories.contains(c) {
            guard draft.categories.count > 1 else {
                notice = String(localized: "Garde au moins une catégorie")
                return
            }
            draft.categories.removeAll { $0 == c }
        } else {
            draft.categories = RecipeCategory.allCases.filter { draft.categories.contains($0) || $0 == c }
        }
        notice = nil
    }

    private func pasteIngredients() {
        guard let text = Clipboard.string else { return }
        let parsed = IngredientLineParser.parseList(text)
        guard !parsed.isEmpty else { return }
        draft.ingredients.append(contentsOf: parsed)
    }

    private func chooseDetection(_ i: Int) {
        let d = detections[i]
        guard pages.indices.contains(d.imageIndex) else { return }
        selectedDetection = i
        let page = pages[d.imageIndex]
        Task {
            guard let cropped = await ImagePipeline.cropAsync(page, box: d.box) else {
                photoError = String(localized: "Oups, le recadrage a échoué")
                return
            }
            await setDishPhoto(cropped)
        }
    }

    private func buildDetectionThumbs() async {
        var thumbs: [Int: UIImage] = [:]
        for (i, d) in detections.enumerated() where pages.indices.contains(d.imageIndex) {
            let page = pages[d.imageIndex]
            if let crop = await ImagePipeline.cropAsync(page, box: d.box, padding: 0) {
                thumbs[i] = await Task.detached { ImagePipeline.resized(crop, maxPixel: 240) }.value
            }
        }
        detectionThumbs = thumbs
    }

    /// Makes full and thumb JPEGs, uploads them to `plats/`, and replaces the current photo.
    func setDishPhoto(_ image: UIImage) async {
        guard store.isOnline else { return }
        photoError = nil
        uploading = true
        uploadProgress = 0.1
        defer { uploading = false }
        guard let variants = await ImagePipeline.dishVariantsAsync(image) else {
            photoError = String(localized: "Oups, cette photo n'a pas pu être lue")
            return
        }
        uploadProgress = 0.5
        do {
            let client = store.client, uid = store.userId
            async let full = ImagePipeline.upload(variants.full, folder: .plats, userId: uid, client: client)
            async let thumb = ImagePipeline.upload(variants.thumb, folder: .plats, userId: uid, client: client)
            let (fullPath, thumbPath) = try await (full, thumb)
            uploads.track([fullPath, thumbPath])
            uploads.discard([draft.photoUrl, draft.photoThumbUrl])
            await store.photos.store(variants.full, for: fullPath)
            await store.photos.store(variants.thumb, for: thumbPath)
            draft.photoUrl = fullPath
            draft.photoThumbUrl = thumbPath
            localPreview = image
            uploadProgress = 1
        } catch {
            photoError = String(localized: "Oups, la photo n'a pas pu être envoyée")
        }
    }

    private func removePhoto() {
        uploads.discard([draft.photoUrl, draft.photoThumbUrl])
        draft.photoUrl = nil
        draft.photoThumbUrl = nil
        localPreview = nil
    }

    private func submit() {
        submitError = nil
        if draft.titleMissing { submitError = String(localized: "Le titre est obligatoire"); return }
        if !draft.rightsCertified { submitError = String(localized: "Certifie tes droits avant de partager la recette"); return }
        guard store.isOnline else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await onSubmit()
                savedTick += 1
            } catch {
                submitError = (error as? RecipeRepository.RepositoryError)?.errorDescription
                    ?? String(localized: "Impossible d'enregistrer la recette")
            }
        }
    }
}

/// One ingredient row: quantity, unit, name, aisle, optional.
private struct IngredientEditorRow: View {
    @Binding var ingredient: DraftIngredient
    var highlight: Bool

    @State private var qtyText = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let raw = ingredient.rawText, !raw.isEmpty {
                Text("« \(raw) »").font(AppFont.body(13).italic()).foregroundStyle(Palette.muted)
            }
            HStack(spacing: 8) {
                TextField("Qté", text: $qtyText)
                    .keyboardType(.decimalPad)
                    .frame(width: 56)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Palette.chip, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        if highlight && ingredient.quantityMissing {
                            RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.warning, lineWidth: 1.5)
                        }
                    }
                    .onChange(of: qtyText) { _, t in ingredient.quantity = RecipeDraft.parseNumber(t) }
                Menu {
                    Picker("Unité", selection: $ingredient.unit) {
                        Text("—").tag(String?.none)
                        ForEach(ingredient.unitOptions, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(ingredient.unit ?? "—")
                        Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                    }
                    .font(AppFont.body(14, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Palette.chip, in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel(Text("Unité"))
                TextField("Ingrédient", text: $ingredient.name)
                    .overlay(alignment: .bottom) {
                        if highlight && ingredient.nameMissing { Rectangle().fill(Palette.warning).frame(height: 1.5) }
                    }
            }
            HStack {
                Menu {
                    Picker("Rayon", selection: $ingredient.shoppingCategory) {
                        ForEach(ShoppingAisle.allCases) { Text($0.rawValue.capitalized(with: Locale(identifier: "fr"))).tag($0.rawValue) }
                    }
                } label: {
                    Label(ingredient.shoppingCategory.capitalized(with: Locale(identifier: "fr")), systemImage: "basket")
                        .font(AppFont.body(13, weight: .semibold))
                }
                .accessibilityLabel(Text("Rayon"))
                Spacer()
                Toggle("Facultatif", isOn: $ingredient.optional)
                    .toggleStyle(.button)
                    .font(AppFont.body(13, weight: .semibold))
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            qtyText = ingredient.quantity.map { Quantity.plain($0) } ?? ""
        }
    }
}

extension Quantity {
    /// Plain decimal text for an editable field ("1,5", "200").
    static func plain(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.maximumFractionDigits = 3
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}
