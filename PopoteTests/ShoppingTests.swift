import Foundation
import Testing
@testable import Popote

struct ShoppingTests {
    typealias B = ShoppingListBuilder

    private let r1 = UUID()
    private let r2 = UUID()
    private let farine = UUID()

    private func row(_ name: String, _ q: Double?, _ unit: String?, recipe: UUID? = nil, servings: Int? = 4,
                     meal: Int? = 4, ingredient: UUID? = nil) -> B.MenuRow {
        B.MenuRow(recipeId: recipe ?? r1, recipeServings: servings, mealServings: meal, name: name,
                  quantity: q, unit: unit, ingredientId: ingredient)
    }

    private func item(_ name: String, key: String?, source: String, checked: Bool = false, inStock: Bool = false,
                      quantity: Double? = nil, unit: String? = nil) -> ShoppingListItem {
        ShoppingListItem(id: UUID(), weekStart: "2026-11-09", name: name, quantity: quantity, unit: unit,
                         ingredientId: nil, itemKey: key, source: source, sourceRecipeIds: [],
                         checked: checked, checkedAt: checked ? .now : nil, checkedBy: nil, inStock: inStock, createdAt: nil)
    }

    // MARK: Normalisation

    @Test func normalisation() {
        #expect(B.norm("Tomates") == "tomate")
        #expect(B.norm("chevaux") == "cheval")
        #expect(B.norm("Œufs") == "oeuf")
        #expect(B.norm("crème") == "creme")
        #expect(B.norm("riz") == "riz")
        #expect(B.norm("os") == "os")
        #expect(B.key("Pommes de terre") == "pomme de terre")
        #expect(B.key("  pomme-de-terre ") == "pomme de terre")
        #expect(B.matches("pom ter", "Pommes de terre"))
        #expect(!B.matches("carotte", "Pommes de terre"))
        #expect(B.matches("", "anything"))
    }

    // MARK: Staples

    @Test func staplesAreSkipped() {
        for s in ["Sel", "sel fin", "Poivre noir", "eau tiède", "Eau tiede", "sel et poivre", "huile d'olive", "Huile", "vinaigre balsamique"] {
            #expect(B.isStaple(s), "\(s)")
        }
        for s in ["selle d'agneau", "poivron", "eau de fleur d'oranger", "farine"] {
            #expect(!B.isStaple(s), "\(s)")
        }
        let out = B.aggregate([row("sel", 1, "pincée"), row("huile d'olive", 2, "c. à soupe"), row("farine", 200, "g")])
        #expect(out.map(\.name) == ["farine"])
    }

    // MARK: Units and rounding

    @Test func unitFamilies() {
        #expect(B.unitFamily("kg").family == .mass && B.unitFamily("kg").factor == 1000)
        #expect(B.unitFamily("g").family == .mass && B.unitFamily("g").factor == 1)
        #expect(B.unitFamily("cl").family == .volume && B.unitFamily("cl").factor == 10)
        #expect(B.unitFamily("L").family == .volume && B.unitFamily("l").factor == 1000)
        #expect(B.unitFamily(nil).family == .other("pièce"))
        #expect(B.unitFamily("").family == .other("pièce"))
        #expect(B.unitFamily("gousse").family == .other("gousse"))
    }

    @Test func rounding() {
        // Mass
        #expect(B.round(1250, family: .mass) == (1.3, "kg"))
        #expect(B.round(1000, family: .mass) == (1, "kg"))
        #expect(B.round(333, family: .mass) == (350, "g"))
        #expect(B.round(260, family: .mass) == (250, "g"))
        #expect(B.round(123, family: .mass) == (120, "g"))
        #expect(B.round(12, family: .mass) == (10, "g"))
        #expect(B.round(1, family: .mass) == (5, "g"))
        // Volume
        #expect(B.round(1500, family: .volume) == (1.5, "l"))
        #expect(B.round(330, family: .volume) == (35, "cl"))
        #expect(B.round(250, family: .volume) == (25, "cl"))
        #expect(B.round(42, family: .volume) == (40, "ml"))
        #expect(B.round(2, family: .volume) == (5, "ml"))
        // Spoons: ceil to ½, min ½
        #expect(B.round(1.2, family: .other("c. à soupe")) == (1.5, "c. à soupe"))
        #expect(B.round(0.1, family: .other("c. à café")) == (0.5, "c. à café"))
        #expect(B.round(2, family: .other("c. à soupe")) == (2, "c. à soupe"))
        // Countable: ceil(x − 0.05), min 1
        #expect(B.round(2.04, family: .other("gousse")) == (2, "gousse"))
        #expect(B.round(2.2, family: .other("gousse")) == (3, "gousse"))
        #expect(B.round(0.3, family: .other("pièce")) == (1, "pièce"))
        // Other: ceil to 0.1
        #expect(B.round(1.23, family: .other("boîte")) == (1.3, "boîte"))
        #expect(B.round(0.3, family: .other("boîte")) == (0.3, "boîte"))
    }

    // MARK: Aggregation

