//
//  BookMerger.swift
//  Reczipes2
//
//  Merges same-name books into one (rules in Utilities/BookDuplicates.swift). The kept
//  book gets every recipe and any content it lacks; pictures move to it; each extra is
//  then deleted from the library and its public copy marked deleted and replaced by the
//  kept book, so every device and the website drop it. No recipe is deleted.
//

import Foundation
import SwiftData

@MainActor
enum BookMerger {
    /// Your own books (not ones downloaded from someone else).
    static func ownBooks(in context: ModelContext) -> [Book] {
        let me = CloudKitSharingService.shared.currentUserID
        let all = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        return all.filter { $0.id != nil && ($0.ownerUserID == nil || $0.ownerUserID == me) }
    }

    static func copy(of book: Book, in context: ModelContext) -> BookCopy? {
        guard let id = book.id else { return nil }
        let pictures = BookPictureStore.images(bookID: id, in: context)
        let ownContent = !pictures.isEmpty || book.imagesData != nil
            || book.glossaryData != nil || book.tableOfContentsData != nil
        return BookCopy(id: id, name: book.name ?? "", recipeIDs: book.recipeIDs ?? [],
                        dateCreated: book.dateCreated, hasOwnContent: ownContent)
    }

    static func duplicateGroups(in context: ModelContext) -> [BookDuplicateGroup] {
        BookDuplicates.groups(ownBooks(in: context).compactMap { copy(of: $0, in: context) })
    }

    /// Merge `extraIDs` into `keepID`. Returns how many books were merged away.
    @discardableResult
    static func merge(keepID: UUID, extraIDs: [UUID], in context: ModelContext) -> Int {
        let books = ownBooks(in: context)
        guard let keep = books.first(where: { $0.id == keepID }) else { return 0 }
        let extras = books.filter { book in book.id.map { extraIDs.contains($0) && $0 != keepID } ?? false }
        guard !extras.isEmpty else { return 0 }

        keep.recipeIDs = BookDuplicates.mergedRecipeIDs(keep: keep.recipeIDs ?? [],
                                                       extras: extras.map { $0.recipeIDs ?? [] })
        for extra in extras {
            if keep.bookDescription == nil { keep.bookDescription = extra.bookDescription }
            if keep.coverImageData == nil {
                keep.coverImageData = extra.coverImageData
                keep.coverImageName = extra.coverImageName
            }
            if keep.color == nil { keep.color = extra.color }
            if keep.glossaryData == nil { keep.glossaryData = extra.glossaryData }
            if keep.tableOfContentsData == nil { keep.tableOfContentsData = extra.tableOfContentsData }
            // Pictures: inline ones become records first, then all move to the kept book.
            BookPictureMigration.migrate(book: extra, in: context)
            if let extraID = extra.id {
                let rows = (try? context.fetch(FetchDescriptor<BookPicture>(
                    predicate: #Predicate<BookPicture> { $0.bookID == extraID }))) ?? []
                for row in rows { row.bookID = keepID }
            }
            if keep.imagesData == nil { keep.imagesData = extra.imagesData }
        }
        keep.recipeIDsHash = Book.calculateRecipeIDsHash(from: keep.recipeIDs ?? [])
        keep.markModified()

        let sharing = CloudKitSharingService.shared
        for extra in extras {
            let extraID = extra.id
            AppLog.info("📚 Merged book '\(extra.displayName)' (\(extra.recipeIDs?.count ?? 0) recipes) into '\(keep.displayName)'", category: .storage)
            context.delete(extra)  // its pictures were moved; nothing else hangs off it
            sharing.ownerDeleted(.book, id: extraID, replacedBy: keepID, modelContext: context)
        }
        try? context.save()
        return extras.count
    }

    /// Unattended: merge only copies that add nothing (same recipes or none, no own content).
    @discardableResult
    static func mergeExactCopies(in context: ModelContext) -> Int {
        var merged = 0
        for group in duplicateGroups(in: context) {
            let exact = group.exactExtras.map(\.id)
            guard !exact.isEmpty else { continue }
            merged += merge(keepID: group.keep.id, extraIDs: exact, in: context)
        }
        if merged > 0 { AppLog.info("📚 Merged \(merged) exact copies of books", category: .storage) }
        return merged
    }
}
