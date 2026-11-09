import Foundation
import Testing
@testable import Popote

struct InvitationLinkTests {
    @Test func buildsWebsiteLink() {
        #expect(InvitationLink.url(code: "ab12CD").absoluteString == "https://la-popote-de-tata-suzanne.lovable.app/invitation/ab12CD")
    }

    @Test func parsesLinksAndCodes() {
        #expect(InvitationLink.code(from: "https://la-popote-de-tata-suzanne.lovable.app/invitation/ab12CD") == "ab12CD")
        #expect(InvitationLink.code(from: "https://la-popote-de-tata-suzanne.lovable.app/invitation/ab12CD?utm=x#top") == "ab12CD")
        #expect(InvitationLink.code(from: "popote://invitation/xyz-9_8") == "xyz-9_8")
        #expect(InvitationLink.code(from: "  ab12CD \n") == "ab12CD")
        #expect(InvitationLink.code(from: "https://la-popote-de-tata-suzanne.lovable.app/recettes/123") == nil)
        #expect(InvitationLink.code(from: "https://la-popote-de-tata-suzanne.lovable.app/invitation/") == nil)
        #expect(InvitationLink.code(from: "") == nil)
        #expect(InvitationLink.code(from: "pas un code !") == nil)
    }

    @Test func roundTrip() {
        let url = InvitationLink.url(code: "Q7w2")
        #expect(InvitationLink.code(from: url.absoluteString) == "Q7w2")
    }

    @Test func initials() {
        #expect(InvitationLink.initials("marion") == "MA")
        #expect(InvitationLink.initials(nil) == "?")
        #expect(InvitationLink.initials("  ") == "?")
    }
}

struct WidgetSelectionTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func meal(_ date: String, _ type: String, _ title: String) -> WidgetSnapshot.Meal {
        .init(date: date, mealType: type, title: title, recipeId: nil, servings: 4)
    }

    var snapshot: WidgetSnapshot {
        WidgetSnapshot(meals: [
            meal("2026-11-10", WidgetSnapshot.dinner, "Soupe"),
            meal("2026-11-10", WidgetSnapshot.lunch, "Quiche"),
            meal("2026-11-11", WidgetSnapshot.lunch, "Salade"),
            meal("2026-11-13", WidgetSnapshot.dinner, "Curry"),
        ], updatedAt: .now)
    }

    @Test func lunchBefore15() throws {
        let s = try #require(snapshot.selection(at: date(10, 9), calendar: calendar))
        #expect(s.meal.title == "Quiche")
        #expect(s.label == "CE MIDI")
        #expect(s.next?.title == "Soupe")
        #expect(s.nextLabel == "CE SOIR")
    }

    @Test func dinnerFrom15() throws {
        let s = try #require(snapshot.selection(at: date(10, 15, 1), calendar: calendar))
        #expect(s.meal.title == "Soupe")
        #expect(s.label == "CE SOIR")
        #expect(s.next?.title == "Salade")
        #expect(s.nextLabel == "DEMAIN MIDI")
    }

    @Test func skipsToNextPlannedMeal() throws {
        let s = try #require(snapshot.selection(at: date(11, 16), calendar: calendar))
        #expect(s.meal.title == "Curry")
        #expect(s.next == nil)
        #expect(s.label.hasSuffix("SOIR"))
        #expect(s.label != "CE SOIR" && s.label != "DEMAIN SOIR")
    }

    @Test func nothingLeft() {
        #expect(snapshot.selection(at: date(14, 8), calendar: calendar) == nil)
    }

    @Test func extraDishesInSameSlot() throws {
        var snap = snapshot
        snap.meals.append(meal("2026-11-10", WidgetSnapshot.lunch, "Tarte"))
        let s = try #require(snap.selection(at: date(10, 12), calendar: calendar))
        #expect(s.meal.title == "Quiche")
        #expect(s.extraCount == 1)
        #expect(s.next?.title == "Soupe")
    }

    @Test func boundaries() {
        #expect(WidgetSnapshot.nextBoundary(after: date(10, 8), calendar: calendar) == date(10, 11))
        #expect(WidgetSnapshot.nextBoundary(after: date(10, 11), calendar: calendar) == date(10, 15))
        #expect(WidgetSnapshot.nextBoundary(after: date(10, 15, 30), calendar: calendar) == date(11, 0))
    }

    @Test func deepLinks() {
        let id = UUID()
        var m = meal("2026-11-10", WidgetSnapshot.lunch, "Quiche")
        #expect(WidgetSnapshot.url(for: m).absoluteString == "popote://menu")
        m.recipeId = id
        #expect(WidgetSnapshot.url(for: m).absoluteString == "popote://recette/\(id.uuidString)")
    }

    @Test func bridgeBuildsMealsFromPlan() {
        let recipe = Recipe(id: UUID(), title: "Gratin", photoThumbUrl: "u/plats/a.webp")
        let today = date(10, 9)
        let plan = [
            MealPlanEntry(id: UUID(), date: "2026-11-10", mealType: .diner, recipeId: recipe.id, servings: 6, position: 0),
            MealPlanEntry(id: UUID(), date: "2026-11-10", mealType: .dejeuner, customTitle: "Restes", position: 0),
            MealPlanEntry(id: UUID(), date: "2026-11-09", mealType: .diner, customTitle: "Hier", position: 0),
            MealPlanEntry(id: UUID(), date: "2026-11-11", mealType: .dejeuner, customTitle: "  ", position: 0),
            MealPlanEntry(id: UUID(), date: "2026-11-30", mealType: .dejeuner, customTitle: "Trop loin", position: 0),
        ]
        let meals = WidgetBridge.meals(from: plan, recipes: [recipe.id: recipe], today: today, calendar: calendar)
        #expect(meals.map(\.0.title) == ["Restes", "Gratin"])
        #expect(meals[1].0.recipeId == recipe.id)
        #expect(meals[1].0.servings == 6)
        #expect(meals[1].1 == "u/plats/a.webp")
        #expect(meals[0].1 == nil)
    }
}

