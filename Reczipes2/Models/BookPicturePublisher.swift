//
//  BookPicturePublisher.swift
//  Reczipes2
//
//  Created on 10/17/26.
//
//  Public CloudKit side of book pictures: one `SharedBookPicture` record per
//  picture, with the image as a CKAsset. The book record itself carries only
//  picture METADATA (`BookPictureMetadata`, no bytes), so it stays far below the
//  ~1 MB record limit however many pictures a book has.
//
//  Record type `SharedBookPicture` (public database), record name
//  "BookPicture_<BOOK-UUID>_<PICTURE-UUID>":
//    bookID           String   book UUID (uppercase, as Swift prints it)   QUERYABLE
//    bookRecordName   String   record name of the SharedRecipeBook / Book record
//    pictureID        String   picture UUID (= metadata `id`)
//    kind             String   "cover" | "interior"
//    title            String
//    caption          String
//    order            Int64
//    sourcePage       String
//    linkedRecipeIDs  [String] recipe UUIDs shown in the picture
//    image            Asset    JPEG, ≤1600 px long side
//    imageHash        String   SHA256 of the stored picture bytes
//    sharedBy         String   CloudKit user record name of the publisher
//
//  See Docs/BOOK_CONTENT_AND_DELETE_GUARD.md, "Pictures as records".
//

import Foundation
import CloudKit
import SwiftData

// MARK: - Metadata carried by the book record

/// One picture as listed in a published book (`bookData.images` on
/// SharedRecipeBook, `imagesJSON` on Book). No bytes.
///
/// It keeps every key of `BookImage` (with `imageData` always empty) so builds
/// that decode `[BookImage]` from the same JSON still decode it.
nonisolated struct BookPictureMetadata: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String?
    var caption: String?
    /// Always empty (shape compatibility with `BookImage`)
    var imageData: Data
    var order: Int
    var dateAdded: Date
    /// "cover" | "interior" (nil = interior)
    var kind: String?
    var sourcePage: String?
    var linkedRecipeIDs: [UUID]?
    /// Name of the `SharedBookPicture` record holding the image; nil = not published
    var pictureRecordName: String?
    /// SHA256 of the picture bytes (receivers skip unchanged downloads)
    var imageHash: String?

    @MainActor
    init(image: BookImage, recordName: String?) {
        id = image.id
        title = image.title
        caption = image.caption
        imageData = Data()
        order = image.order
        dateAdded = image.dateAdded
        kind = image.kind
        sourcePage = image.sourcePage
        linkedRecipeIDs = image.linkedRecipeIDs
        pictureRecordName = recordName
        imageHash = BookPictureHash.sha256(image.imageData)
    }

    /// As a `BookImage` with the given bytes (empty = metadata only)
    @MainActor
    func bookImage(bytes: Data = Data()) -> BookImage {
        BookImage(id: id, title: title, caption: caption, imageData: bytes, order: order,
                  dateAdded: dateAdded, kind: kind, sourcePage: sourcePage,
                  linkedRecipeIDs: linkedRecipeIDs, sourceFile: nil)
    }
}

// MARK: - Publisher

@MainActor
struct BookPicturePublisher {

    nonisolated static let recordType = "SharedBookPicture"

    nonisolated enum Field {
        static let bookID = "bookID"
        static let bookRecordName = "bookRecordName"
        static let pictureID = "pictureID"
        static let kind = "kind"
        static let title = "title"
        static let caption = "caption"
        static let order = "order"
        static let sourcePage = "sourcePage"
        static let linkedRecipeIDs = "linkedRecipeIDs"
        static let image = "image"
        static let imageHash = "imageHash"
        static let sharedBy = "sharedBy"
    }

    let database: CKDatabase

    nonisolated static func recordName(bookID: UUID, pictureID: UUID) -> String {
        "BookPicture_\(bookID.uuidString)_\(pictureID.uuidString)"
    }

    // MARK: Publish

