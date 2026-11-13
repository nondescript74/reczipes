//
//  OpenBooksGuardTests.swift
//  Reczipes2Tests
//
//  The unattended duplicate-book clean-up never deletes a book that is open on screen;
//  the merge it held back runs once the last open book closes.
//

import Testing
import Foundation
import SwiftData
@testable import Reczipes2

@Suite("Open books are never merged away", .serialized)
@MainActor
struct OpenBooksGuardTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Book.self, BookPicture.self])
        let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    /// Two rows of one book (same id), as an iCloud reset leaves them. The older is kept.
    private func twoCopies(in context: ModelContext) throws -> (kept: Book, extra: Book) {
        let id = UUID()
        let kept = Book(id: id, name: "Soups", recipeIDs: [UUID()], dateCreated: Date(timeIntervalSince1970: 1_000))
        let extra = Book(id: id, name: "Soups", recipeIDs: [UUID()], dateCreated: Date(timeIntervalSince1970: 2_000))
        context.insert(kept); context.insert(extra)
        try context.save()
        return (kept, extra)
    }

    private func bookCount(_ context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Book>())
    }

    @Test("A copy open on screen is not deleted; the merge runs after it closes")
    func openCopyHeldBackThenMerged() async throws {
        let open = OpenBooks.shared
        open.resetForTesting()
        defer { open.resetForTesting() }
        let context = try makeContext()
        let (_, extra) = try twoCopies(in: context)

        open.opened(extra)
        CloudKitDuplicateMonitor.shared.mergeDuplicateBooksNow(in: context)
        #expect(try bookCount(context) == 2)
        #expect(open.hasDeferredCleanup)

        var ran = false
        open.settleDelay = .zero
        open.runDeferredCleanup = {
            ran = true
            CloudKitDuplicateMonitor.shared.mergeDuplicateBooksNow(in: context)
        }
        open.closed(extra)
        let pending = try #require(open.pendingRun)
        await pending.value
        #expect(ran)
        #expect(try bookCount(context) == 1)
        #expect(!open.hasDeferredCleanup)
    }

    @Test("When only the kept copy is open, the extra is merged away at once")
    func keptCopyOpenStillMerges() throws {
        let open = OpenBooks.shared
        open.resetForTesting()
        defer { open.resetForTesting() }
        let context = try makeContext()
        let (kept, _) = try twoCopies(in: context)

        open.opened(kept)
        CloudKitDuplicateMonitor.shared.mergeDuplicateBooksNow(in: context)
        #expect(try bookCount(context) == 1)
        #expect(!open.hasDeferredCleanup)
    }

    @Test("A book opened twice stays open until both screens close")
    func openCountsNest() throws {
        let open = OpenBooks.shared
        open.resetForTesting()
        defer { open.resetForTesting() }
        let context = try makeContext()
        let (_, extra) = try twoCopies(in: context)

        open.opened(extra); open.opened(extra)
        open.closed(extra)
        #expect(open.isOpen(extra))
        open.closed(extra)
        #expect(!open.isOpen(extra))
    }

    @Test("Reopening a book before the delay passes keeps the held-back merge waiting")
    func reopenCancelsDeferredRun() async throws {
        let open = OpenBooks.shared
        open.resetForTesting()
        defer { open.resetForTesting() }
        let context = try makeContext()
        let (_, extra) = try twoCopies(in: context)

        open.opened(extra)
        CloudKitDuplicateMonitor.shared.mergeDuplicateBooksNow(in: context)
        var ran = false
        open.settleDelay = .milliseconds(200)
        open.runDeferredCleanup = { ran = true }
        open.closed(extra)
        let pending = try #require(open.pendingRun)
        open.opened(extra)
        #expect(open.pendingRun == nil)
        await pending.value
        #expect(!ran)
        #expect(try bookCount(context) == 2)
        #expect(open.hasDeferredCleanup)
    }
}
