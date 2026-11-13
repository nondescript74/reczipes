//
//  OpenBooks.swift
//  Reczipes2
//
//  Safeguard for the unattended duplicate-book clean-up. A book that is open on screen
//  is never deleted under the person: SwiftData traps when a view reads a model that was
//  deleted under it ("backing data was detached"), the crash 6ecb64a fixed for the
//  Recipes list. The clean-up runs on its own when the app comes back to the front and
//  after every iCloud import, so a book left open while the person switched away could
//  be merged away underneath them. Now the clean-up skips any merge that would delete
//  an open book, remembers it, and runs it once the last open book has closed.
//

import SwiftUI
import SwiftData

@MainActor
final class OpenBooks {
    static let shared = OpenBooks()

    private var openCounts: [PersistentIdentifier: Int] = [:]
    private(set) var hasDeferredCleanup = false
    private var deferredRun: Task<Void, Never>?

    /// What runs once every book is closed after a merge was held back. Tests replace it.
    var runDeferredCleanup: @MainActor () -> Void = OpenBooks.liveCleanup

    /// Wait after the last book closes, so its screen has finished going away first.
    var settleDelay: Duration = .seconds(1)

    private static func liveCleanup() {
        let context = ModelContainerManager.shared.container.mainContext
        CloudKitDuplicateMonitor.shared.mergeDuplicateBooksNow(in: context)
        BookMerger.mergeExactCopies(in: context)
    }

    func opened(_ book: Book) {
        deferredRun?.cancel()
        deferredRun = nil
        openCounts[book.persistentModelID, default: 0] += 1
    }

    func closed(_ book: Book) { closed(book.persistentModelID) }

    /// Takes the identifier, not the book, so closing never reads a model that may be gone.
    func closed(_ id: PersistentIdentifier) {
        guard let count = openCounts[id] else { return }
        openCounts[id] = count > 1 ? count - 1 : nil
        guard openCounts.isEmpty, hasDeferredCleanup else { return }
        let delay = settleDelay
        deferredRun = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.openCounts.isEmpty, self.hasDeferredCleanup else { return }
            self.hasDeferredCleanup = false
            self.deferredRun = nil
            AppLog.info("📚 Running the book clean-up held back while a book was open", category: .storage)
            self.runDeferredCleanup()
        }
    }

    func isOpen(_ book: Book) -> Bool { openCounts[book.persistentModelID] != nil }

    var isAnyBookOpen: Bool { !openCounts.isEmpty }

    /// The held-back clean-up waiting to run, if any (tests await it).
    var pendingRun: Task<Void, Never>? { deferredRun }

    /// True when any of `books` is open on screen; the clean-up is then remembered and
    /// runs again after the last open book closes.
    func holdsBack(_ books: [Book], operation: String) -> Bool {
        guard let open = books.first(where: isOpen) else { return false }
        hasDeferredCleanup = true
        AppLog.info("📚 \(operation): '\(open.displayName)' is open on screen - merge held back until it is closed", category: .storage)
        return true
    }

    /// Tests only: forget every open book and any held-back clean-up.
    func resetForTesting() {
        deferredRun?.cancel()
        deferredRun = nil
        openCounts = [:]
        hasDeferredCleanup = false
        runDeferredCleanup = OpenBooks.liveCleanup
        settleDelay = .seconds(1)
    }
}

/// Marks the book as open while this view is on screen.
private struct HoldsBookOpen: ViewModifier {
    let book: Book?
    @State private var heldID: PersistentIdentifier?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard heldID == nil, let book else { return }
                heldID = book.persistentModelID
                OpenBooks.shared.opened(book)
            }
            .onDisappear {
                if let heldID { OpenBooks.shared.closed(heldID) }
                heldID = nil
            }
    }
}

extension View {
    /// While this view is on screen, unattended duplicate clean-up will not delete `book`.
    func holdsBookOpen(_ book: Book?) -> some View { modifier(HoldsBookOpen(book: book)) }
}