    @Test func aggregatesAcrossRecipesAndUnits() {
        let rows = [
            row("Farine", 500, "g", ingredient: farine),
            row("farine T55", 1, "kg", recipe: r2, ingredient: farine),
            row("Lait", 25, "cl"),
            row("lait", 500, "ml", recipe: r2),
            row("Oeufs", 2, nil),
            row("œuf", 3, "pièce", recipe: r2),
        ]
        let out = B.aggregate(rows)
        #expect(out.count == 3)
        let f = out[0]
        #expect(f.key == "\(B.idString(farine))|mass")
        #expect(f.name == "Farine")
        #expect(f.quantity == 1.5 && f.unit == "kg")
        #expect(Set(f.sourceRecipeIds) == [r1, r2])
        let lait = out[1]
        #expect(lait.key == "lait|vol")
        #expect(lait.quantity == 75 && lait.unit == "cl")
        let oeufs = out[2]
        #expect(oeufs.key == "oeuf|pièce")
        #expect(oeufs.quantity == 5 && oeufs.unit == "pièce")
    }

    @Test func scalesByMenuServings() {
        // A recipe for 4 cooked for 6 → ×1.5; a recipe with no servings falls back to the default.
        let out = B.aggregate([row("beurre", 100, "g", servings: 4, meal: 6)])
        #expect(out.first?.quantity == 150)
        let fallback = B.aggregate([row("beurre", 100, "g", servings: nil, meal: 4)], defaultServings: 2)
        #expect(fallback.first?.quantity == 200)
        let zero = B.aggregate([row("beurre", 100, "g", servings: 0, meal: 8)], defaultServings: 0)
        #expect(zero.first?.quantity == 200)
    }

    @Test func quantityLessItemsGetTheirOwnKey() {
        let out = B.aggregate([row("persil", nil, nil), row("persil", 1, "botte"), row("Persil", nil, "botte", recipe: r2)])
        #expect(out.count == 2)
        #expect(out[0].key == "persil|-")
        #expect(out[0].quantity == nil && out[0].unit == nil)
        #expect(out[0].sourceRecipeIds == [r1, r2])
        #expect(out[1].key == "persil|botte" && out[1].quantity == 1)
    }

    @Test func differentFamiliesStaySeparate() {
        let out = B.aggregate([row("sucre", 100, "g"), row("sucre", 2, "c. à soupe")])
        #expect(out.map(\.key) == ["sucre|mass", "sucre|c. à soupe"])
    }

    @Test func menuRowsSkipFreeDishesAndOutOfRangeDays() {
        let ri = RecipeIngredient(id: UUID(), recipeId: r1, position: 0, rawText: nil, name: "riz", quantity: 200, unit: "g",
                                  shoppingCategory: nil, optional: nil, ingredientId: nil)
        let entries = [
            MealPlanEntry(id: UUID(), date: "2026-11-09", mealType: .diner, recipeId: r1, customTitle: nil, servings: 2, position: 0),
            MealPlanEntry(id: UUID(), date: "2026-11-10", mealType: .dejeuner, recipeId: nil, customTitle: "Restes", servings: 2, position: 0),
            MealPlanEntry(id: UUID(), date: "2026-11-20", mealType: .diner, recipeId: r1, customTitle: nil, servings: 2, position: 0),
        ]
        let rows = B.menuRows(entries: entries, from: "2026-11-09", to: "2026-11-15",
                              recipeServings: [r1: 4], ingredientsByRecipe: [r1: [ri]])
        #expect(rows.count == 1)
        #expect(rows[0].mealServings == 2 && rows[0].recipeServings == 4)
        #expect(B.aggregate(rows).first?.quantity == 100)
    }

    // MARK: Regeneration

    @Test func regenerationKeepsManualAndCheckedState() {
        let manual = item("Papier toilette", key: nil, source: "manuel")
        let keptAuto = item("farine", key: "farine|mass", source: "auto", checked: true, inStock: true, quantity: 100, unit: "g")
        let staleAuto = item("navet", key: "navet|pièce", source: "auto")
        let computed = [
            B.AggregatedItem(key: "farine|mass", name: "farine", quantity: 300, unit: "g", ingredientId: farine, sourceRecipeIds: [r1]),
            B.AggregatedItem(key: "lait|vol", name: "lait", quantity: 50, unit: "cl", ingredientId: nil, sourceRecipeIds: [r2]),
        ]
        let plan = B.plan(existing: [manual, keptAuto, staleAuto], computed: computed, weekStart: "2026-11-09",
                          displayName: { $0 == farine ? "Farine de blé" : nil })
        #expect(plan.deletes == [staleAuto.id])
        #expect(plan.updates.count == 1)
        let updated = plan.updates[0]
        #expect(updated.id == keptAuto.id)
        #expect(updated.quantity == 300 && updated.name == "Farine de blé")
        #expect(updated.checked && updated.inStock == true)
        #expect(updated.ingredientId == farine)
        #expect(plan.inserts.count == 1)
        let inserted = plan.inserts[0]
        #expect(inserted.itemKey == "lait|vol" && inserted.source == "auto" && inserted.weekStart == "2026-11-09")
        #expect(!inserted.checked && inserted.sourceRecipeIds == [r2])
        #expect(!plan.deletes.contains(manual.id) && !plan.updates.contains { $0.id == manual.id })
    }

