import Foundation
import Testing
@testable import Popote

struct RecipeSearchTests {
    @Test func normalisation() {
        #expect(RecipeSearch.norm("Crème") == "creme")
        #expect(RecipeSearch.norm("Œufs") == "oeuf")
        #expect(RecipeSearch.norm("chevaux") == "cheval")
        #expect(RecipeSearch.norm("noix") == "noi")
        #expect(RecipeSearch.norm("os") == "os")
    }

    @Test func accentInsensitiveSearch() {
        #expect(RecipeSearch.matches("creme", "Crème brûlée"))
        #expect(RecipeSearch.matches("BRULEE", "Crème brûlée"))
        #expect(RecipeSearch.matches("oeuf", "3 œufs frais"))
        #expect(RecipeSearch.matches("tom", "Tarte aux tomates"))
        #expect(RecipeSearch.matches("tarte tomate", "Tarte aux tomates"))
        #expect(!RecipeSearch.matches("tarte poire", "Tarte aux tomates"))
        #expect(RecipeSearch.matches("", "anything"))
        #expect(RecipeSearch.matches("pates", "Pâtes à la carbonara"))
    }
}

struct RecipeFilterTests {
    let me = UUID()

    func recipe(_ title: String, categories: [String] = ["plat"], seasons: [String]? = nil, prep: Int? = nil, cook: Int? = nil,
                tags: [String]? = nil, rating: Double? = nil, by: UUID? = nil, created: TimeInterval = 0) -> Recipe {
        Recipe(id: UUID(), title: title, categories: categories, seasons: seasons, servings: 4, prepTimeMin: prep, cookTimeMin: cook,
               tags: tags, createdAt: Date(timeIntervalSince1970: created), createdBy: by, ratingAvg: rating, ratingCount: rating == nil ? 0 : 1)
    }

    func ingredients(_ r: Recipe, _ names: [String]) -> [UUID: [RecipeIngredient]] {
        [r.id: names.enumerated().map { RecipeIngredient(id: UUID(), recipeId: r.id, position: $0.offset, name: $0.element) }]
    }

    @Test func categoriesSeasonsAndTime() {
        let soup = recipe("Soupe", categories: ["soupe"], seasons: ["hiver"], prep: 10, cook: 20)
        let salad = recipe("Salade", categories: ["salade"], seasons: ["toute l'année"], prep: 10)
        let cake = recipe("Gâteau", categories: ["gâteau"], seasons: ["été"])
        let all = [soup, salad, cake]

        var f = RecipeFilterState()
        f.categories = [.soupe, .salade]
        #expect(f.apply(to: all, ingredientsByRecipe: [:], favorites: [:], userId: nil, sort: .recent).map(\.title).sorted() == ["Salade", "Soupe"])

        f = RecipeFilterState()
        f.toggleSeasonal(.hiver)
        #expect(f.isInSeasonFilter(.hiver))
        #expect(Set(f.apply(to: all, ingredientsByRecipe: [:], favorites: [:], userId: nil, sort: .recent).map(\.title)) == ["Soupe", "Salade"])
        f.toggleSeasonal(.hiver)
        #expect(f.seasons.isEmpty)

        f = RecipeFilterState()
        f.maxTime = 15
        // Time 0 is excluded, 30 > 15 is excluded.
        #expect(f.apply(to: all, ingredientsByRecipe: [:], favorites: [:], userId: nil, sort: .recent).map(\.title) == ["Salade"])
    }

    @Test func favoritesMineTagsRatingAndIngredients() {
        let a = recipe("Poulet curry", tags: ["rapide", "épicé"], rating: 4.6, by: me)
        let b = recipe("Risotto", tags: ["rapide"], rating: 3.2)
        var ing = ingredients(a, ["poulet", "lait de coco"])
        ing.merge(ingredients(b, ["riz", "champignons"])) { x, _ in x }

        var f = RecipeFilterState()
        f.favorites = true
        #expect(f.apply(to: [a, b], ingredientsByRecipe: ing, favorites: [b.id: .now], userId: me, sort: .recent).map(\.title) == ["Risotto"])

        f = RecipeFilterState(mine: true)
        #expect(f.apply(to: [a, b], ingredientsByRecipe: ing, favorites: [:], userId: me, sort: .recent).map(\.title) == ["Poulet curry"])

        f = RecipeFilterState()
        f.tags = ["rapide", "épicé"]
        #expect(f.apply(to: [a, b], ingredientsByRecipe: ing, favorites: [:], userId: me, sort: .recent).map(\.title) == ["Poulet curry"])

        f = RecipeFilterState()
        f.minRating = 4.5
        #expect(f.apply(to: [a, b], ingredientsByRecipe: ing, favorites: [:], userId: me, sort: .recent).map(\.title) == ["Poulet curry"])

        f = RecipeFilterState()
        f.include = ["champignon"]
        #expect(f.apply(to: [a, b], ingredientsByRecipe: ing, favorites: [:], userId: me, sort: .recent).map(\.title) == ["Risotto"])
        f = RecipeFilterState()
        f.exclude = ["champignon"]
        #expect(f.apply(to: [a, b], ingredientsByRecipe: ing, favorites: [:], userId: me, sort: .recent).map(\.title) == ["Poulet curry"])

        f = RecipeFilterState(q: "coco")
        #expect(f.apply(to: [a, b], ingredientsByRecipe: ing, favorites: [:], userId: me, sort: .recent).map(\.title) == ["Poulet curry"])
    }