struct SnapshotEncodingTests {
    @Test func widgetSnapshotRoundTrip() throws {
        let snap = WidgetSnapshot(meals: [
            .init(date: "2026-11-10", mealType: "dîner", title: "Pot-au-feu", recipeId: UUID(), servings: 4, thumbnailFile: "thumb-x.jpg"),
        ], updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let back = try d.decode(WidgetSnapshot.self, from: e.encode(snap))
        #expect(back.meals == snap.meals)
        #expect(back.updatedAt == snap.updatedAt)
    }

    @Test func intentsReadAppSnapshot() throws {
        let recipe = Recipe(id: UUID(), title: "Crème brûlée", categories: ["dessert"])
        let data = try JSONEncoder.popote.encode(Snapshot(recipes: [recipe]))
        let recipes = RecipeLibrary.decode(data)
        #expect(recipes.map(\.id) == [recipe.id])
        #expect(RecipeLibrary.search("creme", in: recipes).count == 1)
        #expect(RecipeLibrary.search("DESSERT", in: recipes).count == 1)
        #expect(RecipeLibrary.search("gratin", in: recipes).isEmpty)
        #expect(RecipeLibrary.decode(Data("nope".utf8)).isEmpty)
    }

    @Test func termsParsing() {
        let doc = TermsDocument.parse(LegalTexts.termsFR)
        #expect(doc.title == "Conditions générales d'utilisation")
        #expect(doc.articles.count == 15)
        #expect(doc.articles.first?.title == "1. Objet")
        #expect(doc.articles[1].blocks.contains { if case .bullets(let b) = $0 { b.count == 3 } else { false } })
        #expect(TermsDocument.parse(LegalTexts.termsEN).articles.count == 15)
    }
}