    /// Saves one `SharedBookPicture` record per picture (bytes uploaded only when
    /// they changed), deletes picture records of this book that are no longer
    /// listed, and returns the metadata to put in the book record.
    ///
    /// Never throws: a picture that could not be saved is listed without a
    /// `pictureRecordName` (and a failure is logged), so the book itself still shares.
    func publish(bookID: UUID,
                 bookRecordName: String?,
                 pictures: [BookImage],
                 sharedBy: String?,
                 previousRecordNames: [String] = []) async -> [BookPictureMetadata] {
        let withBytes = pictures.filter(\.hasBytes)
        let recordIDs = withBytes.map { CKRecord.ID(recordName: Self.recordName(bookID: bookID, pictureID: $0.id)) }

        // Existing records (only their hash) — unchanged pictures are not re-uploaded
        var existing: [CKRecord.ID: CKRecord] = [:]
        for batch in Self.batches(recordIDs, size: 100) {
            do {
                let results = try await database.records(for: batch, desiredKeys: [Field.imageHash])
                for (id, result) in results {
                    if case .success(let record) = result { existing[id] = record }
                }
            } catch {
                AppLog.warning("📷 Could not look up published pictures: \(error.localizedDescription)", category: .sharing)
            }
        }

        var toSave: [CKRecord] = []
        var tempFiles: [URL] = []
        defer { tempFiles.forEach { try? FileManager.default.removeItem(at: $0) } }

        for (image, recordID) in zip(withBytes, recordIDs) {
            let record = existing[recordID] ?? CKRecord(recordType: Self.recordType, recordID: recordID)
            record[Field.bookID] = bookID.uuidString
            record[Field.bookRecordName] = bookRecordName
            record[Field.pictureID] = image.id.uuidString
            record[Field.kind] = image.isCover ? BookImage.coverKind : BookImage.interiorKind
            record[Field.title] = image.title
            record[Field.caption] = image.caption
            record[Field.order] = image.order
            record[Field.sourcePage] = image.sourcePage
            let linked = (image.linkedRecipeIDs ?? []).map(\.uuidString)
            record[Field.linkedRecipeIDs] = linked.isEmpty ? nil : linked
            record[Field.sharedBy] = sharedBy

            let hash = BookPictureHash.sha256(image.imageData)
            if existing[recordID] == nil || (record[Field.imageHash] as? String) != hash {
                let upload = BookImageProcessing.publicUploadData(from: image.imageData)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("jpg")
                do {
                    try upload.write(to: url)
                    tempFiles.append(url)
                    record[Field.image] = CKAsset(fileURL: url)
                    record[Field.imageHash] = hash
                } catch {
                    AppLog.warning("📷 Could not stage picture \(image.id) for upload: \(error.localizedDescription)", category: .sharing)
                    continue
                }
            }
            toSave.append(record)
        }

        var published = Set<String>()
        for batch in Self.batches(toSave, size: 20) {
            do {
                let (saveResults, _) = try await database.modifyRecords(
                    saving: batch, deleting: [], savePolicy: .changedKeys, atomically: false)
                for (id, result) in saveResults {
                    switch result {
                    case .success: published.insert(id.recordName)
                    case .failure(let error):
                        AppLog.warning("📷 Picture record \(id.recordName) not saved: \(error.localizedDescription)", category: .sharing)
                    }
                }
            } catch {
                AppLog.warning("📷 Picture records not saved (is the SharedBookPicture record type deployed to this CloudKit environment?): \(error.localizedDescription)", category: .sharing)
            }
        }
        // A picture whose update failed but which was published before keeps its old record
        for id in existing.keys { published.insert(id.recordName) }

        // Stale pictures of this book: listed before (or found by query) but not any more
        let current = Set(recordIDs.map(\.recordName))
        var stale = Set(previousRecordNames)
        stale.formUnion(await publishedRecordNames(bookID: bookID))
        stale.subtract(current)
        if !stale.isEmpty { await deleteRecords(named: Array(stale)) }

        AppLog.info("📷 Published \(published.intersection(current).count)/\(withBytes.count) picture record(s) for book \(bookID); removed \(stale.count) stale", category: .sharing)

        return pictures.map { image in
            let name = Self.recordName(bookID: bookID, pictureID: image.id)
            return BookPictureMetadata(image: image, recordName: published.contains(name) ? name : nil)
        }
    }

    // MARK: Delete

    /// Deletes every picture record of a book: the names listed in its public
    /// record (if `bookRecordName` is given and still exists) plus any found by
    /// querying `bookID`. Best effort, never throws.
    func deleteAllPictures(bookID: UUID?, bookRecordName: String?) async {
        var names = Set<String>()
        var resolvedBookID = bookID
        if let bookRecordName {
            do {
                let record = try await database.record(for: CKRecord.ID(recordName: bookRecordName))
                names.formUnion(Self.pictureRecordNames(in: record))
                if resolvedBookID == nil { resolvedBookID = Self.bookID(in: record) }
            } catch {
                // Record already gone — fall back to the query
            }
        }
        if let resolvedBookID {
            names.formUnion(await publishedRecordNames(bookID: resolvedBookID))
        }
        guard !names.isEmpty else { return }
        await deleteRecords(named: Array(names))
        AppLog.info("📷 Deleted \(names.count) public picture record(s) of book \(resolvedBookID?.uuidString ?? bookRecordName ?? "?")", category: .sharing)
    }

    func deleteRecords(named names: [String]) async {
        for batch in Self.batches(names.map { CKRecord.ID(recordName: $0) }, size: 200) {
            do {
                _ = try await database.modifyRecords(saving: [], deleting: batch, savePolicy: .changedKeys, atomically: false)
            } catch {
                AppLog.warning("📷 Could not delete picture records: \(error.localizedDescription)", category: .sharing)
            }
        }
    }

