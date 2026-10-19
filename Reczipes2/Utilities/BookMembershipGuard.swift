//
//  BookMembershipGuard.swift
//  Reczipes2
//
//  Created on 10/17/26.
//
//  ONE place that answers "is this recipe in a book?".
//
//  RULE: once a recipe is in any Book (its UUID is in Book.recipeIDs), no
//  automatic, bulk or everyday user action may delete it. Removing it FROM a
//  book is always allowed. The only path that may delete a book member is the
//  explicit admin action in CloudKitRecipeManagerView (Settings → Sharing →
//  Manage CloudKit Recipes → "Delete a Book Recipe (Admin)…"), which shows the books, requires the
//  recipe title to be typed, removes the id from those books and only then
//  deletes the recipe (see `forceDeleteBookMember`).
//
//  Every code path that deletes a RecipeX must consult this guard first:
//    - bulk / automatic paths: skip the recipe and log it
//    - user-facing deletes:    refuse with `refusalMessage(...)`
//

import Foundation
import SwiftData

struct BookMembershipGuard {

    /// recipe UUID -> names of the books that contain it (in book order, de-duplicated)
    let membership: [UUID: [String]]

    // MARK: - Init

    /// Pure-logic initializer (used by tests and by the other initializers).
    /// - Parameter books: (book name, recipe IDs in that book)
    init(bookContents: [(name: String, recipeIDs: [UUID])]) {
        var map: [UUID: [String]] = [:]
        for book in bookContents {
            for rid in book.recipeIDs {
                var names = map[rid, default: []]
                if !names.contains(book.name) { names.append(book.name) }
                map[rid] = names
            }
        }
        self.membership = map
    }

    /// Build from already-fetched books.
    init(books: [Book]) {
        self.init(bookContents: books.map { (name: $0.displayName, recipeIDs: $0.recipeIDs ?? []) })
    }

    /// Fetch every Book in `context`. If the fetch fails the guard FAILS SAFE:
    /// `fetchFailed` is true and `isProtected` returns true for every recipe,
    /// so nothing is deleted on the strength of an unreadable book table.
    init(context: ModelContext) {
        let books: [Book]?
        do {
            books = try context.fetch(FetchDescriptor<Book>())
        } catch {
            AppLog.error("BookMembershipGuard: could not fetch books (\(error)) — treating every recipe as protected", category: .recipe)
            books = nil
        }
        self.init(books: books ?? [])
        if books == nil { self.fetchFailed = true }
    }

    /// True when the books could not be read; every recipe is then treated as protected.
    private(set) var fetchFailed = false

    // MARK: - Queries

    /// UUIDs of all recipes that belong to at least one book.
    var protectedRecipeIDs: Set<UUID> { Set(membership.keys) }

    /// Whether the recipe with this id is in any book (and therefore must not be deleted).
    /// A nil id is not protected (it cannot be referenced by a book).
    func isProtected(_ recipeID: UUID?) -> Bool {
        guard let recipeID else { return false }
        if fetchFailed { return true }
        return membership[recipeID] != nil
    }

    /// Names of the books containing the recipe (empty when none).
    func bookNames(for recipeID: UUID?) -> [String] {
        guard let recipeID else { return [] }
        return membership[recipeID] ?? []
    }

    /// Splits ids into (deletable, protected), preserving order.
    func partition(_ ids: [UUID]) -> (deletable: [UUID], protected: [UUID]) {
        var deletable: [UUID] = []
        var protected: [UUID] = []
        for id in ids {
            if isProtected(id) { protected.append(id) } else { deletable.append(id) }
        }
        return (deletable, protected)
    }

    /// May a duplicate copy `copyID` be removed while `keepID` is kept?
    /// Allowed when the copy is in no book, or when it is the very same UUID
    /// as the kept copy (two rows for one id after a sync reset — the books
    /// still resolve to the surviving row).
    func canRemoveDuplicate(_ copyID: UUID?, keeping keepID: UUID?) -> Bool {
        if let copyID, let keepID, copyID == keepID { return true }
        return !isProtected(copyID)
    }

    // MARK: - User-facing text

    /// "Remove it from <book> first" text for a refused delete.
    func refusalMessage(recipeTitle: String, recipeID: UUID?) -> String {
        Self.refusalMessage(recipeTitle: recipeTitle, bookNames: bookNames(for: recipeID))
    }