    @Test func activeCountAndClear() {
        var f = RecipeFilterState(q: "x", mine: true)
        f.categories = [.plat, .soupe]
        f.maxTime = 30
        f.favorites = true
        f.include = ["tomate"]
        #expect(f.activeCount == 5)
        f.clear()
        #expect(f.activeCount == 0)
        #expect(f.q == "x")
        #expect(f.mine)
    }

    @Test func sorting() {
        let a = recipe("Éclair", prep: 30, rating: 4, created: 3)
        let b = recipe("abricots", rating: 5, created: 2)
        let c = recipe("Crumble", prep: 10, cook: 5, created: 1)
        let all = [c, a, b]
        #expect(RecipeSortOrder.sorted(all, by: .recent, favorites: [:]).map(\.title) == ["Éclair", "abricots", "Crumble"])
        #expect(RecipeSortOrder.sorted(all, by: .alpha, favorites: [:]).map(\.title) == ["abricots", "Crumble", "Éclair"])
        #expect(RecipeSortOrder.sorted(all, by: .time, favorites: [:]).map(\.title) == ["Crumble", "Éclair", "abricots"])
        #expect(RecipeSortOrder.sorted(all, by: .rating, favorites: [:]).map(\.title) == ["abricots", "Éclair", "Crumble"])
        let favs: [UUID: Date] = [c.id: Date(timeIntervalSince1970: 10), a.id: Date(timeIntervalSince1970: 20)]
        #expect(RecipeSortOrder.sorted(all, by: .favorited, favorites: favs).map(\.title) == ["Éclair", "Crumble", "abricots"])
    }

    @Test func formatting() {
        #expect(RecipeFormat.rating(5) == "5,0")
        #expect(RecipeFormat.rating(4.25) == "4,2" || RecipeFormat.rating(4.25) == "4,3")
        #expect(RecipeFormat.names(["Anne", "Paul", "Zoé"]) == "Anne, Paul et Zoé")
        #expect(RecipeFormat.names(["Anne"]) == "Anne")
        #expect(RecipeFormat.initials("tata") == "TA")
        #expect(RecipeFormat.initials(nil) == "?")
    }
}

struct CookTimerParserTests {
    func seconds(_ text: String) -> [[Int]] { CookTimerParser.detect(text).map(\.seconds) }

    @Test func simpleDurations() {
        #expect(seconds("Laisser cuire 10 minutes.") == [[600]])
        #expect(seconds("Cuire 45 s") == [[45]])
        #expect(seconds("Enfourner pour 1 heure") == [[3600]])
        #expect(seconds("Compter 1,5 h de cuisson") == [[5400]])
        #expect(seconds("Laisser mijoter vingt minutes") == [[1200]])
        #expect(seconds("Cuire 5 mn") == [[300]])
    }

    @Test func compoundAndHalf() {
        #expect(seconds("Laisser reposer une demi-heure") == [[1800]])
        #expect(seconds("Cuire 2 h 30 à feu doux") == [[9000]])
        #expect(seconds("Cuire 2h30min") == [[9000]])
        #expect(seconds("Cuire 1 heure et demie") == [[5400]])
    }

    @Test func ranges() {
        #expect(seconds("Cuire 10 à 15 minutes") == [[600, 900]])
        #expect(seconds("Cuire entre 20 et 25 min") == [[1200, 1500]])
        #expect(seconds("Cuire 3-4 min") == [[180, 240]])
    }

    @Test func rejections() {
        #expect(seconds("Ajouter 5 sachets de sucre").isEmpty)
        #expect(seconds("Mettre deux s").isEmpty)
        #expect(seconds("Préchauffer le four à 180°").isEmpty)
        #expect(seconds("Ajouter 100 g de farine").isEmpty)
        #expect(seconds("Laisser lever 72 heures").isEmpty) // > 48 h
        #expect(seconds("ab10 min").isEmpty)
    }

