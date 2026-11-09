//
//  RecipeTranslation.swift
//  Reczipes2
//
//  A recipe's text in another app language, made by Claude and published with the
//  recipe's public copy (CloudKitRecipe.translationsJSON), so the website shows a
//  French reader French recipes with metric amounts.
//
//  Operator, 2026-11-09: "when a recipe is admitted, it should be localized in the
//  known system locales and provision should be made when a language is added to
//  update the db so it sticks with the app build and launch process".
//
//  Every translation names the English it was made from (`source`, a fingerprint of
//  the recipe's text). A recipe edited since is translated again; a translation that
//  no longer matches is never published. The arrays line up one for one with the
//  English (same sections, ingredients, steps and notes, same order): a reply that
//  doesn't is refused, never patched.
//

import Foundation
import CryptoKit

/// The text of one recipe in one language.
nonisolated struct RecipeTranslation: Codable, Equatable, Sendable {
    nonisolated struct Line: Codable, Equatable, Sendable {
        var quantity: String?
        var unit: String?
        var name: String
        var preparation: String?
    }
    nonisolated struct IngredientGroup: Codable, Equatable, Sendable {
        var title: String?
        var transitionNote: String?
        var ingredients: [Line]
    }
    nonisolated struct StepGroup: Codable, Equatable, Sendable {
        var title: String?
        var steps: [String]
    }

    var title: String
    var headerNotes: String?
    var yield: String?
    var ingredientSections: [IngredientGroup]
    var instructionSections: [StepGroup]
    var notes: [String]
    /// Fingerprint of the English this was made from (RecipeTranslationSource.fingerprint).
    var source: String?
    /// The Claude model that wrote it.
    var model: String?
    /// True when amounts were given in metric units.
    var metric: Bool?

    /// Same shape as the English: one item for each item, in order.
    func fits(_ english: RecipeTranslationSource) -> Bool {
        guard ingredientSections.count == english.ingredientSections.count,
              instructionSections.count == english.instructionSections.count,
              notes.count == english.notes.count else { return false }
        for (a, b) in zip(ingredientSections, english.ingredientSections) where a.ingredients.count != b.ingredients.count { return false }
        for (a, b) in zip(instructionSections, english.instructionSections) where a.steps.count != b.steps.count { return false }
        return true
    }
}

/// The English text a translation is made from, in the order the recipe stores it.
nonisolated struct RecipeTranslationSource: Codable, Equatable, Sendable {
    nonisolated struct Line: Codable, Equatable, Sendable {
        var quantity: String?
        var unit: String?
        var name: String
        var preparation: String?
        var metricQuantity: String?
        var metricUnit: String?
    }
    nonisolated struct IngredientGroup: Codable, Equatable, Sendable {
        var title: String?
        var transitionNote: String?
        var ingredients: [Line]
    }
    nonisolated struct StepGroup: Codable, Equatable, Sendable {
        var title: String?
        var steps: [String]
    }

    var title: String
    var headerNotes: String?
    var yield: String?
    var ingredientSections: [IngredientGroup]
    var instructionSections: [StepGroup]
    var notes: [String]

    /// Bump when the instructions change enough that every recipe should be translated again.
    static let instructionsVersion = 1

    /// The app's recipe types are main-actor types, so this is read on the main actor.
    @MainActor
    init(title: String, headerNotes: String?, yield: String?,
         ingredientSections: [IngredientSection], instructionSections: [InstructionSection], notes: [RecipeNote]) {
        self.title = title
        self.headerNotes = headerNotes
        self.yield = yield
        self.ingredientSections = ingredientSections.map { s in
            IngredientGroup(title: s.title, transitionNote: s.transitionNote, ingredients: s.ingredients.map {
                Line(quantity: $0.quantity, unit: $0.unit, name: $0.name, preparation: $0.preparation,
                     metricQuantity: $0.metricQuantity, metricUnit: $0.metricUnit)
            })
        }
        // Steps in stored order; the web lines translations up the same way.
        self.instructionSections = instructionSections.map { StepGroup(title: $0.title, steps: $0.steps.map(\.text)) }
        self.notes = notes.map(\.text)
    }

    /// Stable across devices: sorted-key JSON of the text (no ids, no dates) plus the
    /// instructions version, hashed.
    var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(self)) ?? Data()
        var hasher = SHA256()
        hasher.update(data: Data("v\(Self.instructionsVersion):".utf8))
        hasher.update(data: data)
        return hasher.finalize().prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

