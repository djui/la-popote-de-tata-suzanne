import Testing
@testable import Popote

struct QuantityTests {
    @Test func fractions() {
        #expect(Quantity.format(0.5) == "½")
        #expect(Quantity.format(1.5) == "1½")
        #expect(Quantity.format(0.333) == "⅓")
        #expect(Quantity.format(2.5) == "2½")
        #expect(Quantity.format(12.5) == "12,5")
        #expect(Quantity.format(150.4) == "150")
        #expect(Quantity.format(3) == "3")
        #expect(Quantity.format(nil) == "")
    }

    @Test func scaling() {
        #expect(Quantity.scale(100, base: 4, target: 6) == 150)
        #expect(Quantity.scale(100, base: nil, target: 6) == 100)
        #expect(Quantity.scale(nil, base: 4, target: 6) == nil)
    }

    @Test func ingredientLines() {
        #expect(Quantity.formatIngredient(2, unit: "gousse", name: "ail") == ("2 gousses", "ail"))
        #expect(Quantity.formatIngredient(2, unit: nil, name: "oignon rouge") == ("2", "oignons rouges"))
        #expect(Quantity.formatIngredient(3, unit: "pièce", name: "pomme de terre") == ("3", "pommes de terre"))
        #expect(Quantity.formatIngredient(2, unit: nil, name: "beurre") == ("2", "beurre"))
        #expect(Quantity.formatIngredient(100, unit: "g", name: "farine") == ("100 g", "farine"))
        #expect(Quantity.pluralizeWord("chou") == "choux")
        #expect(Quantity.pluralizeWord("poireau") == "poireaux")
        #expect(Quantity.pluralizeWord("bocal") == "bocaux")
    }

    @Test func serovalRoundTrip() throws {
        var counter = 0
        let node = Seroval.node(["ids": ["a", "b"], "n": 2, "b": true, "x": nil, "s": "a\"b<c\n"] as [String: Any?], &counter)
        let decoded = try Seroval.decode(node) as? [String: Any]
        #expect(decoded?["n"] as? Int == 2)
        #expect(decoded?["b"] as? Bool == true)
        #expect(decoded?["s"] as? String == "a\"b<c\n")
        #expect((decoded?["ids"] as? [Any])?.count == 2)
    }
}
