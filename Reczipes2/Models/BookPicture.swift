//
//  BookPicture.swift
//  Reczipes2
//
//  Created on 10/17/26.
//
//  One SwiftData record per book picture (cover or interior).
//
//  Before this, picture bytes lived base64-inline in `Book.imagesData` (a JSON
//  blob of [BookImage]); a book with 7 pictures was 2–4 MB, every edit
//  re-uploaded the whole blob through private CloudKit sync, and the public
//  record (≈1 MB cap) could not carry the pictures at all.
//
//  Now:
//  * `BookPicture` rows hold the bytes (`.externalStorage`) and the metadata.
//  * `Book.imagesData` holds METADATA ONLY (BookImage entries with empty bytes)
//    so old builds still decode it and lists stay cheap.
//  * `Book.images` / `coverImages` / `interiorImages` /
//    `setImagesUpdatingPrimaryCover` keep working; they read and write rows via
//    `BookPictureStore` (see Book.swift).
//  * `BookPictureMigration` moves inline pictures into rows on launch.
//
//  CLOUDKIT COMPATIBILITY: every property optional, no unique constraints, no
//  relationships (`bookID` is a plain UUID, not a relationship to Book).
//

import Foundation
import SwiftData
import CryptoKit

/// SHA256 hex of picture bytes (nil for empty data). Same value as `Book.calculateImageHash`.
nonisolated enum BookPictureHash {
    static func sha256(_ data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@Model
final class BookPicture {
    /// Picture id (same value as the `BookImage.id` it came from). Unique per book, not globally.
    var id: UUID?
    /// `Book.id` this picture belongs to (plain field, not a relationship)
    var bookID: UUID?
    /// "cover" or "interior" (nil = interior)
    var kind: String?
    var title: String?
    var caption: String?
    /// Display order inside the book (covers first, then interior)
    var sortOrder: Int?
    /// Page in the printed book this picture faces, e.g. "page 16"
    var sourcePage: String?
    /// File name it was imported from (a re-import replaces instead of duplicating)
    var sourceFile: String?
    /// JSON of [UUID] — recipes shown in this picture
    var linkedRecipeIDsData: Data?
    /// The picture (JPEG, ≤1600 px long side). Stored outside the SQLite row.
    @Attribute(.externalStorage) var imageData: Data?
    /// SHA256 of `imageData` (lets sync/publish skip unchanged bytes without loading them)
    var imageHash: String?
    var dateAdded: Date?
    var dateModified: Date?

    init(id: UUID? = UUID(),
         bookID: UUID? = nil,
         kind: String? = nil,
         title: String? = nil,
         caption: String? = nil,
         sortOrder: Int? = 0,
         sourcePage: String? = nil,
         sourceFile: String? = nil,
         linkedRecipeIDsData: Data? = nil,
         imageData: Data? = nil,
         imageHash: String? = nil,
         dateAdded: Date? = Date(),
         dateModified: Date? = Date()) {
        self.id = id
        self.bookID = bookID
        self.kind = kind
        self.title = title
        self.caption = caption
        self.sortOrder = sortOrder
        self.sourcePage = sourcePage
        self.sourceFile = sourceFile
        self.linkedRecipeIDsData = linkedRecipeIDsData
        self.imageData = imageData
        self.imageHash = imageHash
        self.dateAdded = dateAdded
        self.dateModified = dateModified
    }
}

// MARK: - Conversions

extension BookPicture {

    var linkedRecipeIDs: [UUID]? {
        guard let data = linkedRecipeIDsData else { return nil }
        return try? JSONDecoder().decode([UUID].self, from: data)
    }

    nonisolated static func encodeLinked(_ ids: [UUID]?) -> Data? {
        guard let ids, !ids.isEmpty else { return nil }
        return try? JSONEncoder().encode(ids)
    }

    var isCover: Bool { kind == BookImage.coverKind }

    /// New row from a picture of `bookID`
    convenience init(bookID: UUID, image: BookImage, now: Date = Date()) {
        self.init(
            id: image.id,
            bookID: bookID,
            kind: image.kind,
            title: image.title,
            caption: image.caption,
            sortOrder: image.order,
            sourcePage: image.sourcePage,
            sourceFile: image.sourceFile,
            linkedRecipeIDsData: Self.encodeLinked(image.linkedRecipeIDs),
            imageData: image.imageData.isEmpty ? nil : image.imageData,
            imageHash: BookPictureHash.sha256(image.imageData),
            dateAdded: image.dateAdded,
            dateModified: now
        )
    }

    /// Copies `image` onto this row, assigning only what changed (so private
    /// CloudKit sync doesn't re-upload unchanged fields). Empty `image.imageData`
    /// means "metadata only" and keeps the stored bytes.
    /// - Returns: true when anything changed
    @discardableResult
    func update(from image: BookImage, now: Date = Date()) -> Bool {
        var changed = false
        if kind != image.kind { kind = image.kind; changed = true }
        if title != image.title { title = image.title; changed = true }
        if caption != image.caption { caption = image.caption; changed = true }
        if sortOrder != image.order { sortOrder = image.order; changed = true }
        if sourcePage != image.sourcePage { sourcePage = image.sourcePage; changed = true }
        if sourceFile != image.sourceFile { sourceFile = image.sourceFile; changed = true }
        if linkedRecipeIDs != image.linkedRecipeIDs.flatMap({ $0.isEmpty ? nil : $0 }) {
            linkedRecipeIDsData = Self.encodeLinked(image.linkedRecipeIDs)
            changed = true
        }
        if !image.imageData.isEmpty {
            let newHash = BookPictureHash.sha256(image.imageData)
            if newHash != imageHash || imageData == nil {
                imageData = image.imageData
                imageHash = newHash
                changed = true
            }
        }
        if changed { dateModified = now }
        return changed
    }

    /// The picture as the app's `BookImage` value (with bytes; empty bytes if missing)
    var asBookImage: BookImage {
        BookImage(
            id: id ?? UUID(),
            title: title,
            caption: caption,
            imageData: imageData ?? Data(),
            order: sortOrder ?? 0,
            dateAdded: dateAdded ?? Date(),
            kind: kind,
            sourcePage: sourcePage,
            linkedRecipeIDs: linkedRecipeIDs,
            sourceFile: sourceFile
        )
    }
}

// MARK: - Metadata (no bytes)

nonisolated extension BookImage {
    /// Same picture without its bytes (what `Book.imagesData` stores now)
    var metadataOnly: BookImage {
        var copy = self
        copy.imageData = Data()
        return copy
    }

    var hasBytes: Bool { !imageData.isEmpty }
}

// MARK: - Store

/// Reads and writes a book's pictures. All picture writes go through here.
nonisolated enum BookPictureStore {

    /// False when the context's container was built without `BookPicture`
    /// (SwiftUI previews and older tests that list only `Book.self`). Callers
    /// then keep pictures inline in `Book.imagesData`, as before.
    static func isAvailable(in context: ModelContext) -> Bool {
        context.container.schema.entities.contains { $0.name == String(describing: BookPicture.self) }
    }

    /// Rows of one book, in display order. If sync produced two rows with the
    /// same picture id, only one is returned (the one with bytes, newest first).
    static func fetch(bookID: UUID, in context: ModelContext) -> [BookPicture] {
        guard isAvailable(in: context) else { return [] }
        let descriptor = FetchDescriptor<BookPicture>(predicate: #Predicate<BookPicture> { $0.bookID == bookID })
        let rows: [BookPicture]
        do {
            rows = try context.fetch(descriptor)
        } catch {
            AppLog.error("📷 Could not fetch pictures for book \(bookID): \(error)", category: .storage)
            return []
        }
        return uniqueByID(rows).sorted { a, b in
            let oa = a.sortOrder ?? 0, ob = b.sortOrder ?? 0
            if oa != ob { return oa < ob }
            return (a.dateAdded ?? Date.distantPast) < (b.dateAdded ?? Date.distantPast)
        }
    }

    /// Pictures of one book as `BookImage` values (with bytes)
    static func images(bookID: UUID, in context: ModelContext) -> [BookImage] {
        fetch(bookID: bookID, in: context).map(\.asBookImage)
    }

    /// Number of rows for a book (cheap check, no bytes loaded)
    static func count(bookID: UUID, in context: ModelContext) -> Int {
        guard isAvailable(in: context) else { return 0 }
        let descriptor = FetchDescriptor<BookPicture>(predicate: #Predicate<BookPicture> { $0.bookID == bookID })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Makes the book's rows equal `images` (upsert by id, delete the rest).
    /// Entries with empty bytes update metadata and keep the stored bytes; an
    /// entry with empty bytes and no existing row is skipped (nothing to show).
    static func replace(bookID: UUID, with images: [BookImage], in context: ModelContext, now: Date = Date()) {
        guard isAvailable(in: context) else { return }
        let descriptor = FetchDescriptor<BookPicture>(predicate: #Predicate<BookPicture> { $0.bookID == bookID })
        let existing = (try? context.fetch(descriptor)) ?? []
        var byID: [UUID: BookPicture] = [:]
        var extras: [BookPicture] = []
        for row in preferredFirst(existing) {
            guard let id = row.id else { extras.append(row); continue }
            if byID[id] == nil { byID[id] = row } else { extras.append(row) }
        }
        var kept = Set<UUID>()
        for image in images {
            guard kept.insert(image.id).inserted else { continue }
            if let row = byID[image.id] {
                row.update(from: image, now: now)
            } else if image.hasBytes {
                context.insert(BookPicture(bookID: bookID, image: image, now: now))
            } else {
                AppLog.warning("📷 Picture \(image.id) has no bytes and no stored row; skipped", category: .storage)
                kept.remove(image.id)
            }
        }
        for (id, row) in byID where !kept.contains(id) { context.delete(row) }
        // Duplicate rows of a kept id (e.g. created on two devices): drop the copy
        for row in extras { context.delete(row) }
    }

    /// Adds one picture at the end
    static func add(_ image: BookImage, bookID: UUID, in context: ModelContext) {
        guard isAvailable(in: context) else { return }
        var copy = image
        copy.order = (fetch(bookID: bookID, in: context).map { $0.sortOrder ?? 0 }.max() ?? -1) + 1
        context.insert(BookPicture(bookID: bookID, image: copy))
    }

    /// Deletes one picture
    static func delete(pictureID: UUID, bookID: UUID, in context: ModelContext) {
        guard isAvailable(in: context) else { return }
        let descriptor = FetchDescriptor<BookPicture>(predicate: #Predicate<BookPicture> { $0.bookID == bookID && $0.id == pictureID })
        for row in (try? context.fetch(descriptor)) ?? [] { context.delete(row) }
    }

    /// Sets `sortOrder` to the position in `orderedIDs`; ids not listed keep their relative order after them
    static func reorder(bookID: UUID, orderedIDs: [UUID], in context: ModelContext) {
        let rows = fetch(bookID: bookID, in: context)
        let position = Dictionary(orderedIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let sorted = rows.enumerated().sorted { a, b in
            let pa = a.element.id.flatMap { position[$0] } ?? (orderedIDs.count + a.offset)
            let pb = b.element.id.flatMap { position[$0] } ?? (orderedIDs.count + b.offset)
            return pa < pb
        }
        for (index, pair) in sorted.enumerated() where pair.element.sortOrder != index {
            pair.element.sortOrder = index
            pair.element.dateModified = Date()
        }
    }

    /// Deletes every picture row of `bookID`. Returns the number deleted.
    @discardableResult
    static func deleteAll(bookID: UUID, in context: ModelContext) -> Int {
        guard isAvailable(in: context) else { return 0 }
        let descriptor = FetchDescriptor<BookPicture>(predicate: #Predicate<BookPicture> { $0.bookID == bookID })
        let rows = (try? context.fetch(descriptor)) ?? []
        rows.forEach { context.delete($0) }
        return rows.count
    }

    /// Deletes a Book record and its pictures. Pictures are kept when another
    /// Book row has the same id (duplicate rows from sync share their pictures).
    /// Never deletes recipes.
    static func deleteBook(_ book: Book, in context: ModelContext) {
        if let bookID = book.id {
            let others = (try? context.fetch(FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.id == bookID }))) ?? []
            let anotherCopyRemains = others.contains { $0.persistentModelID != book.persistentModelID }
            if !anotherCopyRemains {
                let removed = deleteAll(bookID: bookID, in: context)
                if removed > 0 {
                    AppLog.info("📷 Deleted \(removed) picture(s) of book '\(book.displayName)'", category: .storage)
                }
            }
        }
        context.delete(book)
    }

    /// JSON stored in `Book.imagesData`: the pictures without bytes (nil when none)
    static func metadataJSON(for images: [BookImage]) -> Data? {
        guard !images.isEmpty else { return nil }
        return try? JSONEncoder().encode(images.map(\.metadataOnly))
    }

    // MARK: Helpers

    /// Rows with bytes first, then newest
    private static func preferredFirst(_ rows: [BookPicture]) -> [BookPicture] {
        rows.sorted { a, b in
            let ah = a.imageHash != nil, bh = b.imageHash != nil
            if ah != bh { return ah }
            return (a.dateModified ?? .distantPast) > (b.dateModified ?? .distantPast)
        }
    }

    static func uniqueByID(_ rows: [BookPicture]) -> [BookPicture] {
        var seen = Set<UUID>()
        return preferredFirst(rows).filter { row in
            guard let id = row.id else { return true }
            return seen.insert(id).inserted
        }
    }
}

// MARK: - One-time migration of inline pictures

/// Moves picture bytes from `Book.imagesData` (inline base64 JSON) into
/// `BookPicture` rows, then rewrites `imagesData` as metadata only.
///
/// Runs on every launch (cheap when nothing is inline) because books written by
/// older builds on another device can still arrive through iCloud with inline
/// bytes. Idempotent: a picture whose id (or source file) already has a row for
/// that book is not added again. A blob that can't be decoded is left untouched
/// and logged — a picture is never dropped.
@MainActor
enum BookPictureMigration {

    nonisolated struct Result: Equatable {
        var booksScanned = 0
        var booksMigrated = 0
        var picturesCreated = 0
        var undecodable = 0
    }

    /// Plans the migration of one book's inline JSON without touching storage.
    /// - Returns: nil when `data` can't be decoded (leave it alone), otherwise
    ///   the pictures that need a new row and the metadata-only JSON to store.
    static func plan(inline data: Data,
                     existingIDs: Set<UUID>,
                     existingSourceFiles: Set<String>) -> (newRows: [BookImage], metadata: [BookImage])? {
        guard let decoded = try? JSONDecoder().decode([BookImage].self, from: data) else { return nil }
        var newRows: [BookImage] = []
        var seen = existingIDs
        for image in decoded where image.hasBytes {
            if seen.contains(image.id) { continue }
            if let file = image.sourceFile, existingSourceFiles.contains(file) { continue }
            seen.insert(image.id)
            newRows.append(image)
        }
        return (newRows, decoded.map(\.metadataOnly))
    }

    /// Migrates one book. Returns the number of rows created, or nil if its JSON
    /// could not be decoded (data left in place).
    @discardableResult
    static func migrate(book: Book, in context: ModelContext) -> Int? {
        guard let bookID = book.id, let data = book.imagesData else { return 0 }
        guard BookPictureStore.isAvailable(in: context) else { return 0 }
        guard let decoded = try? JSONDecoder().decode([BookImage].self, from: data) else {
            AppLog.error("📷 Book '\(book.displayName)': picture JSON could not be decoded (\(data.count) bytes); left in place", category: .storage)
            return nil
        }
        guard decoded.contains(where: \.hasBytes) else { return 0 }   // already metadata only

        let rows = BookPictureStore.fetch(bookID: bookID, in: context)
        let existingIDs = Set(rows.compactMap(\.id))
        let existingFiles = Set(rows.compactMap(\.sourceFile))
        guard let planned = plan(inline: data, existingIDs: existingIDs, existingSourceFiles: existingFiles) else { return nil }

        // A row that exists but lost its bytes gets them back from the inline copy
        for image in decoded where image.hasBytes {
            if let row = rows.first(where: { $0.id == image.id }), row.imageData == nil {
                row.imageData = image.imageData
                row.imageHash = BookPictureHash.sha256(image.imageData)
                row.dateModified = Date()
            }
        }
        for image in planned.newRows {
            context.insert(BookPicture(bookID: bookID, image: image))
        }

        // Metadata: the book's own list, plus rows it didn't mention (from another device)
        var metadata = planned.metadata
        let listed = Set(metadata.map(\.id))
        for row in rows where !(row.id.map(listed.contains) ?? true) {
            metadata.append(row.asBookImage.metadataOnly)
        }
        book.imagesData = BookPictureStore.metadataJSON(for: metadata)
        AppLog.info("📷 Book '\(book.displayName)': moved \(planned.newRows.count) inline picture(s) to picture records (\(data.count) → \(book.imagesData?.count ?? 0) bytes)", category: .storage)
        return planned.newRows.count
    }

    /// Migrates every book that still has inline picture bytes. Saves after each book.
    @discardableResult
    static func migrateAll(in context: ModelContext) -> Result {
        var result = Result()
        let books: [Book]
        do {
            books = try context.fetch(FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.imagesData != nil }))
        } catch {
            AppLog.error("📷 Picture migration: could not fetch books: \(error)", category: .storage)
            return result
        }
        for book in books {
            result.booksScanned += 1
            guard let created = migrate(book: book, in: context) else {
                result.undecodable += 1
                continue
            }
            guard context.hasChanges else { continue }
            do {
                try context.save()
                result.booksMigrated += 1
                result.picturesCreated += created
            } catch {
                AppLog.error("📷 Picture migration: save failed for '\(book.displayName)': \(error)", category: .storage)
            }
        }
        if result.booksMigrated > 0 || result.undecodable > 0 {
            AppLog.info("📷 Picture migration: \(result.booksMigrated) book(s), \(result.picturesCreated) picture record(s) created, \(result.undecodable) undecodable", category: .storage)
        }
        return result
    }
}
