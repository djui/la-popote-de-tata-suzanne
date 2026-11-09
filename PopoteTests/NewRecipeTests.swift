import CoreGraphics
import Foundation
import Testing
@testable import Popote

struct TitleSimilarityTests {
    @Test func identicalAfterNormalisation() {
        #expect(TitleSimilarity.similarity("Gratin dauphinois", "gratin dauphinois") == 1)
        #expect(TitleSimilarity.similarity("Crêpes de la Chandeleur", "crepe de la chandeleur") == 1)
        #expect(TitleSimilarity.similarity("Gâteau au chocolat", "gateaux au chocolat") < 1) // SPEC norm: "gateaux" → "gateal"
        #expect(TitleSimilarity.similarity("Gâteau au Chocolat", "gateau au chocolat") == 1)
    }

    @Test func emptyOrShortTokens() {
        #expect(TitleSimilarity.similarity("", "Tarte") == 0)
        #expect(TitleSimilarity.similarity("de la", "au") == 0)
    }

    @Test func nearDuplicatesPassThreshold() {
        let s = TitleSimilarity.similarity("Gratin dauphinois de mamie", "Gratin dauphinois")
        #expect(s >= TitleSimilarity.duplicateThreshold)
        #expect(TitleSimilarity.similarity("Quiche lorraine", "Quiches lorraines") == 1)
    }

    @Test func differentRecipesStayBelow() {
        #expect(TitleSimilarity.similarity("Gratin dauphinois", "Tarte aux pommes") < 0.75)
        #expect(TitleSimilarity.similarity("Soupe de potiron", "Soupe de poireaux") < 0.75)
    }

    @Test func norm() {
        #expect(TitleSimilarity.norm("Chevaux") == "cheval")
        #expect(TitleSimilarity.norm("Œufs") == "oeuf")
        #expect(TitleSimilarity.norm("riz") == "riz")
        #expect(TitleSimilarity.tokens("Pâtes à l'ail!") == ["pate", "a", "l", "ail"])
    }
}

struct URLSafetyTests {
    @Test func acceptsPublicSites() {
        #expect(URLSafety.isSafe("https://www.marmiton.org/recettes/recette_gratin.aspx"))
        #expect(URLSafety.isSafe("http://cuisine.example.fr/a?b=c"))
        #expect(URLSafety.isSafe("https://8.8.8.8/x"))
    }

    @Test func rejectsSchemesAndUserinfo() {
        #expect(!URLSafety.isSafe("ftp://example.com/file"))
        #expect(!URLSafety.isSafe("javascript:alert(1)"))
        #expect(!URLSafety.isSafe("https://user:pass@example.com/"))
        #expect(!URLSafety.isSafe("not a url"))
    }

    @Test func rejectsLocalHosts() {
        for s in ["http://localhost:3000", "http://app.localhost", "http://printer.local", "http://db.internal", "http://intranet"] {
            #expect(!URLSafety.isSafe(s), "\(s)")
        }
    }

    @Test func rejectsPrivateIPv4() {
        for s in ["http://10.0.0.1", "http://127.0.0.1", "http://0.0.0.0", "http://224.0.0.1", "http://169.254.169.254/latest",
                  "http://172.16.0.1", "http://172.31.255.255", "http://192.168.1.1", "http://100.64.0.1", "http://100.127.0.1"] {
            #expect(!URLSafety.isSafe(s), "\(s)")
        }
        #expect(URLSafety.isSafe("http://172.32.0.1"))
        #expect(URLSafety.isSafe("http://100.128.0.1"))
    }

    @Test func rejectsPrivateIPv6() {
        for s in ["http://[::1]/", "http://[::]/", "http://[fc00::1]/", "http://[fd12::1]/", "http://[fe80::1]/", "http://[::ffff:127.0.0.1]/"] {
            #expect(!URLSafety.isSafe(s), "\(s)")
        }
        #expect(URLSafety.isSafe("http://[2001:4860:4860::8888]/"))
    }

    @Test func singleURLDetection() {
        #expect(URLSafety.singleURL(in: "https://example.com/recette") == "https://example.com/recette")
        #expect(URLSafety.singleURL(in: "Regarde ça : https://example.com/recette !") == "https://example.com/recette")
        let long = "Voici la recette de ma grand-mère, avec 200 g de farine et trois œufs https://example.com/x"
        #expect(URLSafety.singleURL(in: long) == nil)
        #expect(URLSafety.singleURL(in: "https://a.com https://b.com") == nil)
    }
}

