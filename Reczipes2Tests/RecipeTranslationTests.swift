//
//  RecipeTranslationTests.swift
//  Reczipes2Tests
//
//  Recipe translations published for the web: the fingerprint follows the text,
//  a reply that doesn't line up with the English is refused, French is metric.
//

import Testing
import Foundation
@testable import Reczipes2

@Suite("Recipe translations")
@MainActor
struct RecipeTranslationTests {

    private func source(stepText: String = "Boil water and jaggery until the jaggery dissolves.") -> RecipeTranslationSource {
        RecipeTranslationSource(
            title: "Bajrani Raab",
            headerNotes: "Spiced Drink.",
            yield: "Makes approximately 2½ cups (625 mL)",
            ingredientSections: [IngredientSection(ingredients: [
                Ingredient(quantity: "2½", unit: "cups", name: "water", metricQuantity: "625", metricUnit: "ml"),
                Ingredient(quantity: "1", unit: "tbsp", name: "butter"),
            ])],
            instructionSections: [InstructionSection(steps: [
                InstructionStep(stepNumber: 1, text: stepText),
                InstructionStep(stepNumber: 2, text: "Add milk and serve hot."),
            ])],
            notes: [RecipeNote(type: .general, text: "Jaggery is unrefined cane sugar.")])
    }

    private let goodReply = """
    ```json
    {"title": "Bajrani Raab", "headerNotes": "Boisson épicée.", "yield": "Donne environ 625 ml",
     "ingredientSections": [{"title": null, "transitionNote": null, "ingredients": [
        {"quantity": "625", "unit": "ml", "name": "eau", "preparation": null},
        {"quantity": "1", "unit": "c. à soupe", "name": "beurre", "preparation": null}]}],
     "instructionSections": [{"title": null, "steps": ["Faire bouillir l'eau et le jaggery.", "Ajouter le lait et servir chaud."]}],
     "notes": ["Le jaggery est un sucre de canne non raffiné."]}
    ```
    """

    @Test func fingerprintFollowsTheText() {
        #expect(source().fingerprint == source().fingerprint)
        #expect(source().fingerprint != source(stepText: "Boil water.").fingerprint)
        #expect(source().fingerprint.count == 32)
    }

    @Test func fingerprintIgnoresIDs() {
        // Fresh UUIDs on every section/ingredient must not change it (same recipe on two devices).
        let a = source(), b = source()
        #expect(a == b)
        #expect(a.fingerprint == b.fingerprint)
    }

    @Test func goodReplyIsRead() throws {
        let t = try RecipeTranslations.parse(goodReply, source: source(), language: "fr", model: "m")
        #expect(t.title == "Bajrani Raab")
        #expect(t.ingredientSections[0].ingredients[0].unit == "ml")
        #expect(t.source == source().fingerprint)
        #expect(t.metric == true)
        #expect(t.model == "m")
    }

    @Test func replyThatDropsAStepIsRefused() {
        let bad = goodReply.replacingOccurrences(of: ", \"Ajouter le lait et servir chaud.\"", with: "")
        #expect(throws: RecipeTranslationError.shapeMismatch) {
            try RecipeTranslations.parse(bad, source: source(), language: "fr", model: "m")
        }
    }

    @Test func replyThatIsNotJSONIsRefused() {
        #expect(throws: RecipeTranslationError.unreadable) {
            try RecipeTranslations.parse("Sorry, I can't.", source: source(), language: "fr", model: "m")
        }
    }

    @Test func frenchIsMetricAndNamed() {
        #expect(RecipeTranslations.usesMetric("fr"))
        #expect(RecipeTranslations.englishName(of: "fr") == "French")
        let prompt = RecipeTranslations.prompt(for: source(), language: "fr")
        #expect(prompt.contains("metric"))
        #expect(prompt.contains("c. à soupe"))
        #expect(prompt.contains("Bajrani Raab"))
    }

    @Test func everyAppLanguageButEnglishIsATarget() {
        #expect(RecipeLocalizer.targetLanguages == AppLanguage.allCases.filter { $0 != .english }.map(\.rawValue))
        #expect(RecipeLocalizer.targetLanguages.contains("fr"))
    }

    @Test func translationsRoundTripInsideTheRecipePayload() throws {
        let t = try RecipeTranslations.parse(goodReply, source: source(), language: "fr", model: "m")
        var recipe = CloudKitRecipe(id: UUID(), title: "Bajrani Raab", headerNotes: nil, yield: nil,
                                    ingredientSections: [], instructionSections: [], notes: [], reference: nil,
                                    imageName: nil, additionalImageNames: nil, sharedByUserID: nil,
                                    sharedByUserName: nil, sharedDate: Date())
        recipe.translationsJSON = RecipeTranslations.encode(["fr": t])
        let decoded = try JSONDecoder().decode(CloudKitRecipe.self, from: JSONEncoder().encode(recipe))
        #expect(RecipeTranslations.decode(decoded.translationsJSON)["fr"] == t)
    }

    @Test func olderPayloadWithoutTranslationsStillDecodes() throws {
        let json = #"{"id":"3A79BC31-EA99-46D3-A1DF-FDE65E2EB505","title":"T","ingredientSections":[],"instructionSections":[],"notes":[],"sharedDate":0}"#
        let decoded = try JSONDecoder().decode(CloudKitRecipe.self, from: Data(json.utf8))
        #expect(decoded.translationsJSON == nil)
        #expect(RecipeTranslations.decode(decoded.translationsJSON).isEmpty)
    }
}
