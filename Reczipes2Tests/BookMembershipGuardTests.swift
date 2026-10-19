//
//  BookMembershipGuardTests.swift
//  Reczipes2Tests
//
//  Pure-logic tests for the "a recipe in a book is never deleted" rule.
//

import Testing
import Foundation
@testable import Reczipes2

@Suite("Book Membership Guard")
struct BookMembershipGuardTests {

    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let loose = UUID()

    @MainActor
    private var guardUnderTest: BookMembershipGuard {
        BookMembershipGuard(bookContents: [
            (name: "Shahsultan's Book", recipeIDs: [a, b]),
            (name: "Nimji Book 1", recipeIDs: [b, c])
        ])
    }

    @Test("Members of any book are protected; others are not")
    @MainActor
    func protection() {
        let g = guardUnderTest
        #expect(g.isProtected(a))
        #expect(g.isProtected(b))
        #expect(g.isProtected(c))
        #expect(!g.isProtected(loose))
        #expect(!g.isProtected(nil))
        #expect(g.protectedRecipeIDs == [a, b, c])
    }

    @Test("Book names are reported in book order without repeats")
    @MainActor
    func bookNames() {
        let g = guardUnderTest
        #expect(g.bookNames(for: a) == ["Shahsultan's Book"])
        #expect(g.bookNames(for: b) == ["Shahsultan's Book", "Nimji Book 1"])
        #expect(g.bookNames(for: loose).isEmpty)
    }

    @Test("A recipe listed twice in one book is named once")
    @MainActor
    func duplicateListing() {
        let g = BookMembershipGuard(bookContents: [(name: "X", recipeIDs: [a, a])])
        #expect(g.bookNames(for: a) == ["X"])
    }

    @Test("Partition keeps order and splits protected from deletable")
    @MainActor
    func partition() {
        let result = guardUnderTest.partition([loose, a, c])
        #expect(result.deletable == [loose])
        #expect(result.protected == [a, c])
    }

    @Test("Duplicate copy may be removed only when in no book, or when it is the same id as the keeper")
    @MainActor
    func duplicateRemoval() {
        let g = guardUnderTest
        #expect(g.canRemoveDuplicate(loose, keeping: a))
        #expect(!g.canRemoveDuplicate(a, keeping: loose))
        #expect(!g.canRemoveDuplicate(b, keeping: a))
        #expect(g.canRemoveDuplicate(a, keeping: a))   // same-id row after a sync reset
    }

    @Test("Refusal message names every book")
    @MainActor
    func refusalMessage() {
        let msg = guardUnderTest.refusalMessage(recipeTitle: "Dhokra", recipeID: b)
        #expect(msg.contains("Remove it from 'Shahsultan's Book' and 'Nimji Book 1' first"))
    }

    @Test("List phrase joins names naturally")
    @MainActor
    func listPhrase() {
        #expect(BookMembershipGuard.listPhrase([]) == "")
        #expect(BookMembershipGuard.listPhrase(["A"]) == "'A'")
        #expect(BookMembershipGuard.listPhrase(["A", "B", "C"]) == "'A', 'B' and 'C'")
    }

    @Test("Duplicate keeper prefers the copy that is in a book, and never offers it for removal")
    @MainActor
    func clusterKeeperPrefersBookCopy() throws {
        let encoder = JSONEncoder()
        func recipe(_ steps: Int, added: Date) throws -> RecipeX {
            let section = IngredientSection(ingredients: [Ingredient(quantity: "1", name: "rice"),
                                                          Ingredient(quantity: "2", name: "dal"),
                                                          Ingredient(quantity: "1", name: "salt")])
            let instructions = InstructionSection(steps: (1...steps).map { InstructionStep(stepNumber: $0, text: "Step \($0)") })
            return RecipeX(title: "Khichdi",
                           reference: "https://example.com/khichdi",
                           ingredientSectionsData: try encoder.encode([section]),
                           instructionSectionsData: try encoder.encode([instructions]),
                           dateAdded: added)
        }
        let fuller = try recipe(6, added: Date())
        let inBook = try recipe(2, added: Date(timeIntervalSinceNow: -3600))
        let bookIDs: Set<UUID> = [try #require(inBook.id)]
        let cluster = try #require(DuplicateRecipeDetectorView.buildDuplicateClusters(
            from: [fuller, inBook], includeTitleMatches: false, bookRecipeIDs: bookIDs).first)
        #expect(cluster.canonical.id == inBook.id)
        #expect(cluster.duplicatesToDelete.map(\.id) == [fuller.id])
        #expect(!cluster.isProtectedGroup)
    }

    @Test("When every copy is in a book the group is protected and nothing is removable")
    @MainActor
    func clusterAllInBooks() throws {
        let link = "https://example.com/nan"
        let r1 = RecipeX(title: "Nan", reference: link, dateAdded: Date())
        let r2 = RecipeX(title: "Nan", reference: link, dateAdded: Date(timeIntervalSinceNow: -60))
        let ids: Set<UUID> = [try #require(r1.id), try #require(r2.id)]
        let cluster = try #require(DuplicateRecipeDetectorView.buildDuplicateClusters(
            from: [r1, r2], includeTitleMatches: false, bookRecipeIDs: ids).first)
        #expect(cluster.isProtectedGroup)
        #expect(cluster.duplicatesToDelete.isEmpty)
        #expect(cluster.extraCount == 0)
        #expect(!cluster.isSafeToBulkDelete)
    }
}
