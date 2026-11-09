//
//  BookDuplicatesTests.swift
//  Reczipes2Tests
//
//  Same-name book rules (Utilities/BookDuplicates.swift).
//

import Testing
import Foundation
@testable import Reczipes2

@Suite("Duplicate books")
@MainActor
struct BookDuplicatesTests {
    private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
    private func book(_ n: Int, _ name: String, _ recipes: [Int], days: Double = 0, content: Bool = false) -> BookCopy {
        BookCopy(id: id(n), name: name, recipeIDs: recipes.map(id), dateCreated: Date(timeIntervalSince1970: days * 86400),
                 hasOwnContent: content)
    }

    @Test("Names match across case, spaces and hyphens")
    func nameKey() {
        #expect(BookDuplicates.key("The Low-Carb Cookbook") == BookDuplicates.key("the low carb cookbook"))
        #expect(BookDuplicates.key("Soups") != BookDuplicates.key("Salt"))
    }

    @Test("Keep the copy with most recipes, then the oldest")
    func keep() {
        let groups = BookDuplicates.groups([book(1, "Soups", [10, 11], days: 5), book(2, "Soups", [10, 11, 12], days: 9),
                                            book(3, "soups", [], days: 1), book(4, "Salt", [])])
        #expect(groups.count == 1)
        #expect(groups[0].keep.id == id(2))
        let tie = BookDuplicates.groups([book(5, "Food Lab", [1], days: 3), book(6, "Food Lab", [1], days: 2)])
        #expect(tie[0].keep.id == id(6))
    }

    @Test("Only copies that add nothing merge without asking")
    func exact() {
        let groups = BookDuplicates.groups([book(1, "SFAH", [10]), book(2, "SFAH", [10]), book(3, "SFAH", []),
                                            book(4, "SFAH", [11]), book(5, "SFAH", [], content: true)])
        let g = groups[0]
        #expect(Set(g.exactExtras.map(\.id)) == [id(2), id(3)])
        #expect(g.recipesOnlyInExtras == 1)
    }

    @Test("Same book (name + description) merges without asking when nothing is lost")
    func sameBook() {
        func b(_ n: Int, _ recipes: [Int], _ desc: String?, contents: Data? = nil) -> BookCopy {
            BookCopy(id: id(n), name: "Carol's recipes", recipeIDs: recipes.map(id), dateCreated: nil,
                     hasOwnContent: contents != nil, bookDescription: desc, contentsData: contents)
        }
        let keep = b(1, [1, 2, 3, 4], "Handwritten recipes", contents: Data([1]))
        // Subset, own (older) contents page: merges, the kept book's page stays
        #expect(BookDuplicates.mergesUnattended(b(2, [1, 2], "Handwritten  recipes", contents: Data([2])), into: keep))
        // Adds recipes, no conflicting content: merges (union)
        #expect(BookDuplicates.mergesUnattended(b(3, [4, 5], "Handwritten recipes"), into: keep))
        // Adds recipes AND its contents page differs: owner decides
        #expect(!BookDuplicates.mergesUnattended(b(4, [5], "Handwritten recipes", contents: Data([2])), into: keep))
        // Different or missing description: a name alone never merges
        #expect(!BookDuplicates.mergesUnattended(b(5, [1], "Any kind of soup"), into: keep))
        #expect(!BookDuplicates.mergesUnattended(b(6, [1], nil), into: b(7, [1, 2], nil)))
    }

    @Test("Merged order: kept book first, then new recipes, no repeats")
    func order() {
        let merged = BookDuplicates.mergedRecipeIDs(keep: [id(1), id(2)], extras: [[id(2), id(3)], [id(3), id(4)]])
        #expect(merged == [id(1), id(2), id(3), id(4)])
    }
}
