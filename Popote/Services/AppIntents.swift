import AppIntents
import Foundation
import UIKit

/// Recipes as seen by Siri, Shortcuts and Spotlight. Intents may run without any UI, so the data comes
/// from the offline snapshot the app writes to disk (`AppStore.snapshotURL`), not from a live store.
struct RecipeEntity: AppEntity, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let categories: [String]

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Recette")
    static let defaultQuery = RecipeEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: categories.isEmpty ? nil : "\(categories.joined(separator: " · "))",
            image: .init(systemName: "fork.knife")
        )
    }

    init(id: UUID, title: String, categories: [String]) {
        self.id = id
        self.title = title
        self.categories = categories
    }

    init(_ recipe: Recipe) {
        self.init(id: recipe.id, title: recipe.title, categories: recipe.recipeCategories.map(\.label))
    }
}

/// Reads recipes from the offline snapshot.
enum RecipeLibrary {
    static func decode(_ data: Data) -> [Recipe] {
        (try? JSONDecoder.popote.decode(Snapshot.self, from: data))?.recipes ?? []
    }

    static func load() async -> [Recipe] {
        let url = await AppStore.snapshotURL
        return await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return [] }
            return decode(data)
        }.value
    }

    /// Diacritic- and case-insensitive match on the title and the categories.
    static func search(_ query: String, in recipes: [Recipe]) -> [Recipe] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return recipes }
        return recipes.filter { recipe in
            let haystack = ([recipe.title] + recipe.recipeCategories.map(\.label) + (recipe.tags ?? [])).joined(separator: " ")
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}

struct RecipeEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [RecipeEntity] {
        let wanted = Set(identifiers)
        return await RecipeLibrary.load().filter { wanted.contains($0.id) }.map(RecipeEntity.init)
    }

    func entities(matching string: String) async throws -> [RecipeEntity] {
        RecipeLibrary.search(string, in: await RecipeLibrary.load()).prefix(50).map(RecipeEntity.init)
    }

    func suggestedEntities() async throws -> [RecipeEntity] {
        await RecipeLibrary.load()
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .prefix(100)
            .map(RecipeEntity.init)
    }
}

/// Opens the app on a recipe. The id travels through the app's own deep link (`popote://recette/<id>`),
/// which `Router.handle(url:)` already understands.
struct OpenRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Ouvrir une recette"
    static let description = IntentDescription("Ouvre une recette dans La Popote.")
    static let openAppWhenRun = true

    @Parameter(title: "Recette")
    var recipe: RecipeEntity

    init() {}

    init(recipe: RecipeEntity) {
        self.recipe = recipe
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Ouvrir \(\.$recipe)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await IntentRouting.open(URL(string: "popote://recette/\(recipe.id.uuidString)")!)
        return .result()
    }
}

/// Answers "what are we eating?" from the widget snapshot, without opening the app.
struct ShowTodayMenuIntent: AppIntent {
    static let title: LocalizedStringResource = "Menu du jour"
    static let description = IntentDescription("Dit ce qui est prévu au prochain repas.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let selection = WidgetSnapshot.load()?.selection(at: .now) else {
            return .result(dialog: "Rien n'est prévu au menu pour l'instant.")
        }
        var text = "\(selection.label.capitalized(with: AppLanguage.current.locale)) : \(selection.meal.title)."
        if let next = selection.next, let label = selection.nextLabel {
            text += " " + String(localized: "Ensuite, \(label.lowercased(with: AppLanguage.current.locale)) : \(next.title).")
        }
        return .result(dialog: "\(text)")
    }
}

/// Opens a deep link in the running app once it is in the foreground.
@MainActor
enum IntentRouting {
    static func open(_ url: URL) async {
        for _ in 0..<20 where UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await UIApplication.shared.open(url)
    }
}

struct PopoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRecipeIntent(),
            phrases: [
                "Ouvre la recette \(.applicationName)",
                "Ouvre la recette \(\.$recipe) dans \(.applicationName)",
                "Montre la recette \(\.$recipe) dans \(.applicationName)",
            ],
            shortTitle: "Ouvrir une recette",
            systemImageName: "book"
        )
        AppShortcut(
            intent: ShowTodayMenuIntent(),
            phrases: [
                "Qu'est-ce qu'on mange avec \(.applicationName)",
                "Menu du jour \(.applicationName)",
                "Qu'est-ce qu'on mange ce soir avec \(.applicationName)",
            ],
            shortTitle: "Menu du jour",
            systemImageName: "calendar"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .navy
}