    static func refusalMessage(recipeTitle: String, bookNames: [String]) -> String {
        guard !bookNames.isEmpty else {
            return "'\(recipeTitle)' is protected because the list of books could not be read. Try again later."
        }
        return "'\(recipeTitle)' is in \(listPhrase(bookNames)). Remove it from \(listPhrase(bookNames)) first. Recipes that belong to a book are never deleted."
    }

    /// "Book A", "Book A and Book B", "Book A, Book B and Book C"
    static func listPhrase(_ names: [String]) -> String {
        let quoted = names.map { "'\($0)'" }
        switch quoted.count {
        case 0: return ""
        case 1: return quoted[0]
        default: return quoted.dropLast().joined(separator: ", ") + " and " + quoted.last!
        }
    }

    // MARK: - Logging helper for bulk paths

    /// Log that `recipeTitle` was skipped by `operation` because it is in a book.
    func logSkip(recipeTitle: String, recipeID: UUID?, operation: String) {
        let names = bookNames(for: recipeID)
        AppLog.warning("🛡️ \(operation): kept '\(recipeTitle)' (\(recipeID?.uuidString ?? "nil")) — it is in book(s) \(names.joined(separator: ", "))", category: .recipe)
    }
}

// MARK: - The one explicit path that may delete a book member

extension BookMembershipGuard {

    /// Removes `recipe` from every book that lists it, then deletes it.
    /// ONLY called from the CloudKit admin screen after the user has typed the
    /// recipe title. Caller saves the context.
    /// - Returns: names of the books it was removed from.
    @discardableResult
    static func forceDeleteBookMember(_ recipe: RecipeX, typedConfirmation: String, in context: ModelContext) throws -> [String] {
        let expected = (recipe.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty,
              typedConfirmation.trimmingCharacters(in: .whitespacesAndNewlines) == expected else {
            throw ForceDeleteError.confirmationMismatch
        }
        guard let rid = recipe.id else {
            context.delete(recipe)
            return []
        }
        let books = try context.fetch(FetchDescriptor<Book>())
        var removedFrom: [String] = []
        for book in books where (book.recipeIDs ?? []).contains(rid) {
            book.removeRecipe(rid)
            removedFrom.append(book.displayName)
        }
        AppLog.notice("🗑️ Admin force-delete of book recipe '\(expected)' (\(rid)); removed from \(removedFrom.joined(separator: ", "))", category: .recipe)
        context.delete(recipe)
        return removedFrom
    }

    /// Admin batch delete (Settings → Manage CloudKit Recipes → "Delete Recipes Added on a Day (Admin)…").
    /// Deletes every recipe in `recipes` after the user typed "DELETE <count>" exactly; members are
    /// removed from their books first. Used to discard a failed batch extraction (2026-10-18: the
    /// 20 KB image budget made the model invent recipes). Returns book names touched.
    static func forceDeleteBatch(_ recipes: [RecipeX], typedConfirmation: String, in context: ModelContext) throws -> [String] {
        let expected = "DELETE \(recipes.count)"
        guard !recipes.isEmpty,
              typedConfirmation.trimmingCharacters(in: .whitespacesAndNewlines) == expected else {
            throw ForceDeleteError.batchConfirmationMismatch(expected)
        }
        let books = try context.fetch(FetchDescriptor<Book>())
        var removedFrom: Set<String> = []
        for recipe in recipes {
            if let rid = recipe.id {
                for book in books where (book.recipeIDs ?? []).contains(rid) {
                    book.removeRecipe(rid)
                    removedFrom.insert(book.displayName)
                }
            }
            context.delete(recipe)
        }
        AppLog.notice("🗑️ Admin batch delete of \(recipes.count) recipes; removed from \(removedFrom.sorted().joined(separator: ", "))", category: .recipe)
        return removedFrom.sorted()
    }

    enum ForceDeleteError: LocalizedError {
        case confirmationMismatch
        case batchConfirmationMismatch(String)
        var errorDescription: String? {
            switch self {
            case .confirmationMismatch: return "The typed title does not match the recipe title exactly."
            case .batchConfirmationMismatch(let expected): return "Type \"\(expected)\" exactly to confirm."
            }
        }
    }
}
