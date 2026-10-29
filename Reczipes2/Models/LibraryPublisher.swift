//
//  LibraryPublisher.swift
//  Reczipes2
//
//  Δ-163 — operator ruling 2026-10-29: "Every recipe and every book and every
//  meal will be shared to everyone's app always. Only if recipes are deleted
//  by some user - those should stay on other user's systems with the badge
//  User Deleted."
//
//  So there is no share / unshare any more. A publish pass, run with the
//  auto-sync, makes the public database match this person's library:
//  - anything not yet public is published;
//  - anything edited since it was published is refreshed in place;
//  - nothing is ever removed. A deletion the owner makes is recorded as a
//    mark on the public record (OwnerDeletedStore queues it until it lands).
//
//  The pass decides from what is actually in the public database (the owner's
//  own records, read in full), not from local tracking rows, which arrive late
//  on a fresh device. A deletion is never inferred from something being absent.
//

import Foundation
import CloudKit
import SwiftData

extension CloudKitSharingService {

    /// The owner's own public records of one type.
    struct OwnPublicIndex {
        /// Newest live (not deleted) record per item id.
        var live: [UUID: (recordName: String, sharedDate: Date)] = [:]
        /// Every live record per item id (an item can have several).
        var liveRecords: [UUID: [CKRecord]] = [:]
        /// Newest deleted mark per item id.
        var marks: [UUID: PublicTombstones.Mark] = [:]

        var deleted: [UUID: PublicTombstones.Mark] {
            PublicTombstones.deletedIDs(newestLive: live.mapValues(\.sharedDate), marks: marks)
        }
    }

    /// The fields every payload (recipe, book, meal) shares.
    private struct PayloadHeader: Decodable {
        let id: UUID
        let sharedDate: Date?
        let deletedByOwner: Bool?
        let deletedDate: Date?
        let replacedByID: UUID?
    }

    static func dataKey(for kind: PublicItemKind) -> String {
        switch kind {
        case .recipe: return "recipeData"
        case .book: return "bookData"
        case .meal: return "mealData"
        }
    }

    static func recordType(for kind: PublicItemKind) -> String {
        switch kind {
        case .recipe: return CloudKitRecordType.sharedRecipe
        case .book: return CloudKitRecordType.sharedRecipeBook
        case .meal: return CloudKitRecordType.sharedMeal
        }
    }

