import Foundation
import Observation
import UIKit

/// State machine of `/recettes/nouvelle` (SPEC Part N): category → source → (photos | text | url) → review.
@MainActor
@Observable
final class NewRecipeModel {
    enum Step: Hashable { case source, photos, text, url, review }

    var path: [Step] = []
    var category: RecipeCategory = .plat
    var draft = RecipeDraft.blank()
    var aiHighlight = false
    var logId: String?

    // Photos
    var pages: [UIImage] = []
    var detections: [AiDetection] = []
    var sourceUploads: [String] = []

    // Text
    var text = ""
    var textRevealed = false

    // URL
    var url = ""
    var urlError: String?
    var duplicate: RecipeRepository.SimilarRecipe?

    // Shared
    var busy = false
    var busyTitle: String = ""
    var progress: Double?
    var banner: String?
    var candidates: [AiRecipe] = []
    var showPicker = false

    static let maxPages = 6
    static let maxText = 15_000

    let uploads: UploadSession
    private let store: AppStore

    init(store: AppStore, startWithPhoto: Bool) {
        self.store = store
        uploads = UploadSession(client: store.client)
        if startWithPhoto { path = [.source, .photos] }
    }

    var reviewTitle: String {
        aiHighlight || !draft.title.isEmpty ? String(localized: "Vérifie la recette") : String(localized: "Nouvelle recette")
    }

    func choose(_ c: RecipeCategory) {
        category = c
        if path.isEmpty { path = [.source] }
    }

    func manualEntry() {
        draft = .blank(category: category)
        aiHighlight = false
        logId = nil
        pages = []
        detections = []
        path.append(.review)
    }

    // MARK: - Photos (SPEC §N.5)

    func addPages(_ images: [UIImage]) {
        let room = Self.maxPages - pages.count
        guard room > 0 else { return }
        pages.append(contentsOf: images.prefix(room))
    }