    /// Names of `SharedBookPicture` records whose `bookID` is `bookID`.
    /// Needs `bookID` QUERYABLE in the CloudKit schema; returns [] when the query fails.
    func publishedRecordNames(bookID: UUID) async -> [String] {
        let query = CKQuery(recordType: Self.recordType,
                            predicate: NSPredicate(format: "%K == %@", Field.bookID, bookID.uuidString))
        var names: [String] = []
        do {
            var (results, cursor) = try await database.records(matching: query, desiredKeys: [], resultsLimit: 200)
            names += results.map { $0.0.recordName }
            while let next = cursor {
                (results, cursor) = try await database.records(continuingMatchFrom: next, desiredKeys: [], resultsLimit: 200)
                names += results.map { $0.0.recordName }
            }
        } catch {
            AppLog.debug("📷 Picture query by bookID unavailable: \(error.localizedDescription)", category: .sharing)
        }
        return names
    }

    // MARK: Download

    /// Downloads the bytes of the listed pictures, skipping those whose hash
    /// matches a picture already stored locally (`localHashes`: picture id → hash).
    func downloadPictures(_ metadata: [BookPictureMetadata], skipping localHashes: [UUID: String] = [:]) async -> [UUID: Data] {
        var idByName: [String: UUID] = [:]
        for meta in metadata {
            guard let name = meta.pictureRecordName else { continue }
            if let local = localHashes[meta.id], local == meta.imageHash { continue }
            idByName[name] = meta.id
        }
        var bytes: [UUID: Data] = [:]
        for batch in Self.batches(idByName.keys.map { CKRecord.ID(recordName: $0) }, size: 20) {
            do {
                let results = try await database.records(for: batch, desiredKeys: [Field.image])
                for (recordID, result) in results {
                    guard case .success(let record) = result,
                          let pictureID = idByName[recordID.recordName],
                          let asset = record[Field.image] as? CKAsset,
                          let url = asset.fileURL,
                          let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
                    bytes[pictureID] = data
                }
            } catch {
                AppLog.warning("📷 Could not download book pictures: \(error.localizedDescription)", category: .sharing)
            }
        }
        return bytes
    }

    // MARK: Helpers

    nonisolated private struct NamesHolder: Decodable {
        struct Entry: Decodable { let pictureRecordName: String? }
        let images: [Entry]?
        let id: UUID?
    }

    /// Picture record names listed in a SharedRecipeBook (`bookData.images`) or Book (`imagesJSON`) record
    nonisolated static func pictureRecordNames(in record: CKRecord) -> [String] {
        var names: [String] = []
        if let json = record["bookData"] as? String,
           let holder = try? JSONDecoder().decode(NamesHolder.self, from: Data(json.utf8)) {
            names += (holder.images ?? []).compactMap(\.pictureRecordName)
        }
        if let json = record["imagesJSON"] as? String,
           let entries = try? JSONDecoder().decode([NamesHolder.Entry].self, from: Data(json.utf8)) {
            names += entries.compactMap(\.pictureRecordName)
        }
        return names
    }

    /// Book id stored in a SharedRecipeBook (`bookData.id`) or Book (`id`) record
    nonisolated static func bookID(in record: CKRecord) -> UUID? {
        if let json = record["bookData"] as? String,
           let holder = try? JSONDecoder().decode(NamesHolder.self, from: Data(json.utf8)),
           let id = holder.id {
            return id
        }
        return (record["id"] as? String).flatMap(UUID.init(uuidString:))
    }

    nonisolated static func batches<T>(_ items: [T], size: Int) -> [[T]] {
        stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }
}

// MARK: - Receiving

extension BookPictureStore {

    /// Makes the local rows of `bookID` match a published picture list.
    /// `downloaded` holds new bytes; a listed picture without new bytes keeps its
    /// stored bytes (unchanged), or is skipped when there are none.
    /// - Returns: the pictures now stored (metadata; bytes only where downloaded)
    @discardableResult
    static func applyPublished(bookID: UUID,
                               metadata: [BookPictureMetadata],
                               downloaded: [UUID: Data],
                               in context: ModelContext) -> [BookImage] {
        guard isAvailable(in: context) else { return [] }
        let stored = Set(fetch(bookID: bookID, in: context).filter { $0.imageData != nil }.compactMap(\.id))
        let images = metadata.sorted { $0.order < $1.order }.compactMap { meta -> BookImage? in
            let bytes = downloaded[meta.id] ?? Data()
            guard !bytes.isEmpty || stored.contains(meta.id) else { return nil }
            return meta.bookImage(bytes: bytes)
        }
        replace(bookID: bookID, with: images, in: context)
        return images
    }
}
