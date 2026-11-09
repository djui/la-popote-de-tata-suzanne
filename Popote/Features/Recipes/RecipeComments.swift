import Observation
import Supabase
import SwiftUI

/// Online comments of a recipe (SPEC §A.11). The last loaded result per recipe is cached in memory.
@MainActor
@Observable
final class RecipeCommentsModel {
    struct Payload {
        var comments: [RecipeComment] = []
        var names: [UUID: String] = [:]
        var stars: [UUID: Int] = [:]
    }

    let recipeId: UUID
    var payload: Payload
    var isLoading = false
    var loadError: String?
    var hasLoaded: Bool

    @ObservationIgnored private static var cache: [UUID: Payload] = [:]

    init(recipeId: UUID) {
        self.recipeId = recipeId
        let cached = Self.cache[recipeId]
        payload = cached ?? Payload()
        hasLoaded = cached != nil
    }

    var visibleCount: Int { payload.comments.filter { $0.deleted != true }.count }

    func replies(to id: UUID) -> [RecipeComment] {
        payload.comments.filter { $0.parentId == id }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    /// Top-level comments, hiding deleted ones that have no replies.
    func topLevel(newestFirst: Bool) -> [RecipeComment] {
        let tops = payload.comments.filter { c in
            c.parentId == nil && (c.deleted != true || payload.comments.contains { $0.parentId == c.id })
        }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        return newestFirst ? tops.reversed() : tops
    }

    func load(client: SupabaseClient) async {
        isLoading = true
        defer { isLoading = false }
        struct StarRow: Decodable { let user_id: UUID; let stars: Int }
        do {
            async let commentsReq: [RecipeComment] = client.from("recipe_comments")
                .select("id,recipe_id,user_id,parent_id,content,edited,deleted,created_at")
                .eq("recipe_id", value: recipeId).order("created_at").execute().value
            async let starsReq: [StarRow] = client.from("recipe_ratings")
                .select("user_id,stars").eq("recipe_id", value: recipeId).execute().value
            let comments = try await commentsReq
            let stars = try await starsReq
            let ids = Array(Set(comments.compactMap(\.userId)))
            var names: [UUID: String] = [:]
            if !ids.isEmpty {
                let profiles: [Profile] = try await client.from("profiles").select("id,first_name")
                    .in("id", values: ids.map(\.uuidString)).execute().value
                for p in profiles { if let id = p.id, let n = p.firstName { names[id] = n } }
            }
            payload = Payload(comments: comments, names: names,
                              stars: Dictionary(stars.map { ($0.user_id, $0.stars) }, uniquingKeysWith: { a, _ in a }))
            Self.cache[recipeId] = payload
            hasLoaded = true
            loadError = nil
        } catch {
            if !AppStore.isCancellation(error) { loadError = String(localized: "Impossible de charger les commentaires.") }
        }
    }

    func post(_ content: String, parentId: UUID?, client: SupabaseClient) async throws {
        struct Row: Encodable { let recipe_id: UUID; let content: String; let parent_id: UUID? }
        try await client.from("recipe_comments")
            .insert(Row(recipe_id: recipeId, content: content.trimmingCharacters(in: .whitespacesAndNewlines), parent_id: parentId))
            .execute()
        await load(client: client)
    }

    func edit(_ id: UUID, content: String, client: SupabaseClient) async throws {
        struct Row: Encodable { let content: String }
        try await client.from("recipe_comments")
            .update(Row(content: content.trimmingCharacters(in: .whitespacesAndNewlines))).eq("id", value: id).execute()
        await load(client: client)
    }

    /// Soft delete when the comment has live replies, hard delete otherwise.
    func delete(_ id: UUID, client: SupabaseClient) async throws {
        let hasLiveReplies = payload.comments.contains { $0.parentId == id && $0.deleted != true }
        if hasLiveReplies {
            struct Row: Encodable { let deleted: Bool; let content: String }
            try await client.from("recipe_comments").update(Row(deleted: true, content: "")).eq("id", value: id).execute()
        } else {
            try await client.from("recipe_comments").delete().eq("id", value: id).execute()
        }
        await load(client: client)
    }
}

/// The comments section on the recipe detail page.
struct RecipeCommentsSection: View {
    @Environment(AppStore.self) private var store
    let recipe: Recipe
    @State private var model: RecipeCommentsModel
    @State private var newestFirst = true
    @State private var pageCount = 1
    @State private var draft = ""
    @State private var replyingTo: UUID?
    @State private var replyDraft = ""
    @State private var editingId: UUID?
    @State private var editDraft = ""
    @State private var pendingDelete: RecipeComment?
    @State private var sending = false
    @State private var errorText: String?