    @Test func multipleInOneStep() {
        #expect(seconds("Cuire 10 min, puis laisser reposer 5 min.") == [[600], [300]])
    }

    @Test func formats() {
        #expect(CookTimerParser.format(3900) == "1 h 05")
        #expect(CookTimerParser.format(3600) == "1 h")
        #expect(CookTimerParser.format(330) == "5 min 30")
        #expect(CookTimerParser.format(300) == "5 min")
        #expect(CookTimerParser.format(45) == "45 s")
        #expect(CookTimerParser.clock(65) == "1:05")
        #expect(CookTimerParser.clock(3725) == "1:02:05")
    }

    @Test func labels() {
        #expect(CookTimerParser.label(language: .fr, stepText: "Faire cuire le poulet 20 min", stepIndex: 0, matchedIngredient: "poulet") == "Cuisson du poulet")
        #expect(CookTimerParser.label(language: .fr, stepText: "Faire dorer les oignons", stepIndex: 0, matchedIngredient: "oignon") == "Cuisson de l'oignon")
        #expect(CookTimerParser.label(language: .fr, stepText: "Faire bouillir les pâtes", stepIndex: 0, matchedIngredient: "pâtes") == "Cuisson des pâtes")
        #expect(CookTimerParser.label(language: .fr, stepText: "Laisser reposer la pâte", stepIndex: 2, matchedIngredient: "farine") == "Repos")
        #expect(CookTimerParser.label(language: .fr, stepText: "Enfourner le plat", stepIndex: 1, matchedIngredient: nil) == "Four")
        #expect(CookTimerParser.label(language: .fr, stepText: "Mélanger", stepIndex: 3, matchedIngredient: nil) == "Étape 4")
    }
}

struct StepIngredientMatcherTests {
    func ing(_ name: String) -> RecipeIngredient {
        RecipeIngredient(id: UUID(), recipeId: UUID(), position: 0, name: name)
    }

    @Test func matching() {
        let list = [ing("oignons rouges"), ing("huile d'olive"), ing("pommes de terre"), ing("sel"), ing("crème fraîche"), ing("petits pois")]
        let names = { (step: String) in StepIngredientMatcher.ingredients(list, for: step).map(\.name) }
        #expect(names("Émincer l'oignon et le faire revenir dans l'huile.") == ["oignons rouges", "huile d'olive"])
        #expect(names("Éplucher les pommes et les couper en dés.") == ["pommes de terre"])
        #expect(names("Ajouter la creme et les pois.") == ["crème fraîche", "petits pois"])
        // Short tokens (≤ 2 letters) are ignored.
        #expect(names("Saler.").isEmpty)
    }

    @Test func hyphenatedImperativesAreIgnored() {
        let list = [ing("ail")]
        #expect(StepIngredientMatcher.stepTokens("Presse-ail").isEmpty)
        #expect(StepIngredientMatcher.ingredients(list, for: "Utiliser un presse-ail").isEmpty)
    }

    @Test func tokens() {
        #expect(StepIngredientMatcher.ingredientTokens("huile d'olive") == ["huile"])
        // Adjectives are dropped before singularising, like the website: "grosses" survives as "grosse".
        #expect(StepIngredientMatcher.ingredientTokens("Grosses carottes") == ["grosse", "carotte"])
        #expect(StepIngredientMatcher.ingredientTokens("petite courgette") == ["courgette"])
    }
}

struct CookSessionTests {
    @Test func persistenceAndExpiry() throws {
        let defaults = try #require(UserDefaults(suiteName: "popote-tests-\(UUID().uuidString)"))
        let id = UUID()
        let s = SavedCookSession(step: 2, struck: [1], servings: 6,
                                 timers: [CookTimer(label: "Four", total: 600, endsAt: .now.addingTimeInterval(600))], savedAt: .now)
        s.save(id, defaults: defaults)
        let loaded = try #require(SavedCookSession.load(id, defaults: defaults))
        #expect(loaded.step == 2)
        #expect(loaded.isWorthResuming)
        #expect(SavedCookSession.load(id, now: .now.addingTimeInterval(13 * 3600), defaults: defaults) == nil)
        #expect(SavedCookSession.load(id, defaults: defaults) == nil)
    }

    @Test func timerSecondsLeft() {
        let now = Date()
        #expect(CookTimer(label: "x", total: 60, endsAt: now.addingTimeInterval(30)).secondsLeft(at: now) == 30)
        #expect(CookTimer(label: "x", total: 60, endsAt: nil, remaining: 12.2).secondsLeft(at: now) == 13)
        #expect(CookTimer(label: "x", total: 60, endsAt: nil, remaining: 12).isPaused)
        #expect(CookTimer(label: "x", total: 60, done: true).secondsLeft(at: now) == 0)
    }
}
