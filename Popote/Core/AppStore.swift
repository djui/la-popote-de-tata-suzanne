import Foundation
import Network
import OSLog
import Observation
import Supabase

/// The single source of truth for the UI.
///
/// Everything the user can read is mirrored into memory and persisted to disk (`Snapshot`), so the
/// app works fully offline. Writes are applied optimistically and queued in an outbox (`PendingOp`)
/// that is replayed in order whenever the network is available.
@MainActor
@Observable
final class AppStore {
    nonisolated static let log = Logger(subsystem: "net.dauernheim.popote", category: "sync")
    // MARK: Session
    enum AuthState: Equatable { case loading, signedOut, signedIn }
    var authState: AuthState = .loading
    var userId: UUID?
    var email: String?

    // MARK: Data (mirrors of Supabase tables)
    var recipes: [Recipe] = []
    var ingredientsByRecipe: [UUID: [RecipeIngredient]] = [:]
    var stepsByRecipe: [UUID: [RecipeStep]] = [:]
    var authorNames: [UUID: String] = [:]
    var ingredients: [Ingredient] = []
    var aisles: [IngredientCategory] = []
    var household: Household?
    var members: [HouseholdMember] = []
    var memberNames: [UUID: String] = [:]
    var categoryOrders: [HouseholdCategoryOrder] = []
    var ingredientOverrides: [HouseholdIngredientOverride] = []
    var mealPlan: [MealPlanEntry] = []
    var shoppingItems: [ShoppingListItem] = []
    var favorites: [UUID: Date] = [:]
    var myRatings: [UUID: Int] = [:]
    var profile: Profile?
    var isAdmin = false
    var termsAccepted: Bool?

    // MARK: Sync state
    var isOnline = true
    var isSyncing = false
    var lastSync: Date?
    var lastError: String?
    var pendingOps: [PendingOp] = []
    /// Bumped whenever recipe photos finish downloading, so views can refresh.
    var photoProgress: (done: Int, total: Int) = (0, 0)

    let client = Backend.client
    @ObservationIgnored let photos = PhotoCache()
    @ObservationIgnored lazy var serverFunctions = ServerFunctions(accessToken: { [client] in
        try? await client.auth.session.accessToken
    })
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var realtimeChannel: RealtimeChannelV2?
    @ObservationIgnored private var realtimeTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var authTask: Task<Void, Never>?

    init() {
        loadSnapshot()
        startNetworkMonitor()
    }

    // MARK: - Lifecycle