nonisolated enum RecipeTranslationError: Error, Equatable {
    /// The reply was not the JSON asked for.
    case unreadable
    /// The reply did not line up with the English.
    case shapeMismatch
}

/// The translations a public recipe carries, keyed by language code ("fr").
nonisolated enum RecipeTranslations {
    static func decode(_ json: String?) -> [String: RecipeTranslation] {
        guard let data = json?.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: RecipeTranslation].self, from: data) else { return [:] }
        return map
    }

    static func encode(_ map: [String: RecipeTranslation]) -> String? {
        guard !map.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(map)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// The language's name in English, for the instructions ("fr" → "French").
    static func englishName(of code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    /// Countries using a language outside the US measure in metric.
    static func usesMetric(_ code: String) -> Bool {
        Locale(identifier: code).measurementSystem != .us
    }

    /// What Claude is asked.
    static func prompt(for source: RecipeTranslationSource, language code: String) -> String {
        let name = englishName(of: code)
        let units = usesMetric(code) ? """
        - Give every amount in metric units, written the way \(name) recipes write them: g, kg, ml, l, °C, cm. \
        Where the input gives metricQuantity and metricUnit, use them. Otherwise convert: 1 cup = 240 ml, \
        1 fl oz = 30 ml, 1 pint = 475 ml, 1 quart = 950 ml, 1 oz = 28 g, 1 lb = 450 g, \
        °C = (°F − 32) × 5 ÷ 9 rounded to the nearest 5, 1 inch = 2.5 cm. Round to amounts a cook would measure \
        (625 ml, not 591 ml). Tablespoons and teaspoons stay as the language's own spoon measures \
        (in French "c. à soupe" and "c. à café"); a pinch stays a pinch.
        - Convert amounts, temperatures and sizes inside the steps, notes and yield the same way.
        - Write numbers the way \(name) recipes do (decimal comma where the language uses one).
        """ : """
        - Keep every amount and unit as given.
        """
        return """
        Translate this recipe into \(name) for home cooks.

        Return ONLY a JSON object, no markdown, with exactly these keys:
        {"title": string, "headerNotes": string|null, "yield": string|null,
         "ingredientSections": [{"title": string|null, "transitionNote": string|null,
           "ingredients": [{"quantity": string|null, "unit": string|null, "name": string, "preparation": string|null}]}],
         "instructionSections": [{"title": string|null, "steps": [string]}],
         "notes": [string]}

        Rules:
        - Exactly one output item for each input item, in the same order: the same number of ingredient \
        sections, ingredients in each, instruction sections, steps in each, and notes. Never merge, split, add or drop one. \
        A null stays null.
        - Translate every text: title, section titles, ingredient names and preparation, steps, notes, yield, headerNotes.
        - A dish name that is a proper name (Bajrani Raab, Pilau, Vitumbua) stays as it is. An ingredient with no \
        usual \(name) name (jaggery, ajwain, besan) keeps its name.
        \(units)
        - An ingredient counted without a unit (2 eggs) stays a count.
        - Text already in \(name) stays as it is (amounts still converted).
        - Do not add, explain or correct anything.

        Recipe (JSON):
        \(source.json)
        """
    }

    /// Reads Claude's reply. Refuses anything that does not line up with the English.
    static func parse(_ reply: String, source: RecipeTranslationSource, language code: String, model: String) throws -> RecipeTranslation {
        var text = reply
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end {
            text = String(text[start...end])
        }
        guard let data = text.data(using: .utf8),
              var translation = try? JSONDecoder().decode(RecipeTranslation.self, from: data),
              !translation.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeTranslationError.unreadable
        }
        guard translation.fits(source) else { throw RecipeTranslationError.shapeMismatch }
        translation.source = source.fingerprint
        translation.model = model
        translation.metric = usesMetric(code)
        return translation
    }
}
