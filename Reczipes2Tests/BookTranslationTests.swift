//
//  BookTranslationTests.swift
//  Reczipes2Tests
//
//  Book descriptions in other languages (names are never translated).
//

import Testing
import Foundation
@testable import Reczipes2

@Suite("Book description translations")
@MainActor
struct BookTranslationTests {

    @Test("Fingerprint follows the description")
    func fingerprint() {
        let a = BookTranslations.fingerprint(description: "Filed automatically")
        #expect(a == BookTranslations.fingerprint(description: "Filed automatically"))
        #expect(a != BookTranslations.fingerprint(description: "Filed by hand"))
    }

    @Test("Only a real description is translated")
    func translatable() {
        #expect(BookTranslations.translatable(nil) == nil)
        #expect(BookTranslations.translatable("   \n") == nil)
        #expect(BookTranslations.translatable(" Recipes by my mom ") == "Recipes by my mom")
    }

    @Test("A good reply is read, tied to its English")
    func parsesReply() throws {
        let t = try BookTranslations.parse(#"Voici : {"description": "Recettes de ma mère"}"#,
                                           description: "Recipes by my mom", model: "m")
        #expect(t.bookDescription == "Recettes de ma mère")
        #expect(t.source == BookTranslations.fingerprint(description: "Recipes by my mom"))
    }

    @Test("An empty or unreadable reply is refused")
    func refusesBadReply() {
        #expect(throws: RecipeTranslationError.self) {
            _ = try BookTranslations.parse(#"{"description": "  "}"#, description: "Soups", model: "m")
        }
        #expect(throws: RecipeTranslationError.self) {
            _ = try BookTranslations.parse("Sorry, no.", description: "Soups", model: "m")
        }
    }

    @Test("A book's public copy carries its translations; older copies decode without them")
    func bookDataRoundTrip() throws {
        var book = CloudKitRecipeBook(id: UUID(), name: "Soups", bookDescription: "Any kind of soup",
                                      coverImageName: nil, recipeIDs: [], color: nil,
                                      sharedByUserID: "me", sharedByUserName: "Z", sharedDate: Date())
        book.translations = ["fr": BookTranslation(bookDescription: "Toutes sortes de soupes", source: "x", model: "m")]
        let decoded = try JSONDecoder().decode(CloudKitRecipeBook.self, from: JSONEncoder().encode(book))
        #expect(decoded.name == "Soups")
        #expect(decoded.translations?["fr"]?.bookDescription == "Toutes sortes de soupes")

        book.translations = nil
        let old = try JSONDecoder().decode(CloudKitRecipeBook.self, from: JSONEncoder().encode(book))
        #expect(old.translations == nil)
    }
}