    /// Reads all of this user's public records of one kind (text only).
    /// Returns nil when the read did not finish or a record could not be read:
    /// an incomplete picture must not drive publishing.
    func readOwnPublicIndex(_ kind: PublicItemKind) async -> OwnPublicIndex? {
        guard let userID = currentUserID else { return nil }
        let dataKey = Self.dataKey(for: kind)
        let query = CKQuery(recordType: Self.recordType(for: kind),
                            predicate: NSPredicate(format: "sharedBy == %@", userID))
        let keys: [CKRecord.FieldKey] = [dataKey, "sharedDate", "sharedBy"]
        var index = OwnPublicIndex()
        var cursor: CKQueryOperation.Cursor?
        do {
            repeat {
                let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    page = try await publicDatabase.records(continuingMatchFrom: cursor, desiredKeys: keys, resultsLimit: 200)
                } else {
                    page = try await publicDatabase.records(matching: query, desiredKeys: keys, resultsLimit: 200)
                }
                for (_, result) in page.matchResults {
                    guard case .success(let record) = result else {
                        AppLog.warning("📤 Own \(kind.rawValue) index: a record could not be read — pass skipped", category: .sharing)
                        return nil
                    }
                    guard let json = (record[dataKey] as? String)?.data(using: .utf8),
                          let header = try? JSONDecoder().decode(PayloadHeader.self, from: json) else {
                        continue // not one of ours in a form we understand; never touched
                    }
                    let shared = (record["sharedDate"] as? Date) ?? header.sharedDate ?? .distantPast
                    if header.deletedByOwner == true {
                        PublicTombstones.merge(.init(deletedDate: header.deletedDate ?? shared, replacedByID: header.replacedByID),
                                               into: &index.marks, id: header.id)
                    } else {
                        index.liveRecords[header.id, default: []].append(record)
                        if let seen = index.live[header.id], seen.sharedDate >= shared { continue }
                        index.live[header.id] = (record.recordID.recordName, shared)
                    }
                }
                cursor = page.queryCursor
            } while cursor != nil
        } catch {
            AppLog.warning("📤 Own \(kind.rawValue) index read stopped: \(error.localizedDescription)", category: .sharing)
            return nil
        }
        return index
    }

    // MARK: - Deleting = marking the public copy

    /// Call when the owner deletes a recipe, book or meal from their library.
    /// The public copy is marked deleted (kept for everyone who has it), never removed.
    /// Queued first, so a delete made offline still lands on the next pass.
    func ownerDeleted(_ kind: PublicItemKind, id: UUID?, replacedBy: UUID? = nil, modelContext: ModelContext) {
        guard let id else { return }
        OwnerDeletedStore.shared.enqueueTombstone(kind, id, replacedByID: replacedBy)
        // The owner's own Shared list should not keep showing it.
        dropOwnCommunityCopy(kind, id: id, modelContext: modelContext)
        Task { @MainActor in
            await self.flushPendingTombstones(modelContext: modelContext)
        }
    }

    private func dropOwnCommunityCopy(_ kind: PublicItemKind, id: UUID, modelContext: ModelContext) {
        guard let me = currentUserID else { return }
        switch kind {
        case .recipe:
            let rows = (try? modelContext.fetch(FetchDescriptor<CachedSharedRecipe>(predicate: #Predicate { $0.id == id }))) ?? []
            for row in rows where row.sharedByUserID == me { modelContext.delete(row) }
        case .meal:
            let rows = (try? modelContext.fetch(FetchDescriptor<CachedSharedMeal>(predicate: #Predicate { $0.id == id }))) ?? []
            for row in rows where row.sharedByUserID == me { modelContext.delete(row) }
        case .book:
            break // the owner's own books are never in the community list
        }
        try? modelContext.save()
    }

    /// Marks every queued deletion on the public records. An item with no
    /// public record needs nothing more. Anything that fails stays queued.
    func flushPendingTombstones(modelContext: ModelContext) async {
        let store = OwnerDeletedStore.shared
        guard !store.pending.isEmpty, isCloudKitAvailable, currentUserID != nil else { return }
        for kind in PublicItemKind.allCases {
            let items = store.pending.filter { $0.kind == kind }
            guard !items.isEmpty, let index = await readOwnPublicIndex(kind) else { continue }
            for item in items {
                let records = index.liveRecords[item.id] ?? []
                var allMarked = true
                if records.isEmpty && index.marks[item.id] == nil {
                    // Never published (e.g. Undo Save). Leave a small deleted record
                    // anyway: another of this person's devices that hasn't received
                    // the delete yet would otherwise publish it, live, for good.
                    do {
                        try await saveDeletedStub(kind, id: item.id, replacedBy: item.replacedByID)
                    } catch {
                        allMarked = false
                        AppLog.warning("📤 Could not record deletion of unpublished \(kind.rawValue) \(item.id): \(error.localizedDescription)", category: .sharing)
                    }
                }
                for record in records {
                    do {
                        try await markRecordDeleted(record, kind: kind, replacedBy: item.replacedByID)
                    } catch {
                        allMarked = false
                        AppLog.warning("📤 Could not mark public \(kind.rawValue) \(item.id) deleted: \(error.localizedDescription)", category: .sharing)
                    }
                }
                guard allMarked else { continue }
                store.completeTombstone(kind, item.id)
                removeTracking(kind, id: item.id, modelContext: modelContext)
                AppLog.info("📤 Public \(kind.rawValue) \(item.id) marked deleted (\(records.count) record(s)); kept for everyone who has it", category: .sharing)
            }
        }
    }

    /// Adds the deleted mark to the record's JSON payload; every other field,
    /// photo and the record itself are left as they are.
    private func markRecordDeleted(_ record: CKRecord, kind: PublicItemKind, replacedBy: UUID?) async throws {
        let key = Self.dataKey(for: kind)
        guard let text = record[key] as? String,
              let data = text.data(using: .utf8),
              var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SharingError.invalidData
        }
        object["deletedByOwner"] = true
        // JSONEncoder's default Date format: seconds since 2001-01-01.
        object["deletedDate"] = Date().timeIntervalSinceReferenceDate
        if let replacedBy { object["replacedByID"] = replacedBy.uuidString }
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        record[key] = String(data: updated, encoding: .utf8)
        _ = try await publicDatabase.save(record)
    }

    /// A minimal, valid public record that only says "deleted" (decodes in every
    /// build and on the web; receivers that never had the item skip it).
    private func saveDeletedStub(_ kind: PublicItemKind, id: UUID, replacedBy: UUID?) async throws {
        guard let userID = currentUserID else { throw SharingError.notAuthenticated }
        let now = Date()
        let record = CKRecord(recordType: Self.recordType(for: kind))
        let encoder = JSONEncoder()
        let payload: Data
        let label: String
        switch kind {
        case .recipe:
            label = "Deleted recipe"
            var stub = CloudKitRecipe(id: id, title: label, headerNotes: nil, yield: nil,
                                      ingredientSections: [], instructionSections: [], notes: [],
                                      reference: nil, imageName: nil, additionalImageNames: nil,
                                      sharedByUserID: userID, sharedByUserName: currentUserName, sharedDate: now)
            stub.deletedByOwner = true
            stub.deletedDate = now
            stub.replacedByID = replacedBy
            payload = try encoder.encode(stub)
            record["title"] = label as CKRecordValue
        case .book:
            label = "Deleted book"
            var stub = CloudKitRecipeBook(id: id, name: label, bookDescription: nil, coverImageName: nil,
                                          recipeIDs: [], color: nil, sharedByUserID: userID,
                                          sharedByUserName: currentUserName, sharedDate: now)
            stub.deletedByOwner = true
            stub.deletedDate = now
            payload = try encoder.encode(stub)
            record["name"] = label as CKRecordValue
            record["recipePreviews"] = "[]" as CKRecordValue
        case .meal:
            label = "Deleted meal"
            var stub = CloudKitMeal(id: id, name: label, mealDescription: nil, courses: [], notes: nil,
                                    sharedByUserID: userID, sharedByUserName: currentUserName, sharedDate: now)
            stub.deletedByOwner = true
            stub.deletedDate = now
            payload = try encoder.encode(stub)
            record["name"] = label as CKRecordValue
        }
        record[Self.dataKey(for: kind)] = String(data: payload, encoding: .utf8)
        record["sharedBy"] = userID as CKRecordValue
        record["sharedByName"] = (currentUserName ?? "Anonymous") as CKRecordValue
        record["sharedDate"] = now as CKRecordValue
        _ = try await publicDatabase.save(record)
    }

    private func removeTracking(_ kind: PublicItemKind, id: UUID, modelContext: ModelContext) {
        switch kind {
        case .recipe:
            for row in (try? modelContext.fetch(FetchDescriptor<SharedRecipe>(predicate: #Predicate { $0.recipeID == id }))) ?? [] {
                modelContext.delete(row)
            }
        case .book:
            for row in (try? modelContext.fetch(FetchDescriptor<SharedRecipeBook>(predicate: #Predicate { $0.bookID == id }))) ?? [] {
                modelContext.delete(row)
            }
        case .meal:
            for row in (try? modelContext.fetch(FetchDescriptor<SharedMeal>(predicate: #Predicate { $0.mealID == id }))) ?? [] {
                modelContext.delete(row)
            }
        }
        try? modelContext.save()
    }

    // MARK: - Publish pass

    /// Publishes everything in this person's library that the public database
    /// doesn't have yet, and refreshes what was edited since. Never removes.
    /// Runs at most every 10 minutes unless `force`.
    func publishEverything(modelContext: ModelContext, force: Bool = false) async {
        if let running = publishTask { return await running.value }
        if !force, let last = lastPublishPass, Date().timeIntervalSince(last) < 600 { return }
        guard isCloudKitAvailable, currentUserID != nil else { return }
        let task = Task { @MainActor in
            await self.performPublishPass(modelContext: modelContext)
        }
        publishTask = task
        await task.value
        publishTask = nil
        lastPublishPass = Date()
    }

    private func performPublishPass(modelContext: ModelContext) async {
        let status = LibrarySyncStatus.shared
        await flushPendingTombstones(modelContext: modelContext)

        var work: [(label: String, run: @MainActor () async throws -> Void)] = []

        // Recipes
        if let index = await readOwnPublicIndex(.recipe) {
            let deleted = index.deleted
            let tracked = Set(((try? modelContext.fetch(FetchDescriptor<SharedRecipe>())) ?? [])
                .filter { $0.isActive }.compactMap(\.recipeID))
            let userID = currentUserID
            for recipe in (try? modelContext.fetch(FetchDescriptor<RecipeX>())) ?? [] {
                guard let id = recipe.id, !OwnerDeletedStore.shared.isPendingTombstone(.recipe, id) else { continue }
                let live = deleted[id] == nil ? index.live[id] : nil
                // Tracking rows let a book share find its recipes' records instead of
                // sharing them again; restore any that a fresh device hasn't got yet.
                if let live, !tracked.contains(id), let userID {
                    modelContext.insert(SharedRecipe(recipeID: id, cloudRecordID: live.recordName,
                                                     sharedByUserID: userID, sharedByUserName: currentUserName,
                                                     recipeTitle: recipe.safeTitle, recipeImageName: recipe.imageName))
                }
                switch PublicTombstones.publishAction(localModified: recipe.modificationDate, live: live,
                                                      deletedDate: deleted[id]?.deletedDate) {
                case .none: break
                case .publishNew:
                    work.append((recipe.safeTitle, { [weak self] in
                        guard let self, !recipe.isDeleted else { return }
                        _ = try await self.shareRecipe(recipe, modelContext: modelContext, refreshExisting: true, scanForDuplicates: false)
                    }))
                case .refresh(let name):
                    work.append((recipe.safeTitle, { [weak self] in
                        guard let self, !recipe.isDeleted else { return }
                        _ = try await self.shareRecipe(recipe, modelContext: modelContext, refreshExisting: true,
                                                       knownRecordName: name, scanForDuplicates: false)
                    }))
                }
            }
            try? modelContext.save()
        }

        // Books (this person's own only, never a community copy)
        if let index = await readOwnPublicIndex(.book) {
            let deleted = index.deleted
            let othersBookIDs = Set(((try? modelContext.fetch(FetchDescriptor<SharedRecipeBook>())) ?? [])
                .filter { $0.sharedByUserID != nil && $0.sharedByUserID != currentUserID }.compactMap(\.bookID))
            for book in (try? modelContext.fetch(FetchDescriptor<Book>())) ?? [] {
                guard let id = book.id, book.name != nil, book.recipeIDs != nil,
                      Book.isOwnedByCurrentUser(ownerUserID: book.ownerUserID, currentUserID: currentUserID),
                      book.isImported != true, !othersBookIDs.contains(id),
                      !OwnerDeletedStore.shared.isPendingTombstone(.book, id) else { continue }
                // Picture changes go through setImages → markModified, so dateModified covers them.
                let modified = book.dateModified ?? book.dateCreated ?? .distantPast
                let live = deleted[id] == nil ? index.live[id] : nil
                switch PublicTombstones.publishAction(localModified: modified, live: live, deletedDate: deleted[id]?.deletedDate) {
                case .none: break
                case .publishNew:
                    work.append((book.name ?? "Book", { [weak self] in
                        guard let self, !book.isDeleted else { return }
                        _ = try await self.shareRecipeBook(book, modelContext: modelContext, refreshExisting: true)
                    }))
                case .refresh(let name):
                    work.append((book.name ?? "Book", { [weak self] in
                        guard let self, !book.isDeleted else { return }
                        _ = try await self.shareRecipeBook(book, modelContext: modelContext, refreshExisting: true, knownRecordName: name)
                    }))
                }
            }
        }

        // Meals
        if let index = await readOwnPublicIndex(.meal) {
            let deleted = index.deleted
            for meal in (try? modelContext.fetch(FetchDescriptor<Meal>())) ?? [] {
                // Built-in presets are seeded on every device; publishing them would
                // put the same preset meals in the library once per person.
                guard let id = meal.id, meal.isPreset != true,
                      !OwnerDeletedStore.shared.isPendingTombstone(.meal, id) else { continue }
                let modified = meal.dateModified ?? meal.dateCreated ?? .distantPast
                let live = deleted[id] == nil ? index.live[id] : nil
                switch PublicTombstones.publishAction(localModified: modified, live: live, deletedDate: deleted[id]?.deletedDate) {
                case .none: break
                case .publishNew:
                    work.append((meal.displayName, { [weak self] in
                        guard let self, !meal.isDeleted else { return }
                        _ = try await self.shareMeal(meal, modelContext: modelContext, refreshExisting: true)
                    }))
                case .refresh(let name):
                    work.append((meal.displayName, { [weak self] in
                        guard let self, !meal.isDeleted else { return }
                        _ = try await self.shareMeal(meal, modelContext: modelContext, refreshExisting: true, knownRecordName: name)
                    }))
                }
            }
        }

        guard !work.isEmpty else {
            AppLog.info("📤 Publish pass: everything is already public", category: .sharing)
            return
        }
        AppLog.info("📤 Publish pass: \(work.count) item(s) to publish or refresh", category: .sharing)
        var failures = 0
        for (i, item) in work.enumerated() {
            status.publishProgress(done: i, total: work.count)
            do {
                try await item.run()
            } catch {
                failures += 1
                AppLog.warning("📤 Could not publish '\(item.label)': \(error.localizedDescription)", category: .sharing)
            }
        }
        status.publishFinished()
        AppLog.info("📤 Publish pass done: \(work.count - failures) published, \(failures) to retry", category: .sharing)
    }
}