struct AiMappingTests {
    nonisolated(unsafe) static let json: [String: Any] = [
        "title": "Gratin dauphinois",
        "servings": 6,
        "prep_time_min": 20,
        "cook_time_min": 60.0,
        "ingredients": [
            ["raw_text": "1 kg de pommes de terre", "name": "pommes de terre", "quantity": 1, "unit": "kg", "shopping_category": "fruits & légumes"],
            ["raw_text": "50 cl de crème", "name": "crème", "quantity": 50, "unit": "cl", "shopping_category": "crèmerie"],
            ["raw_text": "Sel", "name": "sel", "quantity": NSNull(), "unit": NSNull(), "shopping_category": "épicerie"],
            ["raw_text": "", "name": "", "quantity": NSNull(), "unit": NSNull(), "shopping_category": "autre"],
        ] as [Any],
        "steps": ["Éplucher les pommes de terre.", "  ", "Cuire 1 h à 180 °C."],
        "suggested_seasons": ["hiver", "automne"],
        "suggested_tags": ["gratin", "végétarien", "gratin"],
        "suggested_categories": ["légumes", "plat"],
        "dish_photos": [
            ["image_index": 0, "box_2d": [100, 200, 500, 800], "is_main": false, "confidence": 0.4],
            ["image_index": 1, "box_2d": [0, 0, 1000, 1000], "is_main": false, "confidence": 0.9],
        ] as [Any],
    ]

    @Test func parsesAiRecipe() throws {
        let ai = try #require(AiRecipe(json: Self.json))
        #expect(ai.title == "Gratin dauphinois")
        #expect(ai.servings == 6)
        #expect(ai.cookTimeMin == 60)
        #expect(ai.ingredients.count == 3)
        #expect(ai.steps.count == 2)
        #expect(ai.dishPhotos.count == 2)
        #expect(AiDetection.main(ai.dishPhotos)?.imageIndex == 1)
    }

    @Test func mergesIntoDraft() throws {
        let ai = try #require(AiRecipe(json: Self.json))
        let d = RecipeDraft.blank(category: .gateau).merging(ai, chosen: .gateau)
        #expect(d.title == "Gratin dauphinois")
        #expect(d.servings == 6)
        #expect(d.prepTimeMin == 20)
        #expect(d.categories == [.plat, .legumes, .gateau])
        #expect(d.seasons == [.automne, .hiver])
        #expect(d.tags == ["gratin", "végétarien"])
        #expect(d.ingredients.map(\.name) == ["pommes de terre", "crème", "sel"])
        #expect(d.ingredients[0].quantity == 1)
        #expect(d.ingredients[0].unit == "kg")
        #expect(d.ingredients[1].shoppingCategory == "crèmerie")
        #expect(d.ingredients.allSatisfy { !$0.optional })
        #expect(d.steps.map(\.instruction) == ["Éplucher les pommes de terre.", "Cuire 1 h à 180 °C."])
        #expect(!d.hasKeyGaps)
    }

    @Test func missingValuesAreHighlighted() throws {
        let ai = try #require(AiRecipe(json: ["title": NSNull(), "servings": NSNull(), "ingredients": [["raw_text": "2 oeufs", "name": "oeufs", "quantity": NSNull()]], "steps": []] as [String: Any]))
        let d = RecipeDraft.blank().merging(ai)
        #expect(d.titleMissing)
        #expect(d.servings == 4) // the blank keeps its default
        #expect(d.ingredients[0].quantityMissing)
        #expect(d.hasKeyGaps)
    }

    @Test func mainDetectionPrefersIsMain() {
        let list = [AiDetection(imageIndex: 0, box: [0, 0, 1, 1], isMain: false, confidence: 0.99),
                    AiDetection(imageIndex: 2, box: [0, 0, 1, 1], isMain: true, confidence: 0.1)]
        #expect(AiDetection.main(list)?.imageIndex == 2)
        #expect(AiDetection.main([]) == nil)
    }

    @Test func unknownUnitIsAppended() {
        var ing = DraftIngredient(name: "lait", unit: "tasse")
        #expect(ing.unitOptions.last == "tasse")
        ing.unit = "g"
        #expect(ing.unitOptions == IngredientUnit.all)
    }