    func start() {
        guard authTask == nil else { return }
        #if DEBUG
        // UI testing helper: sign in from a refresh token passed by the developer at launch.
        if let token = ProcessInfo.processInfo.environment["POPOTE_DEBUG_REFRESH_TOKEN"], !token.isEmpty {
            Task { _ = try? await client.auth.refreshSession(refreshToken: token) }
        }
        #endif
        authTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let session, !(session.isExpired && !self.isOnline && event != .initialSession) {
                        let changedUser = self.userId != session.user.id
                        self.userId = session.user.id
                        self.email = session.user.email
                        self.authState = .signedIn
                        if changedUser || event == .initialSession || event == .signedIn {
                            await self.refresh()
                            self.subscribeRealtime()
                        }
                    } else if event == .initialSession {
                        // Offline with an expired token: keep showing cached data if we have it.
                        self.authState = self.userId != nil ? .signedIn : .signedOut
                    }
                case .signedOut:
                    self.handleSignedOut()
                default:
                    break
                }
            }
        }
    }

    private func handleSignedOut() {
        authState = .signedOut
        userId = nil
        email = nil
        clearData()
        unsubscribeRealtime()
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
    }

    func signUp(email: String, password: String, firstName: String, inviteCode: String, termsAccepted: Bool) async throws {
        try await client.auth.signUp(
            email: email.trimmingCharacters(in: .whitespaces),
            password: password,
            data: [
                "invite_code": .string(inviteCode.trimmingCharacters(in: .whitespaces)),
                "first_name": .string(firstName.trimmingCharacters(in: .whitespaces)),
                "terms_version": .string("1.0"),
                "terms_accepted": .bool(termsAccepted),
            ],
            redirectTo: Backend.webURL.appending(path: "recettes")
        )
    }

    func signOut() async {
        try? await client.auth.signOut()
        handleSignedOut()
    }

    func acceptTerms() async throws {
        guard let userId else { return }
        struct Row: Encodable { let user_id: UUID; let terms_version: String }
        do {
            try await client.from("terms_acceptances").insert(Row(user_id: userId, terms_version: "1.0")).execute()
        } catch let error as PostgrestError where error.code == "23505" {
            // Already accepted.
        }
        termsAccepted = true
        saveSnapshot()
    }

    // MARK: - Pull

    /// Replays pending writes, then pulls every table the app mirrors.
    func refresh() async {
        guard authState == .signedIn, isOnline, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        await flushOutbox()
        do {
            lastError = nil
            try await pullAll()
            lastSync = .now
            saveSnapshot()
            WidgetBridge.publish(from: self)
            SpotlightIndexer.index(recipes: recipes, store: self)
            Task { await self.downloadPhotos() }
        } catch {
            if !Self.isCancellation(error) {
                lastError = error.localizedDescription
                Self.log.error("sync failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func pullAll() async throws {
        guard let uid = userId else { return }
        let db = client
        let since = LocalDay.string(Calendar.current.date(byAdding: .day, value: -35, to: .now) ?? .now)

        async let recipesReq: [RecipeWithChildren] = db.from("recipes")
            .select("*, recipe_ingredients(*), recipe_steps(*), author:profiles!recipes_created_by_fkey(first_name)")
            .order("created_at", ascending: false)
            .execute().value
        async let ingredientsReq: [Ingredient] = db.from("ingredients")
            .select("id,name,display_name,plural_name,aliases,category_id,seasons,verified,source,pending_ai")
            .order("name").execute().value
        async let aislesReq: [IngredientCategory] = db.from("ingredient_categories")
            .select("id,name,name_en,color,icon,sort_order").execute().value
        async let householdReq: [Household] = db.from("households")
            .select("id,name,default_servings").limit(1).execute().value
        async let membersReq: [HouseholdMember] = db.from("household_members")
            .select("user_id,role,joined_at").order("joined_at").execute().value
        async let ordersReq: [CategoryOrderRow] = db.from("household_category_orders")
            .select("category_id,sort_order").execute().value
        async let overridesReq: [HouseholdIngredientOverride] = db.from("household_ingredient_overrides")
            .select("ingredient_id,category_id").execute().value
        async let mealReq: [MealPlanEntry] = db.from("meal_plan_entries")
            .select("id,date,meal_type,recipe_id,custom_title,servings,position")
            .gte("date", value: since).order("position").execute().value
        async let shoppingReq: [ShoppingListItem] = db.from("shopping_list_items")
            .select("*").gte("week_start", value: since).order("created_at").execute().value
        async let favoritesReq: [FavoriteRow] = db.from("recipe_favorites")
            .select("recipe_id,created_at").execute().value
        async let ratingsReq: [RatingRow] = db.from("recipe_ratings")
            .select("recipe_id,stars").eq("user_id", value: uid).execute().value
        async let profileReq: [Profile] = db.from("profiles")
            .select("id,first_name,preferred_language").eq("id", value: uid).limit(1).execute().value
        async let rolesReq: [RoleRow] = db.from("user_roles")
            .select("role").eq("user_id", value: uid).execute().value
        async let termsReq: [TermsRow] = db.from("terms_acceptances")
            .select("accepted_at").eq("user_id", value: uid).eq("terms_version", value: "1.0").limit(1).execute().value

        // Recipes are essential: if they fail, the whole sync fails. Every other table is best-effort, so one
        // failing query (a renamed column, a policy change…) never blocks the rest.
        let rows = try await recipesReq
        recipes = rows.map(\.recipe)
        ingredientsByRecipe = Dictionary(uniqueKeysWithValues: rows.map { ($0.recipe.id, ($0.recipeIngredients ?? []).sorted { $0.position < $1.position }) })
        stepsByRecipe = Dictionary(uniqueKeysWithValues: rows.map { ($0.recipe.id, ($0.recipeSteps ?? []).sorted { $0.position < $1.position }) })
        authorNames = Dictionary(rows.compactMap { r in r.recipe.createdBy.flatMap { id in r.author?.firstName.map { (id, $0) } } }, uniquingKeysWith: { a, _ in a })

        var failures: [String] = []
        func note(_ table: String, _ error: Error) {
            failures.append(table)
            Self.log.error("sync \(table, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }

        do { ingredients = try await ingredientsReq } catch { note("ingredients", error) }
        do { aisles = try await aislesReq.sorted { ($0.sortOrder ?? 0) < ($1.sortOrder ?? 0) } } catch { note("ingredient_categories", error) }
        do { household = try await householdReq.first } catch { note("households", error) }
        do { members = try await membersReq } catch { note("household_members", error) }
        do {
            let orders = try await ordersReq
            categoryOrders = household.map { h in orders.map { HouseholdCategoryOrder(householdId: h.id, categoryId: $0.category_id, sortOrder: $0.sort_order) } } ?? []
        } catch { note("household_category_orders", error) }
        do { ingredientOverrides = try await overridesReq } catch { note("household_ingredient_overrides", error) }
        do { mealPlan = mergePending(try await mealReq) } catch { note("meal_plan_entries", error) }
        do { shoppingItems = mergePendingShopping(try await shoppingReq) } catch { note("shopping_list_items", error) }
        do { favorites = Dictionary(try await favoritesReq.map { ($0.recipe_id, $0.created_at ?? .distantPast) }, uniquingKeysWith: { a, _ in a }) } catch { note("recipe_favorites", error) }
        do { myRatings = Dictionary(try await ratingsReq.map { ($0.recipe_id, $0.stars) }, uniquingKeysWith: { a, _ in a }) } catch { note("recipe_ratings", error) }
        do {
            profile = try await profileReq.first
            adoptProfileLanguage()
        } catch { note("profiles", error) }
        do { isAdmin = try await rolesReq.contains { $0.role == "admin" } } catch { note("user_roles", error) }
        do { termsAccepted = !(try await termsReq).isEmpty } catch { note("terms_acceptances", error) }

        let memberIds = members.map(\.userId)
        if !memberIds.isEmpty {
            do {
                let names: [Profile] = try await db.from("profiles").select("id,first_name")
                    .in("id", values: memberIds.map { $0.uuidString.lowercased() }).execute().value
                memberNames = Dictionary(names.compactMap { p in p.id.flatMap { id in p.firstName.map { (id, $0) } } }, uniquingKeysWith: { a, _ in a })
            } catch { note("profiles (members)", error) }
        }
        if !failures.isEmpty { lastError = String(localized: "Synchronisation partielle : \(failures.joined(separator: ", "))") }
    }

    /// Like the website: a language picked on this device wins and is pushed to the profile;
    /// otherwise the language saved on the profile (e.g. chosen on the website) is applied.
    private func adoptProfileLanguage() {
        guard let saved = profile?.preferredLanguage.flatMap(AppLanguage.init(rawValue:)) else {
            if AppLanguage.hasExplicitChoice { Task { await setLanguage(AppLanguage.current) } }
            return
        }
        if AppLanguage.hasExplicitChoice, saved != AppLanguage.current {
            Task { await setLanguage(AppLanguage.current) }
        } else if !AppLanguage.hasExplicitChoice, saved != AppLanguage.current {
            UserDefaults.standard.set(saved.rawValue, forKey: AppLanguage.storageKey)
            NotificationCenter.default.post(name: .popoteLanguageChanged, object: saved)
        }
    }

    /// Re-pulls only the menu and shopping list (used by realtime notifications).
    func refreshLiveTables() async {
        guard authState == .signedIn, isOnline else { return }
        let since = LocalDay.string(Calendar.current.date(byAdding: .day, value: -35, to: .now) ?? .now)
        do {
            let meals: [MealPlanEntry] = try await client.from("meal_plan_entries")
                .select("id,date,meal_type,recipe_id,custom_title,servings,position")
                .gte("date", value: since).order("position").execute().value
            let items: [ShoppingListItem] = try await client.from("shopping_list_items")
                .select("*").gte("week_start", value: since).order("created_at").execute().value
            mealPlan = mergePending(meals)
            shoppingItems = mergePendingShopping(items)
            saveSnapshot()
            WidgetBridge.publish(from: self)
        } catch {}
    }

    /// Re-pulls a single recipe with its ingredients and steps (after create or edit).
    func refreshRecipe(_ id: UUID) async throws {
        let row: RecipeWithChildren = try await client.from("recipes")
            .select("*, recipe_ingredients(*), recipe_steps(*), author:profiles!recipes_created_by_fkey(first_name)")
            .eq("id", value: id).single().execute().value
        if let i = recipes.firstIndex(where: { $0.id == id }) { recipes[i] = row.recipe } else { recipes.insert(row.recipe, at: 0) }
        ingredientsByRecipe[id] = (row.recipeIngredients ?? []).sorted { $0.position < $1.position }
        stepsByRecipe[id] = (row.recipeSteps ?? []).sorted { $0.position < $1.position }
        if let by = row.recipe.createdBy, let n = row.author?.firstName { authorNames[by] = n }
        saveSnapshot()
        SpotlightIndexer.index(recipes: [row.recipe], store: self)
        Task { await self.downloadPhotos() }
    }

    func removeRecipeLocally(_ id: UUID) {
        recipes.removeAll { $0.id == id }
        ingredientsByRecipe[id] = nil
        stepsByRecipe[id] = nil
        favorites[id] = nil
        saveSnapshot()
        SpotlightIndexer.remove(recipeId: id)
    }

    // MARK: - Photos

    func downloadPhotos() async {
        let paths = recipes.flatMap { [$0.photoThumbUrl, $0.photoUrl].compactMap { $0 } }
        let missing = await photos.missing(paths)
        guard !missing.isEmpty, isOnline else { return }
        photoProgress = (0, missing.count)
        let storage = client.storage.from(Backend.photoBucket)
        await withTaskGroup(of: Void.self) { group in
            var iterator = missing.makeIterator()
            func addNext() {
                guard let path = iterator.next() else { return }
                group.addTask { [photos] in
                    if let data = try? await storage.download(path: path) {
                        await photos.store(data, for: path)
                    }
                }
            }
            for _ in 0..<6 { addNext() }
            while await group.next() != nil {
                photoProgress.done += 1
                addNext()
            }
        }
    }

    /// Loads a photo from disk, downloading it first if needed.
    func photoData(_ path: String) async -> Data? {
        if let data = await photos.data(for: path) { return data }
        guard isOnline, authState == .signedIn else { return nil }
        guard let data = try? await client.storage.from(Backend.photoBucket).download(path: path) else { return nil }
        await photos.store(data, for: path)
        return data
    }

    // MARK: - Realtime

    private func subscribeRealtime() {
        unsubscribeRealtime()
        let channel = client.realtimeV2.channel("popote-live-\(UUID().uuidString.prefix(8))")
        let meals = channel.postgresChange(AnyAction.self, schema: "public", table: "meal_plan_entries")
        let shopping = channel.postgresChange(AnyAction.self, schema: "public", table: "shopping_list_items")
        realtimeChannel = channel
        realtimeTasks = [
            Task { [weak self] in for await _ in meals { await self?.debouncedLiveRefresh() } },
            Task { [weak self] in for await _ in shopping { await self?.debouncedLiveRefresh() } },
            Task { try? await channel.subscribeWithError() },
        ]
    }

    private func unsubscribeRealtime() {
        realtimeTasks.forEach { $0.cancel() }
        realtimeTasks = []
        if let channel = realtimeChannel {
            Task { await channel.unsubscribe() }
        }
        realtimeChannel = nil
    }

    @ObservationIgnored private var liveRefreshTask: Task<Void, Never>?
    private func debouncedLiveRefresh() async {
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.refreshLiveTables()
        }
    }

    // MARK: - Network

    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
                if online { await self.refresh() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "net.dauernheim.popote.network"))
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }

    static func isOfflineError(_ error: Error) -> Bool {
        guard let url = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed].contains(url.code)
    }
}

// MARK: - Decoding helpers

struct RecipeWithChildren: Decodable {
    var recipe: Recipe
    var recipeIngredients: [RecipeIngredient]?
    var recipeSteps: [RecipeStep]?
    var author: Profile?

    enum CodingKeys: String, CodingKey {
        case recipeIngredients = "recipe_ingredients"
        case recipeSteps = "recipe_steps"
        case author
    }

    init(from decoder: Decoder) throws {
        recipe = try Recipe(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recipeIngredients = try c.decodeIfPresent([RecipeIngredient].self, forKey: .recipeIngredients)
        recipeSteps = try c.decodeIfPresent([RecipeStep].self, forKey: .recipeSteps)
        author = try? c.decodeIfPresent(Profile.self, forKey: .author)
    }
}

struct CategoryOrderRow: Decodable { let category_id: String; let sort_order: Int }
struct FavoriteRow: Decodable { let recipe_id: UUID; let created_at: Date? }
struct RatingRow: Decodable { let recipe_id: UUID; let stars: Int }
struct RoleRow: Decodable { let role: String }
struct TermsRow: Decodable { let accepted_at: Date? }
