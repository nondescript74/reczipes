//
//  DuplicateDetectionRulesTests.swift
//  Reczipes2Tests
//
//  Regression tests for the duplicate-detection rule set, using real cases
//  from the Oct 2026 Shahsultan Premji recipe book dedupe.
//

import Testing
import Foundation
@testable import Reczipes2

@Suite("Duplicate Detection Rules")
struct DuplicateDetectionRulesTests {

    // MARK: - Helpers

    @MainActor
    private func recipe(_ title: String,
                        _ ingredients: [(String?, String)],
                        steps: Int = 3,
                        reference: String? = nil,
                        added: Date = Date()) throws -> RecipeX {
        let section = IngredientSection(ingredients: ingredients.map {
            Ingredient(quantity: $0.0, name: $0.1)
        })
        let instructions = InstructionSection(steps: (1...max(steps, 1)).map {
            InstructionStep(stepNumber: $0, text: "Step \($0)")
        })
        let encoder = JSONEncoder()
        return RecipeX(
            title: title,
            reference: reference,
            ingredientSectionsData: try encoder.encode([section]),
            instructionSectionsData: try encoder.encode([instructions]),
            dateAdded: added
        )
    }

    // MARK: - Same title is not enough

    @Test("Same-title recipes with different ingredients are not duplicates (Dhokra 64 vs 96)")
    @MainActor
    func differentRecipesSameName() throws {
        let dhokra64 = try recipe("Dhokra", [
            ("1", "Channa Dal"), ("1", "Mung Dal"), ("1", "Rice"), (nil, "buttermilk"),
            ("2", "oil"), (nil, "green chillies"), (nil, "cilantro"), (nil, "garlic"),
            (nil, "ginger"), ("1", "fruit salt"), (nil, "salt")
        ])
        let dhokraSuji = try recipe("Dhokra", [
            ("2", "suji"), ("1", "gram flour"), ("2", "yogurt"), ("2", "butter milk"),
            (nil, "black pepper"), ("1/4", "soda"), ("1/2", "oil"), ("1", "mustard seeds"),
            (nil, "sesame seeds"), (nil, "curry leaves")
        ])
        let clusters = DuplicateRecipeDetectorView.buildDuplicateClusters(from: [dhokra64, dhokraSuji])
        #expect(clusters.isEmpty)
    }

    @Test("Re-extraction with misread quantities is a likely duplicate (Persian Chicken)")
    @MainActor
    func reExtractionWithOCRDifferences() throws {
        let names = ["whole chicken", "crushed garlic", "ginger", "coarsely ground black pepper",
                     "crushed hot pepper", "salt", "butter or margarine", "sliced onions",
                     "dried apricots", "blanched almonds", "small onions", "canned tomatoes",
                     "white vinegar", "brown sugar", "chili powder"]
        let a = try recipe("Persian Chicken", names.map { ("1", $0) })
        let b = try recipe("Persian Chicken", names.map { ("2", $0) })
        let clusters = DuplicateRecipeDetectorView.buildDuplicateClusters(from: [a, b])
        #expect(clusters.count == 1)
        #expect(clusters.first?.confidence == .likely)
        #expect(clusters.first?.isSafeToBulkDelete == false)
    }

    @Test("Single-ingredient recipes are never compared (Clarified Butter)")
    @MainActor
    func tooFewIngredients() throws {
        let a = try recipe("Clarified Butter", [("1", "butter")])
        let b = try recipe("Clarified Butter", [("3", "butter")])
        #expect(DuplicateRecipeDetectorView.buildDuplicateClusters(from: [a, b]).isEmpty)
    }

    // MARK: - Source URL rule

    @Test("Page numbers in the reference field are not URLs")
    @MainActor
    func pageNumbersAreNotURLs() throws {
        let harischo = try recipe("Harischo", [("1", "hulled wheat"), ("1", "oats"), ("2", "lamb")], reference: "75")
        let tandoori = try recipe("Chicken Tanduri", [("1", "tomato paste"), ("1", "ginger"), ("2", "chicken")], reference: "75")
        #expect(DuplicateRecipeDetectorView.buildDuplicateClusters(from: [harischo, tandoori]).isEmpty)
        // The unattended launch scan must not touch them either
        #expect(DuplicateRecipeDetectorView.buildDuplicateClusters(from: [harischo, tandoori], includeTitleMatches: false).isEmpty)
    }

    @Test("Same web link is an exact copy, safe to bulk delete")
    @MainActor
    func sameWebLink() throws {
        let link = "https://www.seriouseats.com/lomo-saltado"
        let a = try recipe("Lomo Saltado", [("1", "beef"), ("1", "onion"), ("2", "tomatoes")], reference: link)
        let b = try recipe("Lomo Saltado Recipe", [("1", "beef")], reference: link + "/")
        let clusters = DuplicateRecipeDetectorView.buildDuplicateClusters(from: [a, b], includeTitleMatches: false)
        #expect(clusters.count == 1)
        #expect(clusters.first?.confidence == .exactCopy)
        #expect(clusters.first?.isSafeToBulkDelete == true)
    }

    // MARK: - Keeper choice

    @Test("Keeper is the more complete copy, not just the oldest")
    @MainActor
    func keeperPrefersMoreComplete() throws {
        let names = ["mandarins", "onions", "garlic", "boneless chicken", "tomatoes",
                     "coriander powder", "cumin", "turmeric", "chili powder", "grated ginger"]
        let older = try recipe("Madras Curry", names.map { ("1", $0) }, steps: 5,
                               added: Date(timeIntervalSinceNow: -86_400))
        let fuller = try recipe("Madras Curry", (names + ["coconut cream"]).map { ("1", $0) }, steps: 6)
        let cluster = try #require(DuplicateRecipeDetectorView.buildDuplicateClusters(from: [older, fuller]).first)
        #expect(cluster.canonical.id == fuller.id)
    }

    @Test("Ingredient similarity ignores quantities and plurals")
    func similarityScore() {
        let a: [Set<String>] = [["tamarind"], ["water"], ["salt"], ["jaggery"]]
        let b: [Set<String>] = [["tamarind"], ["water"], ["salt"], ["jaggery"]]
        #expect(DuplicateRecipeDetectorView.ingredientSimilarity(a, b) == 1.0)
        let c: [Set<String>] = [["tamarind"], ["sugar"], ["date"], ["vinegar"]]
        #expect(DuplicateRecipeDetectorView.ingredientSimilarity(a, c) == 0.25)
    }
}