    @Test func duplicateAutoKeysAreCleanedUp() {
        let a = item("farine", key: "farine|mass", source: "auto")
        let b = item("farine", key: "farine|mass", source: "auto")
        let legacy = item("x", key: nil, source: "auto")
        let plan = B.plan(existing: [a, b, legacy], computed: [
            B.AggregatedItem(key: "farine|mass", name: "farine", quantity: 1, unit: "kg", ingredientId: nil, sourceRecipeIds: []),
        ], weekStart: "2026-11-09")
        #expect(plan.updates.map(\.id) == [a.id])
        #expect(Set(plan.deletes) == [b.id, legacy.id])
        #expect(plan.inserts.isEmpty)
    }

    // MARK: Quick add parsing

    @Test func parsesFreeText() {
        #expect(B.parseQuick("2 kg pommes") == .init(name: "pommes", quantity: 2, unit: "kg"))
        #expect(B.parseQuick("200 g de farine") == .init(name: "farine", quantity: 200, unit: "g"))
        #expect(B.parseQuick("200g farine") == .init(name: "farine", quantity: 200, unit: "g"))
        #expect(B.parseQuick("1,5 l d'eau gazeuse") == .init(name: "eau gazeuse", quantity: 1.5, unit: "l"))
        #expect(B.parseQuick("2 c. à soupe de miel") == .init(name: "miel", quantity: 2, unit: "c. à soupe"))
        #expect(B.parseQuick("3 oeufs") == .init(name: "oeufs", quantity: 3, unit: nil))
        #expect(B.parseQuick("2 gousses d’ail") == .init(name: "gousses d’ail", quantity: 2, unit: nil))
        #expect(B.parseQuick("1 gousse d’ail") == .init(name: "ail", quantity: 1, unit: "gousse"))
        #expect(B.parseQuick("  persil ") == .init(name: "persil", quantity: nil, unit: nil))
        #expect(B.parseQuick("12") == .init(name: "12", quantity: nil, unit: nil))
        // "l" must be followed by a space to count as the unit.
        #expect(B.parseQuick("1 litre de lait") == .init(name: "litre de lait", quantity: 1, unit: nil))
    }

    // MARK: Ingredient matching

    @Test func matchesIngredientsByNameAndAliases() {
        let pdt = Ingredient(id: UUID(), name: "pomme de terre", displayName: "Pommes de terre", pluralName: nil,
                             aliases: ["patate"], categoryId: nil, seasons: nil, verified: true, source: nil, pendingAi: nil)
        let pomme = Ingredient(id: UUID(), name: "pomme", displayName: "Pomme", pluralName: nil, aliases: nil,
                               categoryId: nil, seasons: nil, verified: true, source: nil, pendingAi: nil)
        let list = [pomme, pdt]
        #expect(B.exactIngredient(named: "Patates", in: list)?.id == pdt.id)
        #expect(B.exactIngredient(named: "pommes", in: list)?.id == pomme.id)
        #expect(B.exactIngredient(named: "poire", in: list) == nil)
        let found = B.searchIngredients(list, query: "pom")
        #expect(found.map(\.id) == [pomme.id, pdt.id])
        let byFrequency = B.searchIngredients(list, query: "pom", frequency: [pdt.id: 3])
        #expect(byFrequency.first?.id == pdt.id)
        #expect(B.searchIngredients(list, query: "terre").map(\.id) == [pdt.id])
    }

    // MARK: Grouping and sharing

    @Test func groupsByAisleWithOtherLast() {
        let fruits = "fruits", cremerie = "cremerie", autre = "autre"
        let aisles = [(id: cremerie, name: "Crèmerie"), (id: autre, name: "Autre"), (id: fruits, name: "Fruits & légumes")]
        var pommes = item("pommes", key: nil, source: "manuel"); pommes.ingredientId = UUID()
        var lait = item("lait", key: nil, source: "manuel"); lait.ingredientId = UUID()
        let mystery = item("truc", key: nil, source: "manuel")
        let map: [UUID: String] = [pommes.ingredientId!: fruits, lait.ingredientId!: cremerie]
        let sections = B.group([pommes, mystery, lait], aisles: aisles, otherName: "Autre") { $0.ingredientId.flatMap { map[$0] } }
        #expect(sections.map(\.name) == ["Crèmerie", "Fruits & légumes", "Autre"])
        #expect(sections.last?.id == autre)
        #expect(sections.last?.items.map(\.name) == ["truc"])

        var farine = item("farine", key: nil, source: "auto", quantity: 200, unit: "g")
        farine.ingredientId = nil
        let text = B.shareText(title: "Courses du 9 nov. au 15 nov.", sections: [
            .init(id: cremerie, name: "Crèmerie", items: [lait]),
            .init(id: nil, name: "Autre", items: [farine]),
        ])
        #expect(text == "🛒 Courses du 9 nov. au 15 nov.\n\nCRÈMERIE\n• lait\n\nAUTRE\n• farine — 200 g")
    }
}