    init(recipe: Recipe) {
        self.recipe = recipe
        _model = State(initialValue: RecipeCommentsModel(recipeId: recipe.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Commentaires (\(model.visibleCount))")
                    .font(AppFont.display(22, relativeTo: .title2))
                Spacer()
                Menu {
                    Picker("Trier les commentaires", selection: $newestFirst) {
                        Text("Plus récents").tag(true)
                        Text("Plus anciens").tag(false)
                    }
                } label: {
                    Label(newestFirst ? "Plus récents" : "Plus anciens", systemImage: "arrow.up.arrow.down")
                        .font(AppFont.body(13, weight: .bold))
                }
                .accessibilityLabel(Text("Trier les commentaires"))
            }

            composer

            if let errorText {
                Text(errorText).font(AppFont.body(13)).foregroundStyle(Palette.destructive)
            }

            if !model.hasLoaded {
                if store.isOnline {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    OfflineNotice(text: "Les commentaires s'afficheront au retour du réseau.")
                }
            } else {
                let tops = model.topLevel(newestFirst: newestFirst)
                if tops.isEmpty {
                    Text("Aucun commentaire pour l'instant. Soyez le premier !")
                        .font(AppFont.body(15))
                        .foregroundStyle(Palette.muted)
                } else {
                    ForEach(tops.prefix(pageCount * 10)) { c in
                        VStack(alignment: .leading, spacing: 12) {
                            commentRow(c, isReply: false)
                            let replies = model.replies(to: c.id)
                            if !replies.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(replies) { r in commentRow(r, isReply: true) }
                                }
                                .padding(.leading, 16)
                                .overlay(alignment: .leading) { Rectangle().fill(Palette.line).frame(width: 2) }
                                .padding(.leading, 18)
                            }
                            if replyingTo == c.id { replyComposer(to: c) }
                        }
                        Divider()
                    }
                    if tops.count > pageCount * 10 {
                        Button("Voir plus") { withAnimation { pageCount += 1 } }
                            .buttonStyle(.popoteSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            if !store.isOnline, model.hasLoaded {
                OfflineNotice(text: "Hors ligne : les commentaires affichés peuvent ne pas être à jour.")
            }
        }
        .task(id: store.isOnline) {
            if store.isOnline { await model.load(client: store.client) }
        }
        .confirmationDialog("Supprimer ce commentaire ?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { c in
            Button("Supprimer", role: .destructive) { run(String(localized: "Suppression impossible")) { try await model.delete(c.id, client: store.client) } }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("Cette action est définitive.")
        }
    }

    // MARK: Composer

    @ViewBuilder private var composer: some View {
        if store.isOnline {
            VStack(alignment: .trailing, spacing: 8) {
                TextField("Partage ton avis, une astuce, une variante…", text: $draft, axis: .vertical)
                    .lineLimit(3...8)
                    .font(AppFont.body(15))
                    .padding(12)
                    .popoteCard(radius: 14)
                    .onChange(of: draft) { _, v in if v.count > 2000 { draft = String(v.prefix(2000)) } }
                HStack {
                    Text(verbatim: "\(draft.count)/2000")
                        .font(AppFont.body(12)).foregroundStyle(Palette.muted).monospacedDigit()
                    Spacer()
                    Button("Publier") {
                        let text = draft
                        run(String(localized: "Publication impossible")) {
                            try await model.post(text, parentId: nil, client: store.client)
                            draft = ""
                        }
                    }
                    .buttonStyle(.popotePrimaryCompact)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                }
            }
        } else {
            OfflineNotice(text: "Hors ligne : tu pourras commenter au retour du réseau.")
        }
    }

    private func replyComposer(to c: RecipeComment) -> some View {
        let name = c.userId.flatMap { model.payload.names[$0] } ?? String(localized: "Membre")
        return VStack(alignment: .trailing, spacing: 8) {
            TextField(String(localized: "Répondre à \(name)…"), text: $replyDraft, axis: .vertical)
                .lineLimit(2...6)
                .font(AppFont.body(15))
                .padding(10)
                .popoteCard(radius: 12)
                .onChange(of: replyDraft) { _, v in if v.count > 2000 { replyDraft = String(v.prefix(2000)) } }
            HStack {
                Button("Annuler") { replyingTo = nil; replyDraft = "" }.buttonStyle(.popoteSecondary)
                Button("Répondre") {
                    let text = replyDraft
                    run(String(localized: "Publication impossible")) {
                        try await model.post(text, parentId: c.id, client: store.client)
                        replyDraft = ""; replyingTo = nil
                    }
                }
                .buttonStyle(.popotePrimaryCompact)
                .disabled(replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending || !store.isOnline)
            }
        }
        .padding(.leading, 34)
    }

    // MARK: Row

    private func commentRow(_ c: RecipeComment, isReply: Bool) -> some View {
        let name = c.userId.flatMap { model.payload.names[$0] }
        let mine = c.userId != nil && c.userId == store.userId
        return HStack(alignment: .top, spacing: 10) {
            Text(verbatim: RecipeFormat.initials(name))
                .font(AppFont.body(13, weight: .heavy))
                .foregroundStyle(Palette.onPrimary)
                .frame(width: 34, height: 34)
                .background(Palette.tileGradient, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if c.deleted == true {
                    Text("Commentaire supprimé").italic().font(AppFont.body(14)).foregroundStyle(Palette.muted)
                } else {
                    HStack(spacing: 6) {
                        Text(name ?? String(localized: "Membre")).font(AppFont.body(14, weight: .heavy))
                        if c.userId != nil, c.userId == recipe.createdBy {
                            Text("Auteur de la recette")
                                .font(AppFont.body(11, weight: .bold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Palette.chip, in: Capsule())
                        }
                        if let uid = c.userId, let stars = model.payload.stars[uid] {
                            HStack(spacing: 1) {
                                ForEach(0..<stars, id: \.self) { _ in Image(systemName: "star.fill") }
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.primary)
                            .accessibilityElement()
                            .accessibilityLabel(Text("\(stars) étoiles"))
                        }
                    }
                    HStack(spacing: 0) {
                        Text(relative(c.createdAt))
                        if c.edited == true { Text(" · modifié") }
                    }
                    .font(AppFont.body(12)).foregroundStyle(Palette.muted)

                    if editingId == c.id {
                        TextField("", text: $editDraft, axis: .vertical)
                            .lineLimit(2...8).font(AppFont.body(15)).padding(10).popoteCard(radius: 12)
                        HStack {
                            Button("Annuler") { editingId = nil }.buttonStyle(.popoteSecondary)
                            Button("Enregistrer") {
                                let text = editDraft
                                run(String(localized: "Modification impossible")) {
                                    try await model.edit(c.id, content: text, client: store.client)
                                    editingId = nil
                                }
                            }
                            .buttonStyle(.popotePrimaryCompact)
                            .disabled(editDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending || !store.isOnline)
                        }
                    } else {
                        Text(c.content).font(AppFont.body(15)).textSelection(.enabled)
                    }
                    if !isReply, store.isOnline, editingId != c.id {
                        Button("Répondre") { replyingTo = c.id; replyDraft = "" }
                            .font(AppFont.body(13, weight: .bold))
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.primary)
                            .padding(.top, 2)
                    }
                }
            }
            Spacer(minLength: 0)
            if mine, c.deleted != true, store.isOnline {
                Menu {
                    Button { editingId = c.id; editDraft = c.content } label: { Label("Modifier", systemImage: "pencil") }
                    Button(role: .destructive) { pendingDelete = c } label: { Label("Supprimer", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .foregroundStyle(Palette.muted)
                .accessibilityLabel(Text("Options du commentaire"))
            }
        }
    }

    private func relative(_ date: Date?) -> String {
        guard let date else { return "" }
        if abs(date.timeIntervalSinceNow) < 60 { return String(localized: "à l'instant") }
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }

    private func run(_ failure: String, _ work: @escaping () async throws -> Void) {
        sending = true
        errorText = nil
        Task {
            do { try await work() } catch { errorText = failure }
            sending = false
        }
    }
}
