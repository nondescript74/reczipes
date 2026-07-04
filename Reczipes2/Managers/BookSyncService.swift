//
//  BookSyncService.swift
//  Reczipes2
//
//  Created on 1/26/26.
//
//  Service for syncing Book models with CloudKit Public Database

import Foundation
import CloudKit
import SwiftData
import OSLog
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Combine

/// Manages CloudKit sync for Book models
@MainActor
class BookSyncService: ObservableObject {
    
    // MARK: - Properties
    
    private let modelContext: ModelContext
    private let container: CKContainer
    private let publicDatabase: CKDatabase
    private let logger = Logger(subsystem: "com.reczipes2", category: "BookSync")
    
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: BookSyncError?
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext, containerIdentifier: String = "iCloud.com.headydiscy.reczipes") {
        self.modelContext = modelContext
        self.container = CKContainer(identifier: containerIdentifier)
        self.publicDatabase = container.publicCloudDatabase
    }
    
    // MARK: - Account Status
    
    /// Check if user is signed in to iCloud
    func checkAccountStatus() async throws -> CKAccountStatus {
        return try await container.accountStatus()
    }
    
    /// Verify CloudKit availability
    func verifyCloudKitAvailability() async -> Bool {
        do {
            let status = try await checkAccountStatus()
            return status == .available
        } catch {
            logger.error("CloudKit not available: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Upload Books
    
    /// Sync a single book to CloudKit
    func syncBook(_ book: Book, configuration: BookSharingConfiguration = .public) async throws -> String {
        guard await verifyCloudKitAvailability() else {
            throw BookSyncError.cloudKitUnavailable
        }
        
        logger.info("Syncing book: \(book.displayName)")
        
        // Create or update CloudKit record
        let recordID: CKRecord.ID
        if let existingRecordID = book.cloudRecordID {
            recordID = CKRecord.ID(recordName: existingRecordID)
        } else {
            recordID = CKRecord.ID(recordName: (book.id ?? UUID()).uuidString)
        }
        
        let record = CKRecord(recordType: CloudKitRecordType.book, recordID: recordID)
        
        // Set basic fields
        record["id"] = (book.id ?? UUID()).uuidString
        record["name"] = book.name ?? ""
        record["bookDescription"] = book.bookDescription
        record["color"] = book.color
        record["category"] = book.category
        record["cuisine"] = book.cuisine
        record["privacyLevel"] = configuration.privacyLevel.rawValue
        record["version"] = book.version ?? 1
        record["dateCreated"] = book.dateCreated ?? Date()
        record["dateModified"] = book.dateModified ?? Date()
        
        // Set user attribution
        let ownerUserID: String
        if let existingOwnerID = book.ownerUserID {
            ownerUserID = existingOwnerID
        } else {
            ownerUserID = await getCurrentUserID()
        }
        record["ownerUserID"] = ownerUserID
        
        let ownerDisplayName: String
        if let existingDisplayName = book.ownerDisplayName {
            ownerDisplayName = existingDisplayName
        } else {
            ownerDisplayName = await getCurrentUserDisplayName()
        }
        record["ownerDisplayName"] = ownerDisplayName
        
        record["sharedDate"] = book.sharedDate ?? Date()
        
        // Set recipe IDs
        let recipeIDStrings = (book.recipeIDs ?? []).map { $0.uuidString }
        record["recipeIDs"] = recipeIDStrings
        
        // Upload cover image if present
        if let coverImageData = book.coverImageData, configuration.includeHighResCover {
            let asset = try createCKAsset(from: coverImageData, quality: configuration.imageQuality)
            record["coverImage"] = asset
        }
        
        // Encode and set content as JSON strings
        try setContentFields(on: record, from: book, configuration: configuration)
        
        // Upload to CloudKit
        do {
            let savedRecord = try await publicDatabase.save(record)
            
            // Update local book with CloudKit metadata
            book.cloudRecordID = savedRecord.recordID.recordName
            book.lastSyncedToCloud = Date()
            book.needsCloudSync = false
            book.syncRetryCount = 0
            book.lastSyncError = nil
            
            try modelContext.save()
            
            logger.info("Successfully synced book: \(book.displayName)")
            return savedRecord.recordID.recordName
            
        } catch let error as CKError {
            throw handleCKError(error)
        }
    }
    
    /// Sync multiple books
    func syncBooks(_ books: [Book], configuration: BookSharingConfiguration = .public) async -> BookSyncResult {
        var successCount = 0
        var errors: [BookSyncError] = []
        
        for book in books {
            do {
                _ = try await syncBook(book, configuration: configuration)
                successCount += 1
            } catch let error as BookSyncError {
                errors.append(error)
                logger.error("Failed to sync book \(book.displayName): \(error.localizedDescription)")
            } catch {
                errors.append(.uploadFailed(error))
            }
        }
        
        if errors.isEmpty {
            return .success(bookID: books.first?.id ?? UUID(), recordID: books.first?.cloudRecordID ?? "")
        } else if successCount > 0 {
            return .partialSuccess(synced: successCount, failed: errors.count, errors: errors)
        } else {
            return .failure(error: errors.first ?? .uploadFailed(NSError(domain: "BookSync", code: -1)))
        }
    }
    
    /// Sync all books that need syncing
    func syncAllPendingBooks(configuration: BookSharingConfiguration = .public) async throws {
        isSyncing = true
        defer { isSyncing = false }
        
        // Fetch books that need sync
        let predicate = #Predicate<Book> { book in
            book.needsCloudSync == true && book.isShared == true
        }
        let descriptor = FetchDescriptor<Book>(predicate: predicate)
        let booksToSync = try modelContext.fetch(descriptor)
        
        logger.info("Syncing \(booksToSync.count) books")
        
        let result = await syncBooks(booksToSync, configuration: configuration)
        
        switch result {
        case .success:
            lastSyncDate = Date()
            syncError = nil
        case .failure(let error):
            syncError = error
        case .partialSuccess(let synced, let failed, let errors):
            logger.warning("Partial sync: \(synced) succeeded, \(failed) failed")
            syncError = errors.first
        }
    }
    
    // MARK: - Download Books
    
    /// Fetch all shared books from CloudKit
    func fetchSharedBooks(limit: Int = 100) async throws -> [CloudKitBook] {
        guard await verifyCloudKitAvailability() else {
            throw BookSyncError.cloudKitUnavailable
        }
        
        let query = CKQuery(recordType: CloudKitRecordType.book, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "dateModified", ascending: false)]
        
        var allBooks: [CloudKitBook] = []
        var cursor: CKQueryOperation.Cursor?
        
        repeat {
            let (results, nextCursor) = try await publicDatabase.records(
                matching: query,
                resultsLimit: limit
            )
            
            for (_, result) in results {
                switch result {
                case .success(let record):
                    if let book = try? decodeBookFromRecord(record) {
                        allBooks.append(book)
                    }
                case .failure(let error):
                    logger.error("Failed to fetch record: \(error.localizedDescription)")
                }
            }
            
            cursor = nextCursor
        } while cursor != nil
        
        logger.info("Fetched \(allBooks.count) shared books")
        return allBooks
    }
    
    /// Download a specific book
    func downloadBook(recordID: String, options: BookDownloadOptions = .full) async throws -> Book {
        guard await verifyCloudKitAvailability() else {
            throw BookSyncError.cloudKitUnavailable
        }
        
        let ckRecordID = CKRecord.ID(recordName: recordID)
        let record = try await publicDatabase.record(for: ckRecordID)
        
        let cloudBook = try decodeBookFromRecord(record)
        
        // Create local Book
        let book = Book(
            id: cloudBook.id,
            name: cloudBook.name,
            bookDescription: cloudBook.bookDescription,
            color: cloudBook.color,
            recipeIDs: cloudBook.recipeIDs,
            dateCreated: cloudBook.dateCreated,
            dateModified: cloudBook.dateModified,
            version: cloudBook.version,
            cloudRecordID: recordID,
            needsCloudSync: false,
            isShared: false, // Imported book, user doesn't share it
            ownerUserID: cloudBook.ownerUserID,
            ownerDisplayName: cloudBook.ownerDisplayName,
            category: cloudBook.category,
            cuisine: cloudBook.cuisine,
            sharedDate: cloudBook.sharedDate,
            isImported: true,
            originalOwnerUserID: cloudBook.ownerUserID,
            originalOwnerDisplayName: cloudBook.ownerDisplayName
        )
        
        // Download cover image if present
        if let coverAsset = record["coverImage"] as? CKAsset,
           let coverURL = coverAsset.fileURL,
           let coverData = try? Data(contentsOf: coverURL) {
            book.coverImageData = coverData
        }
        
        // Set content data
        book.setRecipePreviews(cloudBook.recipePreviews)
        
        if options.downloadAllContent {
            book.setImages(cloudBook.images)
            book.setInstructions(cloudBook.instructions)
            book.setGlossary(cloudBook.glossary)
            book.setCustomContent(cloudBook.customContent)
            book.setTableOfContents(cloudBook.tableOfContents)
        }
        
        if options.createLocalCopy {
            modelContext.insert(book)
            try modelContext.save()
        }
        
        logger.info("Downloaded book: \(book.displayName)")
        return book
    }
    
    // MARK: - Delete Books
    
    /// Delete book from CloudKit
    func deleteBookFromCloud(_ book: Book) async throws {
        guard let recordID = book.cloudRecordID else {
            throw BookSyncError.bookNotFound
        }
        
        let ckRecordID = CKRecord.ID(recordName: recordID)
        try await publicDatabase.deleteRecord(withID: ckRecordID)
        
        // Update local book
        book.cloudRecordID = nil
        book.isShared = false
        book.needsCloudSync = false
        try modelContext.save()
        
        logger.info("Deleted book from CloudKit: \(book.displayName)")
    }
    
    // MARK: - Search Books
    
    /// Search for books by name
    func searchBooks(query: String, limit: Int = 50) async throws -> [CloudKitBook] {
        guard await verifyCloudKitAvailability() else {
            throw BookSyncError.cloudKitUnavailable
        }
        
        let predicate = NSPredicate(format: "name CONTAINS[cd] %@", query)
        let ckQuery = CKQuery(recordType: CloudKitRecordType.book, predicate: predicate)
        ckQuery.sortDescriptors = [NSSortDescriptor(key: "dateModified", ascending: false)]
        
        let (results, _) = try await publicDatabase.records(matching: ckQuery, resultsLimit: limit)
        
        var books: [CloudKitBook] = []
        for (_, result) in results {
            if case .success(let record) = result,
               let book = try? decodeBookFromRecord(record) {
                books.append(book)
            }
        }
        
        logger.info("Found \(books.count) books matching '\(query)'")
        return books
    }
    
    /// Search books by category
    func searchBooksByCategory(_ category: String, limit: Int = 50) async throws -> [CloudKitBook] {
        guard await verifyCloudKitAvailability() else {
            throw BookSyncError.cloudKitUnavailable
        }
        
        let predicate = NSPredicate(format: "category == %@", category)
        let ckQuery = CKQuery(recordType: CloudKitRecordType.book, predicate: predicate)
        
        let (results, _) = try await publicDatabase.records(matching: ckQuery, resultsLimit: limit)
        
        var books: [CloudKitBook] = []
        for (_, result) in results {
            if case .success(let record) = result,
               let book = try? decodeBookFromRecord(record) {
                books.append(book)
            }
        }
        
        return books
    }
    
    // MARK: - Helper Methods
    
    /// Get current user's CloudKit ID
    private func getCurrentUserID() async -> String {
        do {
            let userRecordID = try await container.userRecordID()
            return userRecordID.recordName
        } catch {
            logger.error("Failed to get user ID: \(error.localizedDescription)")
            return ""
        }
    }
    
    /// Get current user's display name
    private func getCurrentUserDisplayName() async -> String {
        do {
            let userRecordID = try await container.userRecordID()
            let userRecord = try await container.publicCloudDatabase.record(for: userRecordID)
            
            // Try to get display name from user record
            if let firstName = userRecord["firstName"] as? String,
               let lastName = userRecord["lastName"] as? String {
                return "\(firstName) \(lastName)"
            } else if let firstName = userRecord["firstName"] as? String {
                return firstName
            }
            
            return "Unknown User"
        } catch {
            logger.error("Failed to get user display name: \(error.localizedDescription)")
            return "Unknown User"
        }
    }
    
    /// Create CKAsset from image data
    private func createCKAsset(from imageData: Data, quality: Double = 0.8) throws -> CKAsset {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        // Use centralized compression utility for book covers
        let compressedData: Data
        if let uiImage = PlatformImage(data: imageData),
           let compressed = ImageCompressionUtility.compressForBookCover(uiImage) {
            compressedData = compressed
        } else {
            compressedData = imageData
        }

        try compressedData.write(to: tempURL)
        return CKAsset(fileURL: tempURL)
    }
    
    /// Set content fields on CloudKit record
    private func setContentFields(
        on record: CKRecord,
        from book: Book,
        configuration: BookSharingConfiguration
    ) throws {
        // Recipe previews
        if let data = book.recipePreviewsData,
           let jsonString = String(data: data, encoding: .utf8) {
            record["recipePreviewsJSON"] = jsonString
        }
        
        // Images
        if configuration.includeContentImages,
           let data = book.imagesData,
           let jsonString = String(data: data, encoding: .utf8) {
            record["imagesJSON"] = jsonString
        }
        
        // Instructions
        if let data = book.instructionsData,
           let jsonString = String(data: data, encoding: .utf8) {
            record["instructionsJSON"] = jsonString
        }
        
        // Glossary
        if let data = book.glossaryData,
           let jsonString = String(data: data, encoding: .utf8) {
            record["glossaryJSON"] = jsonString
        }
        
        // Custom content
        if let data = book.customContentData,
           let jsonString = String(data: data, encoding: .utf8) {
            record["customContentJSON"] = jsonString
        }
        
        // Table of contents
        if let data = book.tableOfContentsData,
           let jsonString = String(data: data, encoding: .utf8) {
            record["tableOfContentsJSON"] = jsonString
        }
        
        // Tags
        let tags = book.tags
        if !tags.isEmpty {
            record["tags"] = tags
        }
    }
    
    /// Decode Book from CloudKit record
    private func decodeBookFromRecord(_ record: CKRecord) throws -> CloudKitBook {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = record["name"] as? String else {
            throw BookSyncError.invalidData
        }
        
        // Decode JSON fields
        let recipePreviews = decodeJSON([BookRecipePreview].self, from: record["recipePreviewsJSON"] as? String)
        let images = decodeJSON([BookImage].self, from: record["imagesJSON"] as? String)
        let instructions = decodeJSON([BookInstruction].self, from: record["instructionsJSON"] as? String)
        let glossary = decodeJSON([BookGlossaryEntry].self, from: record["glossaryJSON"] as? String)
        let customContent = decodeJSON([BookContentItem].self, from: record["customContentJSON"] as? String)
        let tableOfContents = decodeJSON([BookSection].self, from: record["tableOfContentsJSON"] as? String)
        
        // Parse recipe IDs
        let recipeIDStrings = record["recipeIDs"] as? [String] ?? []
        let recipeIDs = recipeIDStrings.compactMap { UUID(uuidString: $0) }
        
        // Get tags
        let tags = record["tags"] as? [String] ?? []
        
        return CloudKitBook(
            id: id,
            name: name,
            bookDescription: record["bookDescription"] as? String,
            color: record["color"] as? String,
            recipeIDs: recipeIDs,
            recipePreviews: recipePreviews,
            images: images,
            instructions: instructions,
            glossary: glossary,
            customContent: customContent,
            tableOfContents: tableOfContents,
            category: record["category"] as? String,
            cuisine: record["cuisine"] as? String,
            tags: tags,
            version: record["version"] as? Int ?? 1,
            dateCreated: record["dateCreated"] as? Date ?? Date(),
            dateModified: record["dateModified"] as? Date ?? Date(),
            ownerUserID: record["ownerUserID"] as? String ?? "",
            ownerDisplayName: record["ownerDisplayName"] as? String,
            sharedDate: record["sharedDate"] as? Date ?? Date(),
            privacyLevel: record["privacyLevel"] as? String ?? "public"
        )
    }
    
    /// Decode JSON string to type
    private func decodeJSON<T: Decodable>(_ type: T.Type, from jsonString: String?) -> T {
        guard let jsonString = jsonString,
              let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(type, from: data) else {
            // Return empty array/default value for array types
            if T.self is [Any].Type {
                return [] as! T
            }
            fatalError("Cannot create default value for \(T.self)")
        }
        return decoded
    }
    
    /// Handle CloudKit errors
    private func handleCKError(_ error: CKError) -> BookSyncError {
        switch error.code {
        case .notAuthenticated:
            return .notAuthenticated
        case .networkUnavailable, .networkFailure:
            return .networkError
        case .quotaExceeded:
            return .quotaExceeded
        case .serverRecordChanged:
            // Handle conflict - could be more sophisticated
            return .uploadFailed(error)
        default:
            return .uploadFailed(error)
        }
    }
}

// MARK: - Background Sync

extension BookSyncService {
    
    /// Setup background sync (call on app launch)
    func setupBackgroundSync() {
        // Register for CloudKit notifications
        Task {
            do {
                try await subscribeToBookChanges()
            } catch {
                logger.error("Failed to subscribe to book changes: \(error.localizedDescription)")
            }
        }
    }
    
    /// Subscribe to book changes in CloudKit
    private func subscribeToBookChanges() async throws {
        let subscription = CKQuerySubscription(
            recordType: CloudKitRecordType.book,
            predicate: NSPredicate(value: true),
            subscriptionID: "book-changes",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        try await publicDatabase.save(subscription)
        logger.info("Subscribed to book changes")
    }
    
    /// Handle remote notification (call from AppDelegate/SceneDelegate)
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.notificationType == .query else {
            return
        }
        
        logger.info("Received book change notification")
        
        // Sync all pending books
        do {
            try await syncAllPendingBooks()
        } catch {
            logger.error("Failed to sync after notification: \(error.localizedDescription)")
        }
    }
}