    @Test func quickParser() throws {
        let a = try #require(IngredientLineParser.parse("- 200 g de farine"))
        #expect(a.quantity == 200 && a.unit == "g" && a.name == "farine")
        let b = try #require(IngredientLineParser.parse("2 c. à soupe d'huile d'olive"))
        #expect(b.quantity == 2 && b.unit == "c. à soupe" && b.name == "huile d'olive")
        let c = try #require(IngredientLineParser.parse("1,5 l lait"))
        #expect(c.quantity == 1.5 && c.unit == "l" && c.name == "lait")
        let d = try #require(IngredientLineParser.parse("Sel, poivre"))
        #expect(d.quantity == nil && d.name == "Sel, poivre")
    }

    @Test func numberAndTagParsing() {
        #expect(RecipeDraft.parseNumber("1,5") == 1.5)
        #expect(RecipeDraft.parseNumber("  ") == nil)
        #expect(RecipeDraft.parseTags(" rapide, ,végétarien ,") == ["rapide", "végétarien"])
    }
}

struct CropMathTests {
    @Test func boxToPixelsWithPadding() throws {
        let r = try #require(ImagePipeline.cropRect(box: [100, 200, 500, 800], imageSize: CGSize(width: 1000, height: 2000)))
        // x: (0.2-0.02)*1000 … (0.8+0.02)*1000 ; y: (0.1-0.02)*2000 … (0.5+0.02)*2000
        #expect(r == CGRect(x: 180, y: 160, width: 640, height: 880))
    }

    @Test func clampsToImage() throws {
        let r = try #require(ImagePipeline.cropRect(box: [0, 0, 1000, 1000], imageSize: CGSize(width: 400, height: 300)))
        #expect(r == CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    @Test func unpaddedAndSwappedCoordinates() throws {
        let r = try #require(ImagePipeline.cropRect(box: [500, 800, 100, 200], imageSize: CGSize(width: 1000, height: 1000), padding: 0))
        #expect(r == CGRect(x: 200, y: 100, width: 600, height: 400))
    }

    @Test func invalidBoxes() {
        #expect(ImagePipeline.cropRect(box: [1, 2, 3], imageSize: CGSize(width: 100, height: 100)) == nil)
        #expect(ImagePipeline.cropRect(box: [0, 0, 0, 0], imageSize: CGSize(width: 100, height: 100), padding: 0) == nil)
        #expect(ImagePipeline.cropRect(box: [0, 0, 10, 10], imageSize: .zero) == nil)
    }

    @Test func fittedSize() {
        #expect(ImagePipeline.fittedSize(CGSize(width: 4000, height: 3000), maxPixel: 1600) == CGSize(width: 1600, height: 1200))
        #expect(ImagePipeline.fittedSize(CGSize(width: 800, height: 600), maxPixel: 1600) == CGSize(width: 800, height: 600))
        #expect(ImagePipeline.fittedSize(CGSize(width: 1000, height: 3000), maxPixel: 400) == CGSize(width: 133, height: 400))
    }

    @Test func cropperFullImageAtZoomOne() {
        let g = CropGeometry(imageSize: CGSize(width: 2000, height: 1000), frameSize: CGSize(width: 300, height: 300))
        // Covers the frame by height: scale 0.3, displayed 600×300, centred.
        #expect(abs(g.baseScale - 0.3) < 1e-9)
        let r = g.cropRect
        #expect(abs(r.minX - 500) < 1e-6 && abs(r.width - 1000) < 1e-6 && abs(r.height - 1000) < 1e-6)
    }

    @Test func cropperOffsetIsClamped() {
        var g = CropGeometry(imageSize: CGSize(width: 2000, height: 1000), frameSize: CGSize(width: 300, height: 300))
        g.offset = CGSize(width: 10_000, height: 50)
        #expect(g.clamped(g.offset) == CGSize(width: 150, height: 0))
        #expect(abs(g.cropRect.minX) < 1e-6)
    }

    @Test func cropperFocusesOnBox() {
        var g = CropGeometry(imageSize: CGSize(width: 2000, height: 2000), frameSize: CGSize(width: 400, height: 400))
        let box = CGRect(x: 1000, y: 1000, width: 800, height: 800)
        g.focus(on: box)
        #expect(abs(g.zoom - 2.5) < 1e-9)
        let r = g.cropRect
        #expect(abs(r.minX - 1000) < 1e-6 && abs(r.minY - 1000) < 1e-6 && abs(r.width - 800) < 1e-6)
    }
}