    func removePage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        pages.remove(at: index)
    }

    func analyzePhotos() async {
        guard !pages.isEmpty, !busy, store.isOnline else { return }
        busy = true
        banner = nil
        busyTitle = String(localized: "Préparation des photos…")
        progress = 0
        defer { busy = false; progress = nil }

        do {
            let n = Double(pages.count)
            var compressed: [Data] = []
            for (i, page) in pages.enumerated() {
                guard let data = await ImagePipeline.jpegAsync(page, budget: .sourcePage) else { throw ImagePipeline.PipelineError.encoding }
                compressed.append(data)
                progress = (Double(i) + 0.6) / n * 0.9
            }

            // Stale uploads from an earlier attempt.
            uploads.discard(sourceUploads)
            sourceUploads = []

            let client = store.client, uid = store.userId
            let paths = try await withThrowingTaskGroup(of: (Int, String).self) { group in
                for (i, data) in compressed.enumerated() {
                    group.addTask { (i, try await ImagePipeline.upload(data, folder: .sources, userId: uid, client: client)) }
                }
                var result = [String](repeating: "", count: compressed.count)
                for try await (i, path) in group { result[i] = path }
                return result
            }
            uploads.track(paths)
            sourceUploads = paths
            progress = 1
            busyTitle = String(localized: "Lecture de la recette…")
            progress = nil

            let images = compressed.map(ImagePipeline.dataURL(jpeg:))
            let result = try await store.serverFunctions.call(ServerFunctions.ID.photoToRecipe, data: ["images": images])
            let dict = result as? [String: Any] ?? [:]
            logId = AiJSON.string(dict["logId"])
            let recipe = AiRecipe(json: dict["recipe"])
            let fallback = (dict["dishPhotos"] as? [Any] ?? []).compactMap(AiDetection.init(json:))
            detections = (recipe?.dishPhotos.isEmpty == false ? recipe?.dishPhotos : fallback) ?? fallback

            var base = RecipeDraft.blank(category: category)
            base.sourceImageUrls = paths
            if let main = AiDetection.main(detections), pages.indices.contains(main.imageIndex),
               let crop = await ImagePipeline.cropAsync(pages[main.imageIndex], box: main.box) {
                if let (full, thumb) = await uploadDishPhoto(crop) {
                    base.photoUrl = full
                    base.photoThumbUrl = thumb
                }
            }

            if let recipe, AiJSON.string(dict["error"]) == nil {
                draft = base.merging(recipe, chosen: category)
                aiHighlight = true
            } else {
                banner = AiJSON.string(dict["error"]) ?? String(localized: "Analyse impossible")
                draft = base
                aiHighlight = false
            }
            path.append(.review)
        } catch {
            banner = (error as? ServerFunctions.CallError)?.errorDescription ?? String(localized: "Échec de l'envoi des photos")
        }
    }

    /// Full + thumb JPEGs of a dish photo uploaded to `plats/`. Failures are only logged.
    func uploadDishPhoto(_ image: UIImage) async -> (String, String)? {
        guard let variants = await ImagePipeline.dishVariantsAsync(image) else { return nil }
        let client = store.client, uid = store.userId
        do {
            async let full = ImagePipeline.upload(variants.full, folder: .plats, userId: uid, client: client)
            async let thumb = ImagePipeline.upload(variants.thumb, folder: .plats, userId: uid, client: client)
            let pair = try await (full, thumb)
            uploads.track([pair.0, pair.1])
            await store.photos.store(variants.full, for: pair.0)
            await store.photos.store(variants.thumb, for: pair.1)
            return pair
        } catch {
            print("photo du plat:", error)
            return nil
        }
    }

    // MARK: - Text (SPEC §N.3)

    func pasteText() async {
        if let s = Clipboard.string {
            text = String(s.prefix(Self.maxText))
            textRevealed = true
            await parseText()
        } else {
            textRevealed = true
            banner = String(localized: "Colle ta recette dans la zone ci-dessous")
        }
    }

    func parseText() async {
        let input = String(text.prefix(Self.maxText))
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !busy, store.isOnline else { return }
        if let single = URLSafety.singleURL(in: input), URLSafety.isSafe(single) {
            url = single
            if let i = path.lastIndex(of: .text) { path[i] = .url } else { path.append(.url) }
            await importURL()
            return
        }
        busy = true
        banner = nil
        busyTitle = String(localized: "Lecture de la recette…")
        defer { busy = false }
        do {
            let result = try await store.serverFunctions.call(ServerFunctions.ID.textToRecipes, data: ["text": input])
            let dict = result as? [String: Any] ?? [:]
            logId = AiJSON.string(dict["logId"])
            let recipes = (dict["recipes"] as? [Any] ?? []).compactMap { AiRecipe(json: $0) }
            resetPhotos()
            handle(recipes, base: .blank(category: category), error: AiJSON.string(dict["error"]) ?? String(localized: "Lecture impossible"))
        } catch {
            banner = String(localized: "Lecture impossible, réessaie dans un instant.")
        }
    }

    // MARK: - URL (SPEC §N.4)

    func pasteURL() {
        if let s = Clipboard.string, let found = URLSafety.extractURL(from: s) ?? (URLSafety.isSafe(s) ? s : nil) {
            url = found
            urlError = nil
        } else {
            urlError = String(localized: "Colle le lien dans le champ")
        }
    }

    func importURL(force: Bool = false) async {
        var candidate = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty, !candidate.contains("://") { candidate = "https://" + candidate }
        guard URLSafety.isSafe(candidate) else {
            urlError = String(localized: "Ce lien ne semble pas valide. Vérifie qu'il commence par https://")
            return
        }
        guard !busy, store.isOnline else { return }
        url = candidate
        urlError = nil
        busy = true
        busyTitle = String(localized: "Lecture de la page…")
        defer { busy = false }

        if !force, let existing = await RecipeRepository(store: store).existing(sourceURL: candidate) {
            duplicate = existing
            return
        }

        do {
            let result = try await store.serverFunctions.call(ServerFunctions.ID.urlToRecipes, data: ["url": candidate])
            let dict = result as? [String: Any] ?? [:]
            logId = AiJSON.string(dict["logId"])
            let recipes = (dict["recipes"] as? [Any] ?? []).compactMap { AiRecipe(json: $0) }
            guard !recipes.isEmpty else {
                urlError = AiJSON.string(dict["error"]) ?? String(localized: "Tata Suzanne n'arrive pas à lire cette page. Copie le texte de la recette et utilise « Coller un texte ».")
                return
            }
            var base = RecipeDraft.blank(category: category)
            base.sourceUrl = candidate
            base.sourceInspiration = AiJSON.string(dict["site"]).flatMap { $0.isEmpty ? nil : $0 }
            if let imageURL = AiJSON.string(dict["image"]), let pair = await downloadDishImage(imageURL) {
                base.photoUrl = pair.0
                base.photoThumbUrl = pair.1
            }
            resetPhotos()
            handle(recipes, base: base, error: nil)
        } catch {
            urlError = String(localized: "Tata Suzanne n'arrive pas à lire cette page. Copie le texte de la recette et utilise « Coller un texte ».")
        }
    }

    private func downloadDishImage(_ string: String) async -> (String, String)? {
        guard URLSafety.isSafe(string), let u = URL(string: string) else { return nil }
        do {
            var request = URLRequest(url: u)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let image = await ImagePipeline.decode(data) else { return nil }
            return await uploadDishPhoto(image)
        } catch {
            print("photo du plat:", error)
            return nil
        }
    }

    func switchToText() {
        textRevealed = true
        if let i = path.lastIndex(of: .url) { path[i] = .text } else { path.append(.text) }
    }

    // MARK: - Results

    private var pendingBase = RecipeDraft.blank()

    private func handle(_ recipes: [AiRecipe], base: RecipeDraft, error: String?) {
        switch recipes.count {
        case 0:
            banner = error
            draft = base
            aiHighlight = false
            path.append(.review)
        case 1:
            draft = base.merging(recipes[0], chosen: category)
            aiHighlight = true
            path.append(.review)
        default:
            pendingBase = base
            candidates = recipes
            showPicker = true
        }
    }

    func pick(_ recipe: AiRecipe) {
        showPicker = false
        draft = pendingBase.merging(recipe, chosen: category)
        aiHighlight = true
        path.append(.review)
    }

    private func resetPhotos() {
        pages = []
        detections = []
    }

    // MARK: - Save (SPEC §N.8)

    func similarTitles() async throws -> [RecipeRepository.SimilarRecipe] {
        try await RecipeRepository(store: store).similarTitles(to: draft.title)
    }

    func save() async throws -> UUID {
        let id = try await RecipeRepository(store: store).save(draft, logId: logId)
        try? await store.refreshRecipe(id)
        return id
    }

    func cancel() {
        uploads.cleanup()
    }
}
