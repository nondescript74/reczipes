//
//  BookTranslation.swift
//  Reczipes2
//
//  A public book's description in another app language (Δ-224 follow-up).
//  Same rules as RecipeTranslation: made by Claude when the book is published, carried
//  inside the book's public record (CloudKitRecipeBook.translations, no CloudKit schema
//  change), and tied to the English it was made from (`source`), so a book re-described
//  is translated again and an out-of-date translation is never published.
//  Self-contained (Foundation + CryptoKit) so the test target can use it.
//

import Foundation
import CryptoKit

/// One book's description in one language. The book's name is never translated:
/// titles stay as their owner entered them (Z, 2026-11-09).
nonisolated struct BookTranslation: Codable, Equatable, Sendable {
    var bookDescription: String
    /// Fingerprint of the English description this was made from (BookTranslations.fingerprint).
    var source: String?
    /// The Claude model that wrote it.
    var model: String?
}

nonisolated enum BookTranslations {
    static let instructionsVersion = 1

    static func fingerprint(description: String) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("book-description-v\(instructionsVersion):".utf8))
        hasher.update(data: Data(description.utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The description worth translating, or nil (none, or only whitespace).
    static func translatable(_ description: String?) -> String? {
        guard let d = description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty else { return nil }
        return d
    }

    /// What Claude is asked.
    static func prompt(description: String, language code: String) -> String {
        let languageName = RecipeTranslations.englishName(of: code)
        let json = (try? JSONSerialization.data(withJSONObject: ["description": description], options: [.withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        Translate this cookbook description into \(languageName) for the readers of a family recipe website.

        Return ONLY a JSON object, no markdown: {"description": string}

        Rules:
        - Names of people (Noorbhanu Nimji, Samin Nosrat), brands and websites, and titles of published \
        cookbooks stay exactly as they are; the words around them are translated.
        - Text already in \(languageName) stays as it is.
        - Do not add, explain or correct anything.

        Description (JSON):
        \(json)
        """
    }

    /// Reads Claude's reply. Refuses an empty or unreadable one.
    static func parse(_ reply: String, description: String, model: String) throws -> BookTranslation {
        var text = reply
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end {
            text = String(text[start...end])
        }
        struct Reply: Decodable { let description: String }
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw RecipeTranslationError.unreadable
        }
        let translated = decoded.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty else { throw RecipeTranslationError.unreadable }
        return BookTranslation(bookDescription: translated, source: fingerprint(description: description), model: model)
    }
}
