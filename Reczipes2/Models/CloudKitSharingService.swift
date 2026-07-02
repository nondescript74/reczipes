//
//  CloudKitSharingService.swift
//  Reczipes2
//
//  Created on 1/15/26.
//

import Foundation
import CloudKit
import SwiftData
import UIKit
import Combine
import SwiftUI

/// Service for sharing recipes and recipe books via CloudKit Public Database
@MainActor
class CloudKitSharingService: ObservableObject {
    static let shared = CloudKitSharingService()
    
    let container: CKContainer
    let publicDatabase: CKDatabase
    private let privateDatabase: CKDatabase
    
    @Published var isCloudKitAvailable = false
    @Published var currentUserID: String?
    @Published var currentUserName: String?
    
    // Auto-sync properties
    private var syncTimer: Timer?
    @Published var lastSyncDate: Date?
    @Published var isSyncing = false
    @Published var autoSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoSyncEnabled, forKey: "cloudKitAutoSyncEnabled")
            if !autoSyncEnabled {
                stopAutoSync()
            }
        }
    }
    
    // Sync interval in seconds (5 minutes to 30 minutes)
    @Published var syncInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(syncInterval, forKey: "cloudKitSyncInterval")
            // Restart timer with new interval if auto-sync is enabled
            if autoSyncEnabled, syncTimer != nil {
                stopAutoSync()
                Task {
                    if let context = currentModelContext {
                        await startAutoSync(modelContext: context)
                    }
                }
            }
            AppLog.info("Sync interval changed to \(Int(syncInterval)) seconds", category: .sharing)
        }
    }
    
    // Keep a weak reference to model context for auto-sync
    private weak var currentModelContext: ModelContext?
    
    // Track last sync attempt to prevent too-frequent syncs
    private var lastSyncAttempt: Date?
    private let minimumSyncInterval: TimeInterval = 300 // 5 minutes minimum
    
    private init() {
        // Use the same container as your app
        self.container = CKContainer(identifier: "iCloud.com.headydiscy.reczipes")
        self.publicDatabase = container.publicCloudDatabase
        self.privateDatabase = container.privateCloudDatabase
        
        // Load auto-sync preferences from UserDefaults
        self.autoSyncEnabled = UserDefaults.standard.bool(forKey: "cloudKitAutoSyncEnabled")
        self.syncInterval = UserDefaults.standard.double(forKey: "cloudKitSyncInterval")
        
        // Default to 5 minutes if not set or too low
        if self.syncInterval < minimumSyncInterval {
            self.syncInterval = 300 // 5 minutes
        }
        
        Task {
            await checkCloudKitAvailability()
        }
    }
    
    // MARK: - CloudKit Availability
    
    func checkCloudKitAvailability() async {
        do {
            let status = try await container.accountStatus()
            
            switch status {
            case .available:
                isCloudKitAvailable = true
                await fetchUserIdentity()
                AppLog.info("CloudKit available for sharing", category: .sharing)
                
            case .noAccount:
                isCloudKitAvailable = false
                AppLog.warning("No iCloud account - sharing disabled", category: .sharing)
                
            case .restricted:
                isCloudKitAvailable = false
                AppLog.warning("CloudKit restricted - sharing disabled", category: .sharing)
                
            case .couldNotDetermine:
                isCloudKitAvailable = false
                AppLog.warning("CloudKit status unknown - sharing disabled", category: .sharing)
                
            case .temporarilyUnavailable:
                isCloudKitAvailable = false
                AppLog.warning("CloudKit temporarily unavailable", category: .sharing)
                
            @unknown default:
                isCloudKitAvailable = false
            }
        } catch {
            isCloudKitAvailable = false
            AppLog.error("Failed to check CloudKit status: \(error)", category: .sharing)
        }
    }
    
    private func fetchUserIdentity() async {
        do {
            let userRecordID = try await container.userRecordID()
            currentUserID = userRecordID.recordName
            
            // Note: userIdentity(forUserRecordID:) was deprecated in iOS 17.0
            // For privacy reasons, we'll use a user-configured display name from SharingPreferences
            // Fall back to UserDefaults for backwards compatibility
            await fetchUserDisplayName()
            
            AppLog.info("User ID: \(currentUserID ?? "unknown"), Name: \(currentUserName ?? "not set")", category: .sharing)
        } catch {
            AppLog.error("Failed to fetch user identity: \(error)", category: .sharing)
        }
    }
    
    /// Fetch user's display name from SharingPreferences
    private func fetchUserDisplayName() async {
        // This needs to be called from a context where we have access to ModelContext
        // For now, read from UserDefaults as fallback
        currentUserName = UserDefaults.standard.string(forKey: "userDisplayName")
    }
    
    /// Update the current user's display name (call this when SharingPreferences change)
    func updateUserDisplayName(from preferences: SharingPreferences) {
        if preferences.allowOthersToSeeMyName, let displayName = preferences.displayName, !displayName.isEmpty {
            currentUserName = displayName
            // Also save to UserDefaults for persistence
            UserDefaults.standard.set(displayName, forKey: "userDisplayName")
        } else {
            currentUserName = nil
            UserDefaults.standard.removeObject(forKey: "userDisplayName")
        }
        AppLog.info("Updated user display name: \(currentUserName ?? "not set")", category: .sharing)
    }
    
    
    /// Fetch all recipes owned by current user with tracking status
    func fetchMyCloudKitRecipesWithStatus(modelContext: ModelContext) async throws -> CloudKitRecipeManagerData {
        guard let currentUserID = currentUserID else {
            throw SharingError.notAuthenticated
        }
        
        AppLog.info("📋 Fetching all CloudKit recipes for current user...", category: .sharing)
        
        // 1. Fetch all local tracking records first
        let allTracking = try modelContext.fetch(FetchDescriptor<SharedRecipe>())
        AppLog.info("📋 Found \(allTracking.count) local tracking records", category: .sharing)
        
        // 2. Fetch CloudKit records with record IDs
        let allCloudKitRecords = try await fetchAllCloudKitRecords(type: CloudKitRecordType.sharedRecipe)
        let myCloudKitRecords = allCloudKitRecords.filter { record in
            guard let sharedBy = record["sharedBy"] as? String else { return false }
            return sharedBy == currentUserID
        }
        
        AppLog.info("📋 Found \(myCloudKitRecords.count) of my recipes in CloudKit", category: .sharing)
        
        // 3. Build lookup for tracking by both recipeID and cloudRecordID
        var trackingByRecipeID: [UUID: SharedRecipe] = [:]
        var trackingByCloudRecordID: [String: SharedRecipe] = [:]
        var orphanedTrackingRecords: [SharedRecipe] = []
        
        for tracking in allTracking {
            if let recipeID = tracking.recipeID {
                trackingByRecipeID[recipeID] = tracking
            }
            if let cloudRecordID = tracking.cloudRecordID {
                trackingByCloudRecordID[cloudRecordID] = tracking
            }
        }
        
        // 4. Build status objects from CloudKit records
        var statuses: [CloudKitRecipeStatus] = []
        var foundCloudRecordIDs = Set<String>()
        
        for record in myCloudKitRecords {
            guard let recipeData = record["recipeData"] as? String,
                  let jsonData = recipeData.data(using: .utf8),
                  let cloudRecipe = try? JSONDecoder().decode(CloudKitRecipe.self, from: jsonData),
                  let sharedDate = record["sharedDate"] as? Date else {
                AppLog.warning("📋 Skipping invalid CloudKit record: \(record.recordID.recordName)", category: .sharing)
                continue
            }
            
            let cloudRecordID = record.recordID.recordName
            foundCloudRecordIDs.insert(cloudRecordID)
            
            // Check for tracking by both recipe ID and cloud record ID
            let trackingRecord = trackingByRecipeID[cloudRecipe.id] ?? trackingByCloudRecordID[cloudRecordID]
            
            let status = CloudKitRecipeStatus(
                recipe: cloudRecipe,
                cloudRecordID: cloudRecordID,
                sharedDate: sharedDate,
                localTrackingRecord: trackingRecord
            )
            
            statuses.append(status)
        }
        
        // 5. Clean up orphaned tracking records (tracking records that point to deleted CloudKit records)
        for tracking in allTracking {
            if let cloudRecordID = tracking.cloudRecordID,
               !foundCloudRecordIDs.contains(cloudRecordID),
               tracking.sharedByUserID == currentUserID {
                AppLog.warning("📋 Found orphaned tracking record for '\(tracking.recipeTitle)' - CloudKit record was deleted", category: .sharing)
                orphanedTrackingRecords.append(tracking)
            }
        }
        
        // Clean up orphaned tracking records
        if !orphanedTrackingRecords.isEmpty {
            AppLog.info("📋 Cleaning up \(orphanedTrackingRecords.count) orphaned tracking records...", category: .sharing)
            for tracking in orphanedTrackingRecords {
                modelContext.delete(tracking)
            }
            try? modelContext.save()
        }
        
        // 6. Sort: tracked first, then by date
        statuses.sort { (lhs: CloudKitRecipeStatus, rhs: CloudKitRecipeStatus) in
            if lhs.isTracked != rhs.isTracked {
                return lhs.isTracked // Tracked first
            }
            return lhs.sharedDate > rhs.sharedDate // Newest first
        }
        
        AppLog.info("📋 Status: \(statuses.filter { $0.isTracked }.count) tracked, \(statuses.filter { $0.isOrphaned }.count) orphaned", category: .sharing)
        AppLog.info("📋 Cleaned up \(orphanedTrackingRecords.count) stale tracking records", category: .sharing)
        
        return CloudKitRecipeManagerData(recipes: statuses)
    }

    /// Delete a single recipe from CloudKit by record ID
    func deleteRecipeFromCloudKit(cloudRecordID: String) async throws {
        AppLog.info("🗑️ Deleting recipe from CloudKit: \(cloudRecordID)", category: .sharing)
        
        let recordID = CKRecord.ID(recordName: cloudRecordID)
        try await publicDatabase.deleteRecord(withID: recordID)
        
        AppLog.info("✅ Recipe deleted from CloudKit", category: .sharing)
    }

    /// Re-track an orphaned recipe (restore local tracking)
    func reTrackRecipe(recipe: CloudKitRecipe, cloudRecordID: String, modelContext: ModelContext) throws {
        AppLog.info("🔄 Re-tracking orphaned recipe: \(recipe.title)", category: .sharing)
        
        // Check if tracking already exists
        let recipeIDToFind = recipe.id
        let existing = try modelContext.fetch(
            FetchDescriptor<SharedRecipe>(
                predicate: #Predicate<SharedRecipe> { $0.recipeID == recipeIDToFind }
            )
        )
        
        if let existingRecord = existing.first {
            // Reactivate existing record
            existingRecord.isActive = true
            AppLog.info("✅ Reactivated existing tracking record", category: .sharing)
        } else {
            // Create new tracking record
            let tracking = SharedRecipe(
                recipeID: recipe.id,
                cloudRecordID: cloudRecordID,
                sharedByUserID: recipe.sharedByUserID ?? "no user id",
                sharedByUserName: recipe.sharedByUserName,
                sharedDate: Date(),
                recipeTitle: recipe.title,
                recipeImageName: recipe.imageName
            )
            modelContext.insert(tracking)
            AppLog.info("✅ Created new tracking record", category: .sharing)
        }
        
        try modelContext.save()
    }

    /// Delete all orphaned recipes from CloudKit
    func deleteAllOrphanedRecipes(orphanedStatuses: [CloudKitRecipeStatus]) async throws {
        AppLog.info("🗑️ Deleting \(orphanedStatuses.count) orphaned recipes from CloudKit...", category: .sharing)
        
        var successCount = 0
        var failCount = 0
        
        for status in orphanedStatuses {
            do {
                try await deleteRecipeFromCloudKit(cloudRecordID: status.cloudRecordID)
                successCount += 1
            } catch {
                AppLog.error("❌ Failed to delete '\(status.recipe.title)': \(error)", category: .sharing)
                failCount += 1
            }
        }
        
        AppLog.info("✅ Deleted \(successCount) orphaned recipes, \(failCount) failures", category: .sharing)
    }
    
    // MARK: - CloudKit Recipe Book Manager
    
    /// Fetch all recipe books owned by current user with tracking status
    func fetchMyCloudKitRecipeBooksWithStatus(modelContext: ModelContext) async throws -> CloudKitRecipeBookManagerData {
        guard let currentUserID = currentUserID else {
            throw SharingError.notAuthenticated
        }
        
        AppLog.info("📚 Fetching all CloudKit recipe books for current user...", category: .sharing)
        
        // 1. Fetch all recipe book records from CloudKit
        let allRecords = try await fetchAllCloudKitRecords(type: CloudKitRecordType.sharedRecipeBook)
        AppLog.info("📚 Found \(allRecords.count) total recipe book records in CloudKit", category: .sharing)
        
        // 2. Filter to only current user's books
        let myCloudKitRecords = allRecords.filter { record in
            guard let sharedBy = record["sharedBy"] as? String else { return false }
            return sharedBy == currentUserID
        }
        AppLog.info("📚 Found \(myCloudKitRecords.count) recipe books belonging to current user", category: .sharing)
        
        // 3. Fetch all local tracking records
        let allTrackingDescriptor = FetchDescriptor<SharedRecipeBook>()
        let allTracking = (try? modelContext.fetch(allTrackingDescriptor)) ?? []
        AppLog.info("📚 Found \(allTracking.count) local SharedRecipeBook tracking records", category: .sharing)
        
        // Build lookup dictionaries
        var trackingByBookID: [UUID: SharedRecipeBook] = [:]
        var trackingByCloudRecordID: [String: SharedRecipeBook] = [:]
        
        for tracking in allTracking {
            if let bookID = tracking.bookID {
                trackingByBookID[bookID] = tracking
            }
            if let cloudRecordID = tracking.cloudRecordID {
                trackingByCloudRecordID[cloudRecordID] = tracking
            }
        }
        
        // 4. Build status objects from CloudKit records
        var statuses: [CloudKitRecipeBookStatus] = []
        var foundCloudRecordIDs = Set<String>()
        
        for record in myCloudKitRecords {
            guard let bookData = record["bookData"] as? String,
                  let jsonData = bookData.data(using: .utf8),
                  let cloudBook = try? JSONDecoder().decode(CloudKitRecipeBook.self, from: jsonData),
                  let sharedDate = record["sharedDate"] as? Date else {
                AppLog.warning("📚 Skipping invalid CloudKit record: \(record.recordID.recordName)", category: .sharing)
                continue
            }
            
            let cloudRecordID = record.recordID.recordName
            foundCloudRecordIDs.insert(cloudRecordID)
            
            // Check if we have a tracking record for this CloudKit record
            let trackingRecord = trackingByCloudRecordID[cloudRecordID] ?? trackingByBookID[cloudBook.id]
            
            let status = CloudKitRecipeBookStatus(
                book: cloudBook,
                cloudRecordID: cloudRecordID,
                sharedDate: sharedDate,
                localTrackingRecord: trackingRecord
            )
            
            statuses.append(status)
        }
        
        AppLog.info("📚 Built \(statuses.count) status objects", category: .sharing)
        AppLog.info("📚 Tracked: \(statuses.filter { $0.isTracked }.count), Orphaned: \(statuses.filter { $0.isOrphaned }.count)", category: .sharing)
        
        return CloudKitRecipeBookManagerData(books: statuses)
    }
    
    /// Delete a recipe book from CloudKit
    func deleteRecipeBookFromCloudKit(cloudRecordID: String) async throws {
        let recordID = CKRecord.ID(recordName: cloudRecordID)
        
        do {
            _ = try await publicDatabase.deleteRecord(withID: recordID)
            AppLog.info("🗑️ Deleted recipe book from CloudKit: \(cloudRecordID)", category: .sharing)
        } catch {
            AppLog.error("❌ Failed to delete recipe book from CloudKit: \(error)", category: .sharing)
            throw SharingError.uploadFailed(error)
        }
    }
    
    /// Re-track an orphaned recipe book
    func reTrackRecipeBook(book: CloudKitRecipeBook, cloudRecordID: String, modelContext: ModelContext) throws {
        AppLog.info("🔄 Re-tracking recipe book: \(book.name)", category: .sharing)
        
        // Check if tracking already exists
        let cloudRecordIDToFind = cloudRecordID
        let existingDescriptor = FetchDescriptor<SharedRecipeBook>(
            predicate: #Predicate<SharedRecipeBook> { sharedBook in
                sharedBook.cloudRecordID == cloudRecordIDToFind
            }
        )
        
        if let existing = try? modelContext.fetch(existingDescriptor).first {
            // Reactivate existing tracking
            existing.isActive = true
            AppLog.info("✅ Reactivated existing tracking record", category: .sharing)
        } else {
            // Create new tracking record
            let tracking = SharedRecipeBook(
                bookID: book.id,
                cloudRecordID: cloudRecordID,
                sharedByUserID: book.sharedByUserID,
                sharedByUserName: book.sharedByUserName,
                sharedDate: book.sharedDate,
                bookName: book.name,
                bookDescription: book.bookDescription,
                coverImageName: book.coverImageName
            )
            modelContext.insert(tracking)
            AppLog.info("✅ Created new tracking record", category: .sharing)
        }
        
        try modelContext.save()
    }
    
    /// Delete all orphaned recipe books from CloudKit
    func deleteAllOrphanedRecipeBooks(orphanedStatuses: [CloudKitRecipeBookStatus]) async throws {
        AppLog.info("🗑️ Deleting \(orphanedStatuses.count) orphaned recipe books from CloudKit...", category: .sharing)
        
        var successCount = 0
        var failCount = 0
        
        for status in orphanedStatuses {
            do {
                try await deleteRecipeBookFromCloudKit(cloudRecordID: status.cloudRecordID)
                successCount += 1
            } catch {
                AppLog.error("❌ Failed to delete '\(status.book.name)': \(error)", category: .sharing)
                failCount += 1
            }
        }
        
        AppLog.info("✅ Deleted \(successCount) orphaned recipe books, \(failCount) failures", category: .sharing)
    }
    
    // MARK: - Share Recipe
    
    func shareRecipe(_ recipe: RecipeX, modelContext: ModelContext) async throws -> String {
        guard isCloudKitAvailable else {
            throw SharingError.cloudKitUnavailable()
        }
        
        guard let userID = currentUserID else {
            throw SharingError.notAuthenticated
        }
        
        // Check if this recipe is already shared and active
        let recipeIDToFind = recipe.safeID
        let existingDescriptor = FetchDescriptor<SharedRecipe>(
            predicate: #Predicate<SharedRecipe> { sharedRecipe in
                sharedRecipe.recipeID == recipeIDToFind && sharedRecipe.isActive == true
            }
        )
        
        if let existingShared = try? modelContext.fetch(existingDescriptor).first,
           let cloudRecordID = existingShared.cloudRecordID {
            // Verify it still exists in CloudKit
            do {
                let recordID = CKRecord.ID(recordName: cloudRecordID)
                _ = try await publicDatabase.record(for: recordID)
                AppLog.info("Recipe '\(recipe.safeTitle)' is already shared (verified in CloudKit)", category: .sharing)
                return cloudRecordID
            } catch {
                // Record doesn't exist in CloudKit anymore - clean up and reshare
                AppLog.warning("CloudKit record missing for tracked share - will reshare", category: .sharing)
                modelContext.delete(existingShared)
                try? modelContext.save()
            }
        }
        
        // Check for duplicates in CloudKit by recipe ID (safety check)
        let query = CKQuery(
            recordType: CloudKitRecordType.sharedRecipe,
            predicate: NSPredicate(format: "sharedBy == %@", userID)
        )
        let existingRecords = try await publicDatabase.records(matching: query, desiredKeys: ["recipeData"], resultsLimit: 400)
        
        // Delete any existing records for this recipe ID
        for (_, result) in existingRecords.matchResults {
            if case .success(let record) = result,
               let recipeData = record["recipeData"] as? String,
               let jsonData = recipeData.data(using: .utf8),
               let cloudRecipe = try? JSONDecoder().decode(CloudKitRecipe.self, from: jsonData),
               cloudRecipe.id == recipe.safeID {
                // Found duplicate - delete it
                _ = try? await publicDatabase.deleteRecord(withID: record.recordID)
                AppLog.info("Deleted duplicate CloudKit record for recipe '\(recipe.safeTitle)'", category: .sharing)
            }
        }
        
        // Create CloudKit record
        let record = CKRecord(recordType: CloudKitRecordType.sharedRecipe)
        
        let cloudRecipe = CloudKitRecipe(
            id: recipe.safeID,
            title: recipe.safeTitle,
            headerNotes: recipe.headerNotes,
            yield: recipe.yield,
            ingredientSections: recipe.ingredientSections,
            instructionSections: recipe.instructionSections,
            notes: recipe.notes,
            reference: recipe.reference,
            imageName: recipe.imageName,
            additionalImageNames: recipe.additionalImageNames,
            sharedByUserID: userID,
            sharedByUserName: currentUserName,
            sharedDate: Date()
        )
        
        // Encode to JSON and store in CloudKit
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(cloudRecipe)
        
        record["recipeData"] = String(data: jsonData, encoding: .utf8)
        record["title"] = recipe.safeTitle as CKRecordValue
        record["sharedBy"] = userID as CKRecordValue
        record["sharedByName"] = (currentUserName ?? "Anonymous") as CKRecordValue
        record["sharedDate"] = Date() as CKRecordValue
        
        // Upload images if they exist (prefer file on disk; fall back to inline imageData)
        if let imageName = recipe.imageName {
            try await uploadImage(named: imageName, imageData: recipe.imageData, to: record, fieldName: "mainImage")
        } else if recipe.imageData != nil {
            try await uploadImage(named: nil, imageData: recipe.imageData, to: record, fieldName: "mainImage")
        }
        
        // Save to public database
        let savedRecord = try await publicDatabase.save(record)
        
        // Track locally
        let sharedRecipe = SharedRecipe(
            recipeID: recipe.safeID,
            cloudRecordID: savedRecord.recordID.recordName,
            sharedByUserID: userID,
            sharedByUserName: currentUserName,
            recipeTitle: recipe.safeTitle,
            recipeImageName: recipe.imageName
        )
        
        modelContext.insert(sharedRecipe)
        try modelContext.save()
        
        AppLog.info("Shared recipe: \(recipe.safeTitle)", category: .sharing)
        AppLog.info("Community share successful", category: .analytics)
        
        return savedRecord.recordID.recordName
    }
    
    // MARK: - Share Recipe Book
    
    func shareRecipeBook(_ book: Book, modelContext: ModelContext) async throws -> String {
        guard isCloudKitAvailable else {
            throw SharingError.cloudKitUnavailable()
        }
        
        guard let userID = currentUserID else {
            throw SharingError.notAuthenticated
        }
        
        // Check if this book is already shared and active
        let bookIDToFind = book.id
        let existingDescriptor = FetchDescriptor<SharedRecipeBook>(
            predicate: #Predicate<SharedRecipeBook> { sharedBook in
                sharedBook.bookID == bookIDToFind && sharedBook.isActive == true
            }
        )
        
        if let existingShared = try? modelContext.fetch(existingDescriptor).first {
            AppLog.info("Book '\(String(describing: book.name))' is already shared", category: .sharing)
            return existingShared.cloudRecordID ?? "Already shared"
        }
        
        AppLog.info("📚 Sharing recipe book '\(String(describing: book.name))' with \(book.recipeIDs?.count ?? 0) recipes...", category: .sharing)
        
        // Fetch recipe previews for all recipes in the book
        var recipePreviews: [RecipePreviewData] = []
        var recipeCloudRecordIDs: [UUID: String] = [:]
        
        // Safely unwrap recipeIDs before iterating
        guard let recipeIDs = book.recipeIDs else {
            throw SharingError.invalidData
        }
        
        for recipeID in recipeIDs {
            // Find the recipe in local SwiftData (using RecipeX)
            let recipeDescriptor = FetchDescriptor<RecipeX>(
                predicate: #Predicate<RecipeX> { $0.id == recipeID }
            )
            
            guard let recipes = try? modelContext.fetch(recipeDescriptor),
                  let recipe = recipes.first else {
                AppLog.warning("Recipe \(recipeID) not found locally, skipping preview", category: .sharing)
                continue
            }
            
            // Check if this recipe is already shared (to get its CloudKit record ID)
            let sharedRecipeDescriptor = FetchDescriptor<SharedRecipe>(
                predicate: #Predicate<SharedRecipe> { $0.recipeID == recipeID && $0.isActive == true }
            )
            var cloudRecordID = (try? modelContext.fetch(sharedRecipeDescriptor).first)?.cloudRecordID
            
            // If recipe is not shared yet, share it now so we have a cloudRecordID
            if cloudRecordID == nil {
                AppLog.info("  📤 Recipe '\(recipe.safeTitle)' not yet shared, sharing now...", category: .sharing)
                do {
                    cloudRecordID = try await shareRecipe(recipe, modelContext: modelContext)
                    AppLog.info("  ✅ Shared recipe '\(recipe.safeTitle)' with CloudKit ID: \(cloudRecordID ?? "unknown")", category: .sharing)
                } catch {
                    AppLog.error("  ❌ Failed to share recipe '\(recipe.safeTitle)': \(error)", category: .sharing)
                    // Continue anyway - preview will be created without cloudRecordID (read-only)
                }
            }
            
            // Create thumbnail (small, base64-encoded)
            // Fall back to inline imageData when the file is missing from Documents
            var thumbnailBase64: String?
            if let thumbnailData = createThumbnail(for: recipe.imageName, imageData: recipe.imageData, maxSize: 200) {
                thumbnailBase64 = thumbnailData.base64EncodedString()
            }
            
            // Create preview data with embedded thumbnail
            let preview = RecipePreviewData(
                id: recipe.safeID,
                title: recipe.safeTitle,
                headerNotes: recipe.headerNotes,
                imageName: recipe.imageName,
                recipeYield: recipe.recipeYield,
                cloudRecordID: cloudRecordID,
                thumbnailBase64: thumbnailBase64
            )
            
            recipePreviews.append(preview)
            
            if let cloudRecordID = cloudRecordID {
                recipeCloudRecordIDs[recipe.safeID] = cloudRecordID
            }
            
            AppLog.info("  ✅ Added preview for '\(recipe.safeTitle)'\(thumbnailBase64 != nil ? " (with thumbnail)" : "")", category: .sharing)
        }
        
        AppLog.info("📚 Created \(recipePreviews.count) recipe previews", category: .sharing)
        
        // Create CloudKit record
        let record = CKRecord(recordType: CloudKitRecordType.sharedRecipeBook)
        
        // Convert book to CloudKit-friendly format with previews
        let cloudBook = CloudKitRecipeBook(
            id: book.id!,
            name: book.name!,
            bookDescription: book.bookDescription,
            coverImageName: book.coverImageName,
            recipeIDs: book.recipeIDs!,
            color: book.color,
            sharedByUserID: userID,
            sharedByUserName: currentUserName,
            sharedDate: Date()
        )
        
        // Encode book data to JSON
        let encoder = JSONEncoder()
        let bookJsonData = try encoder.encode(cloudBook)
        
        record["bookData"] = String(data: bookJsonData, encoding: .utf8)
        record["name"] = book.name! as any CKRecordValue as CKRecordValue
        record["sharedBy"] = userID as CKRecordValue
        record["sharedByName"] = (currentUserName ?? "Anonymous") as CKRecordValue
        record["sharedDate"] = Date() as CKRecordValue
        
        // NEW: Store recipe previews with embedded thumbnails
        let previewsJsonData = try encoder.encode(recipePreviews)
        record["recipePreviews"] = String(data: previewsJsonData, encoding: .utf8)
        
        AppLog.info("📚 Uploading cover image...", category: .sharing)
        
        // Upload cover image if exists (file on disk or inline coverImageData)
        do {
            try await uploadImage(named: book.coverImageName, imageData: book.coverImageData, to: record, fieldName: "coverImage")
            AppLog.info("  ✅ Uploaded cover image", category: .sharing)
        } catch {
            AppLog.warning("  ⚠️ Failed to upload cover image: \(error)", category: .sharing)
        }
        
        // Save to public database
        AppLog.info("📚 Saving to CloudKit Public Database...", category: .sharing)
        let savedRecord = try await publicDatabase.save(record)
        
        // Track locally
        let sharedBook = SharedRecipeBook(
            bookID: book.id!,
            cloudRecordID: savedRecord.recordID.recordName,
            sharedByUserID: userID,
            sharedByUserName: currentUserName,
            bookName: book.name!,
            bookDescription: book.bookDescription,
            coverImageName: book.coverImageName
        )
        
        modelContext.insert(sharedBook)
        try modelContext.save()
        
        AppLog.info("✅ Shared recipe book: \(String(describing: book.name)) with \(recipePreviews.count) recipe previews", category: .sharing)
        AppLog.info("Community share successful", category: .analytics)
        
        return savedRecord.recordID.recordName
    }
    
    // MARK: - Share Multiple Items
    
    func shareMultipleRecipes(_ recipes: [RecipeX], modelContext: ModelContext) async -> SharingResult {
        var successful = 0
        var failed = 0
        
        for recipe in recipes {
            do {
                _ = try await shareRecipe(recipe, modelContext: modelContext)
                successful += 1
            } catch {
                AppLog.error("Failed to share recipe '\(recipe.safeTitle)': \(error)", category: .sharing)
                AppLog.error("Community share failed: \(error)", category: .analytics)
                failed += 1
            }
        }
        
        if failed == 0 {
            return .success(recordID: "\(successful) recipes shared")
        } else {
            return .partialSuccess(successful: successful, failed: failed)
        }
    }
    
    func shareMultipleBooks(_ books: [Book], modelContext: ModelContext) async -> SharingResult {
        var successful = 0
        var failed = 0
        
        for book in books {
            do {
                _ = try await shareRecipeBook(book, modelContext: modelContext)
                successful += 1
            } catch {
                AppLog.error("Failed to share book '\(String(describing: book.name))': \(error)", category: .sharing)
                AppLog.error("Community share failed: \(error)", category: .analytics)
                failed += 1
            }
        }
        
        if failed == 0 {
            return .success(recordID: "\(successful) books shared")
        } else {
            return .partialSuccess(successful: successful, failed: failed)
        }
    }
    
    // MARK: - Fetch Shared Content
    
    /// Force refresh shared content by clearing any local cache
    func clearSharedContentCache(modelContext: ModelContext) throws {
        // This doesn't delete the actual shared recipes in CloudKit,
        // just the local tracking records that might be stale
        let sharedRecipesDescriptor = FetchDescriptor<SharedRecipe>()
        let sharedBooksDescriptor = FetchDescriptor<SharedRecipeBook>()
        
        let recipes = try modelContext.fetch(sharedRecipesDescriptor)
        let books = try modelContext.fetch(sharedBooksDescriptor)
        
        AppLog.info("Clearing \(recipes.count) cached shared recipes and \(books.count) cached books", category: .sharing)
        
        // Note: Only delete tracking records for recipes shared by OTHERS
        // Keep our own shared recipe tracking
        for recipe in recipes where recipe.sharedByUserID != currentUserID {
            modelContext.delete(recipe)
        }
        
        for book in books where book.sharedByUserID != currentUserID {
            modelContext.delete(book)
        }
        
        try modelContext.save()
        AppLog.info("Shared content cache cleared - next fetch will be fresh from CloudKit", category: .sharing)
    }
    
    
    func fetchSharedRecipes(limit: Int = 400, excludeCurrentUser: Bool = true) async throws -> [CloudKitRecipe] {
        guard isCloudKitAvailable else {
            throw SharingError.cloudKitUnavailable()
        }
        
        AppLog.info("Starting fetchSharedRecipes with limit: \(limit), excludeCurrentUser: \(excludeCurrentUser)", category: .sharing)
        
        // Build predicate: exclude current user's recipes if requested
        let predicate: NSPredicate
        if excludeCurrentUser, let currentUserID = currentUserID {
            predicate = NSPredicate(format: "sharedBy != %@", currentUserID)
            AppLog.info("Filtering out recipes from current user: \(currentUserID)", category: .sharing)
        } else {
            predicate = NSPredicate(value: true)
        }
        
        let query = CKQuery(recordType: CloudKitRecordType.sharedRecipe, predicate: predicate)
        // Note: Don't use sortDescriptors - fields must be marked queryable in CloudKit schema
        // We'll sort results in memory after fetching
        
        var allRecipes: [CloudKitRecipe] = []
        var cursor: CKQueryOperation.Cursor? = nil
        let batchSize = 100 // CloudKit recommended batch size
        var batchNumber = 1
        
        repeat {
            AppLog.info("Fetching batch #\(batchNumber) from CloudKit...", category: .sharing)
            let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            
            if let cursor = cursor {
                // Continue fetching with cursor
                results = try await publicDatabase.records(continuingMatchFrom: cursor, desiredKeys: nil, resultsLimit: batchSize)
            } else {
                // Initial fetch
                results = try await publicDatabase.records(matching: query, desiredKeys: nil, resultsLimit: batchSize)
            }
            
            // Process batch
            var successCount = 0
            var failureCount = 0
            for (_, result) in results.matchResults {
                switch result {
                case .success(let record):
                    if let recipeData = record["recipeData"] as? String,
                       let jsonData = recipeData.data(using: .utf8) {
                        let decoder = JSONDecoder()
                        if var recipe = try? decoder.decode(CloudKitRecipe.self, from: jsonData) {
                            // Download the mainImage CKAsset so the thumbnail
                            // is available on the viewer's device.
                            if let imageAsset = record["mainImage"] as? CKAsset,
                               let assetURL = imageAsset.fileURL,
                               let data = try? Data(contentsOf: assetURL) {
                                recipe.imageData = data
                                AppLog.info("  📷 Downloaded mainImage for '\(recipe.title)' (\(data.count) bytes)", category: .sharing)
                            }
                            allRecipes.append(recipe)
                            successCount += 1
                        } else {
                            AppLog.warning("Failed to decode recipe data from record: \(record.recordID.recordName)", category: .sharing)
                            failureCount += 1
                        }
                    } else {
                        AppLog.warning("Record missing recipeData field: \(record.recordID.recordName)", category: .sharing)
                        failureCount += 1
                    }
                case .failure(let error):
                    AppLog.error("Failed to fetch shared recipe: \(error)", category: .sharing)
                    failureCount += 1
                }
            }
            AppLog.info("Batch decoded: \(successCount) success, \(failureCount) failures", category: .sharing)
            
            // Update cursor for next iteration
            cursor = results.queryCursor
            
            AppLog.info("Batch #\(batchNumber) complete: \(allRecipes.count) total recipes so far, cursor: \(cursor != nil ? "has more" : "end")", category: .sharing)
            batchNumber += 1
            
            // Stop if we've reached the limit or no more results
            if allRecipes.count >= limit || cursor == nil {
                break
            }
            
        } while cursor != nil
        
        // Sort in memory by sharedDate (most recent first)
        allRecipes.sort { recipe1, recipe2 in
            recipe1.sharedDate > recipe2.sharedDate
        }
        
        AppLog.info("✅ Fetched \(allRecipes.count) shared recipes total (using cursor pagination)", category: .sharing)
        return allRecipes
    }
    
    func fetchSharedRecipeBooks(limit: Int = 400, excludeCurrentUser: Bool = true) async throws -> [CloudKitRecipeBook] {
        guard isCloudKitAvailable else {
            throw SharingError.cloudKitUnavailable()
        }
        
        // Build predicate: exclude current user's books if requested
        let predicate: NSPredicate
        if excludeCurrentUser, let currentUserID = currentUserID {
            predicate = NSPredicate(format: "sharedBy != %@", currentUserID)
            AppLog.info("Filtering out recipe books from current user: \(currentUserID)", category: .sharing)
        } else {
            predicate = NSPredicate(value: true)
        }
        
        let query = CKQuery(recordType: CloudKitRecordType.sharedRecipeBook, predicate: predicate)
        // Note: Don't use sortDescriptors - fields must be marked queryable in CloudKit schema
        // We'll sort results in memory after fetching
        
        var allBooks: [CloudKitRecipeBook] = []
        var cursor: CKQueryOperation.Cursor? = nil
        let batchSize = 100 // CloudKit recommended batch size
        
        repeat {
            let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            
            if let cursor = cursor {
                // Continue fetching with cursor
                results = try await publicDatabase.records(continuingMatchFrom: cursor, desiredKeys: nil, resultsLimit: batchSize)
            } else {
                // Initial fetch
                results = try await publicDatabase.records(matching: query, desiredKeys: nil, resultsLimit: batchSize)
            }
            
            // Process batch
            for (_, result) in results.matchResults {
                switch result {
                case .success(let record):
                    if let bookData = record["bookData"] as? String,
                       let jsonData = bookData.data(using: .utf8) {
                        let decoder = JSONDecoder()
                        if let book = try? decoder.decode(CloudKitRecipeBook.self, from: jsonData) {
                            allBooks.append(book)
                        }
                    }
                case .failure(let error):
                    AppLog.error("Failed to fetch shared book: \(error)", category: .sharing)
                }
            }
            
            // Update cursor for next iteration
            cursor = results.queryCursor
            
            // Stop if we've reached the limit or no more results
            if allBooks.count >= limit || cursor == nil {
                break
            }
            
        } while cursor != nil
        
        // Sort in memory by sharedDate (most recent first)
        allBooks.sort { book1, book2 in
            book1.sharedDate > book2.sharedDate
        }
        
        AppLog.info("Fetched \(allBooks.count) shared recipe books (using cursor pagination)", category: .sharing)
        return allBooks
    }
    
    // MARK: - Unshare Content
    
    func unshareRecipe(cloudRecordID: String, modelContext: ModelContext) async throws {
        guard isCloudKitAvailable else {
            throw SharingError.cloudKitUnavailable()
        }
        
        let recordID = CKRecord.ID(recordName: cloudRecordID)
        try await publicDatabase.deleteRecord(withID: recordID)
        
        // Remove from local tracking
        let recordIDToFind = cloudRecordID
        let descriptor = FetchDescriptor<SharedRecipe>(
            predicate: #Predicate<SharedRecipe> { sharedRecipe in
                sharedRecipe.cloudRecordID == recordIDToFind
            }
        )
        
        if let sharedRecipe = try modelContext.fetch(descriptor).first {
            modelContext.delete(sharedRecipe)
            try modelContext.save()
        }
        
        AppLog.info("Unshared recipe with ID: \(cloudRecordID)", category: .sharing)
    }
    
    func unshareRecipeBook(cloudRecordID: String, modelContext: ModelContext) async throws {
        guard isCloudKitAvailable else {
            throw SharingError.cloudKitUnavailable()
        }
        
        AppLog.info("📚 Unsharing book: \(cloudRecordID)", category: .sharing)
        
        // Find the SharedRecipeBook entry to get the bookID before deletion
        let recordIDToFind = cloudRecordID
        let sharedBookDescriptor = FetchDescriptor<SharedRecipeBook>(
            predicate: #Predicate<SharedRecipeBook> { sharedBook in
                sharedBook.cloudRecordID == recordIDToFind
            }
        )
        
        let sharedBook = try modelContext.fetch(sharedBookDescriptor).first
        let bookID = sharedBook?.bookID
        
        // Delete from CloudKit first
        let recordID = CKRecord.ID(recordName: cloudRecordID)
        try await publicDatabase.deleteRecord(withID: recordID)
        AppLog.info("📚 Deleted CloudKit record: \(cloudRecordID)", category: .sharing)
        
        // Remove from local tracking
        if let sharedBook = sharedBook {
            modelContext.delete(sharedBook)
            AppLog.info("📚 Deleted SharedRecipeBook tracking entry", category: .sharing)
        }
        
        // IMPORTANT: Also delete the local RecipeBook if this was the user's own shared book
        // (Don't delete it if it's someone else's shared book - that should only be cleaned by sync)
        if let bookID = bookID,
           let currentUserID = currentUserID,
           sharedBook?.sharedByUserID == currentUserID {
            let bookDescriptor = FetchDescriptor<Book>(
                predicate: #Predicate<Book> { book in
                    book.id == bookID
                }
            )
            
            if (try modelContext.fetch(bookDescriptor).first) != nil {
                AppLog.info("📚 Also deleting local RecipeBook (user's own shared book)", category: .sharing)
                // Note: We're NOT deleting the book here because the user may still want to keep it locally
                // Only mark the sharing as inactive
            }
        }
        
        try modelContext.save()
        AppLog.info("✅ Successfully unshared recipe book: \(cloudRecordID)", category: .sharing)
    }
    
    // MARK: - Image Handling
    
    /// Upload an image as a CKAsset.
    /// Prefers the file on disk at `imageName`; falls back to writing `imageData` to a
    /// temporary file so a valid CKAsset can be created.  Does nothing if neither source
    /// produces usable data.
    private func uploadImage(named imageName: String?, imageData: Data?, to record: CKRecord, fieldName: String) async throws {
        // --- Try the on-disk file first ---
        if let imageName = imageName {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let imageURL = documentsPath.appendingPathComponent(imageName)

            if FileManager.default.fileExists(atPath: imageURL.path) {
                record[fieldName] = CKAsset(fileURL: imageURL)
                return
            }
            AppLog.warning("Image file not found on disk: \(imageName) — attempting imageData fallback", category: .sharing)
        }

        // --- Fall back to inline imageData ---
        guard let data = imageData, !data.isEmpty else {
            AppLog.warning("No image available for field '\(fieldName)' (imageName: \(imageName ?? "nil"), imageData: nil)", category: .sharing)
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ckasset_\(fieldName)_\(UUID().uuidString).jpg")
        try data.write(to: tempURL)
        record[fieldName] = CKAsset(fileURL: tempURL)
        AppLog.info("  📷 Uploaded '\(fieldName)' from inline imageData (\(data.count) bytes)", category: .sharing)
    }
    
    func downloadImage(from record: CKRecord, fieldName: String) async throws -> UIImage? {
        guard let asset = record[fieldName] as? CKAsset,
              let fileURL = asset.fileURL else {
            return nil
        }
        
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        
        return image
    }
    
    // MARK: - Import Shared Content
    
    /// Diagnostic function to check CloudKit public database status and detect sync issues
    func diagnoseSharedRecipes() async {
        guard let currentUserID = currentUserID else {
            AppLog.error("Cannot run diagnostic - no current user ID", category: .sharing)
            return
        }
        
        do {
            // Fetch ALL recipes (including current user's) for diagnostic purposes
            let recipes = try await fetchSharedRecipes(excludeCurrentUser: false)
            
            // Separate current user's recipes vs others
            let myRecipes = recipes.filter { $0.sharedByUserID == currentUserID }
            let othersRecipes = recipes.filter { $0.sharedByUserID != currentUserID }
            
            AppLog.info("Diagnostic: \(myRecipes.count) of my recipes, \(othersRecipes.count) from others", category: .sharing)
            
            // Group by sharer
            let groupedByUser = Dictionary(grouping: recipes) { $0.sharedByUserID }
            AppLog.info("Total unique sharers: \(groupedByUser.count)", category: .sharing)
            
            // Detect duplicates by recipe ID
            let groupedByRecipeID = Dictionary(grouping: recipes) { $0.id }
            let duplicates = groupedByRecipeID.filter { $0.value.count > 1 }
            if !duplicates.isEmpty {
                AppLog.warning("Found \(duplicates.count) duplicate recipe IDs in CloudKit", category: .sharing)
            } else {
                AppLog.info("No duplicates found", category: .sharing)
            }
            
        } catch {
            AppLog.error("Diagnostic failed: \(error)", category: .sharing)
        }
    }
    
    /// Sync local SharedRecipe tracking with CloudKit truth
    /// This finds recipes in CloudKit that should be tracked locally but aren't
    func syncLocalTrackingWithCloudKit(modelContext: ModelContext) async throws {
        guard let currentUserID = currentUserID else {
            throw SharingError.notAuthenticated
        }
        
        AppLog.info("Starting local tracking sync", category: .sharing)
        
        // Fetch ALL recipes from CloudKit (including current user's)
        let allCloudKitRecipes = try await fetchSharedRecipes(excludeCurrentUser: false)
        let myCloudKitRecipes = allCloudKitRecipes.filter { $0.sharedByUserID == currentUserID }
        
        // Fetch all local SharedRecipe tracking records
        let localTracking = try modelContext.fetch(FetchDescriptor<SharedRecipe>())
        let localRecipeIDs = Set(localTracking.compactMap { $0.recipeID })
        
        AppLog.info("Found \(myCloudKitRecipes.count) recipes in CloudKit, \(localTracking.count) local tracking records", category: .sharing)
        
        // Find CloudKit recipes that aren't tracked locally
        var missingLocalTracking: [CloudKitRecipe] = []
        
        for cloudRecipe in myCloudKitRecipes {
            if !localRecipeIDs.contains(cloudRecipe.id) {
                missingLocalTracking.append(cloudRecipe)
            }
        }
        
        // Find local tracking records that don't exist in CloudKit
        let cloudKitRecipeIDs = Set(myCloudKitRecipes.map { $0.id })
        var orphanedLocalRecords: [SharedRecipe] = []
        
        for localRecord in localTracking where localRecord.isActive {
            if let recipeID = localRecord.recipeID,
               !cloudKitRecipeIDs.contains(recipeID) {
                orphanedLocalRecords.append(localRecord)
            }
        }
        
        AppLog.info("Sync: \(missingLocalTracking.count) CloudKit recipes not tracked, \(orphanedLocalRecords.count) orphaned local records", category: .sharing)
        
        // Clean up orphaned local records (recipes that were unshared but local tracking wasn't cleaned)
        if !orphanedLocalRecords.isEmpty {
            for record in orphanedLocalRecords {
                record.isActive = false
            }
        }
        
        // Report on missing local tracking
        if !missingLocalTracking.isEmpty {
            AppLog.warning("Found \(missingLocalTracking.count) recipes in CloudKit without local tracking - run cleanupGhostRecipes()", category: .sharing)
        }
        
        try modelContext.save()
        
        AppLog.info("✅ SYNC COMPLETE: Local tracking is now synced with CloudKit", category: .sharing)
        AppLog.info("   - Deactivated \(orphanedLocalRecords.count) stale local records", category: .sharing)
        AppLog.info("   - Found \(missingLocalTracking.count) ghost recipes in CloudKit (need cleanup)", category: .sharing)
    }
    
    /// Repair missing CloudKit record IDs for shared recipes
    /// This fixes recipes that were shared but don't have cloudRecordID stored
    func repairMissingRecipeCloudKitIDs(modelContext: ModelContext) async throws {
        guard let currentUserID = currentUserID else {
            throw SharingError.notAuthenticated
        }
        
        AppLog.info("🔧 REPAIR: Starting repair of missing recipe CloudKit IDs...", category: .sharing)
        
        // Find all active shared recipes without cloudRecordID
        let allSharedRecipes = try modelContext.fetch(FetchDescriptor<SharedRecipe>())
        let recipesNeedingRepair = allSharedRecipes.filter { $0.cloudRecordID == nil && $0.isActive }
        
        if recipesNeedingRepair.isEmpty {
            AppLog.info("✅ REPAIR: No recipes need repair - all have CloudKit IDs", category: .sharing)
            return
        }
        
        AppLog.info("🔧 REPAIR: Found \(recipesNeedingRepair.count) recipes missing CloudKit IDs", category: .sharing)
        
        // Fetch all CloudKit records for current user's recipes
        let allCloudKitRecords = try await fetchAllCloudKitRecords(type: CloudKitRecordType.sharedRecipe)
        let myRecords = allCloudKitRecords.filter { record in
            guard let sharedBy = record["sharedBy"] as? String else { return false }
            return sharedBy == currentUserID
        }
        
        AppLog.info("🔧 REPAIR: Found \(myRecords.count) CloudKit records belonging to current user", category: .sharing)
        
        // Build mapping from recipeID to cloudRecordID
        var recipeIDToRecordID: [UUID: String] = [:]
        for record in myRecords {
            guard let recipeData = record["recipeData"] as? String,
                  let jsonData = recipeData.data(using: .utf8),
                  let cloudRecipe = try? JSONDecoder().decode(CloudKitRecipe.self, from: jsonData) else {
                continue
            }
            
            recipeIDToRecordID[cloudRecipe.id] = record.recordID.recordName
        }
        
        // Repair each recipe
        var repairedCount = 0
        for sharedRecipe in recipesNeedingRepair {
            guard let recipeID = sharedRecipe.recipeID,
                  let cloudRecordID = recipeIDToRecordID[recipeID] else {
                AppLog.warning("🔧 REPAIR: Could not find CloudKit record for recipe '\(sharedRecipe.recipeTitle)'", category: .sharing)
                continue
            }
            
            sharedRecipe.cloudRecordID = cloudRecordID
            repairedCount += 1
            AppLog.info("🔧 REPAIR: Fixed '\(sharedRecipe.recipeTitle)' - added CloudKit ID: \(cloudRecordID)", category: .sharing)
        }
        
        try modelContext.save()
        
        AppLog.info("✅ REPAIR COMPLETE: Fixed \(repairedCount) of \(recipesNeedingRepair.count) recipes", category: .sharing)
    }
    
    /// Remove "ghost recipes" - recipes in CloudKit that users think they've unshared
    /// These are recipes where the CloudKit record exists but there's no active local tracking
    /// Returns: (ghostsFound: Int, deleted: Int, failed: Int)
    func cleanupGhostRecipes(modelContext: ModelContext) async throws -> (ghostsFound: Int, deleted: Int, failed: Int) {
        guard let currentUserID = currentUserID else {
            throw SharingError.notAuthenticated
        }
        
        AppLog.info("👻 GHOST CLEANUP: Starting ghost recipe detection...", category: .sharing)
        
        // Fetch ALL my recipes from CloudKit
        let allCloudKitRecipes = try await fetchSharedRecipes(excludeCurrentUser: false)
        let myCloudKitRecipes = allCloudKitRecipes.filter { $0.sharedByUserID == currentUserID }
        
        AppLog.info("👻 Found \(myCloudKitRecipes.count) of my recipes in CloudKit", category: .sharing)
        
        // Fetch all ACTIVE local SharedRecipe tracking records
        let activeTracking = try modelContext.fetch(
            FetchDescriptor<SharedRecipe>(
                predicate: #Predicate<SharedRecipe> { $0.isActive == true }
            )
        )
        let activeRecipeIDs = Set(activeTracking.compactMap { $0.recipeID })
        
        AppLog.info("👻 Found \(activeTracking.count) active local tracking records", category: .sharing)
        
        // Find CloudKit recipes that aren't actively tracked (these are ghosts!)
        var ghostRecipes: [(recipe: CloudKitRecipe, cloudRecordID: String)] = []
        
        // We need to fetch the actual CloudKit records to get their record IDs for deletion
        let allCloudKitRecords = try await fetchAllCloudKitRecords(type: CloudKitRecordType.sharedRecipe)
        
        for record in allCloudKitRecords {
            guard let sharedBy = record["sharedBy"] as? String,
                  sharedBy == currentUserID,
                  let recipeData = record["recipeData"] as? String,
                  let jsonData = recipeData.data(using: .utf8),
                  let cloudRecipe = try? JSONDecoder().decode(CloudKitRecipe.self, from: jsonData) else {
                continue
            }
            
            // If this recipe isn't actively tracked locally, it's a ghost
            if !activeRecipeIDs.contains(cloudRecipe.id) {
                ghostRecipes.append((cloudRecipe, record.recordID.recordName))
                AppLog.warning("👻 Found ghost recipe: '\(cloudRecipe.title)' (ID: \(cloudRecipe.id))", category: .sharing)
            }
        }
        
        AppLog.info("👻 Found \(ghostRecipes.count) ghost recipes", category: .sharing)
        
        if ghostRecipes.isEmpty {
            AppLog.info("✅ No ghost recipes found - everything is in sync!", category: .sharing)
            return (ghostsFound: 0, deleted: 0, failed: 0)
        }
        
        // Delete ghost recipes from CloudKit
        AppLog.info("👻 Deleting \(ghostRecipes.count) ghost recipes from CloudKit...", category: .sharing)
        var successCount = 0
        var failCount = 0
        
        for (recipe, cloudRecordID) in ghostRecipes {
            do {
                let recordID = CKRecord.ID(recordName: cloudRecordID)
                try await publicDatabase.deleteRecord(withID: recordID)
                AppLog.info("👻   Deleted '\(recipe.title)'", category: .sharing)
                successCount += 1
            } catch {
                AppLog.error("👻   Failed to delete '\(recipe.title)': \(error)", category: .sharing)
                failCount += 1
            }
        }
        
        AppLog.info("✅ GHOST CLEANUP COMPLETE: Deleted \(successCount) ghost recipes, \(failCount) failures", category: .sharing)
        
        return (ghostsFound: ghostRecipes.count, deleted: successCount, failed: failCount)
    }
    
    // MARK: - Ghost/Orphaned Recipe Books Cleanup
    
    /// Diagnostic result for recipe book analysis
    struct BookDiagnosticResult {
        let cloudKitBooks: Int
        let myCloudKitBooks: Int
        let othersCloudKitBooks: Int
        let localBooks: Int
        let activeTracking: Int
        let inactiveTracking: Int
        let myTracking: Int
        let othersTracking: Int
        let duplicateBookIDs: Int
        let orphanedBooks: Int
    }
    
    /// Diagnostic function to analyze recipe book sharing state
    /// Returns structured diagnostic data for display to user
    func diagnoseSharedRecipeBooks(modelContext: ModelContext) async -> BookDiagnosticResult? {
        guard let currentUserID = currentUserID else {
            AppLog.error("No user ID available", category: .sharing)
            return nil
        }
        
        var cloudKitBooks = 0
        var myCloudKitBooks = 0
        var othersCloudKitBooks = 0
        var duplicateBookIDs = 0
        
        // PART 1: Check CloudKit Public Database
        do {
            let books = try await fetchSharedRecipeBooks(excludeCurrentUser: false)
            cloudKitBooks = books.count
            myCloudKitBooks = books.filter { $0.sharedByUserID == currentUserID }.count
            othersCloudKitBooks = books.filter { $0.sharedByUserID != currentUserID }.count
            
            // Detect duplicates
            let groupedByBookID = Dictionary(grouping: books) { $0.id }
            duplicateBookIDs = groupedByBookID.filter { $0.value.count > 1 }.count
            
            AppLog.info("CloudKit: \(cloudKitBooks) total (\(myCloudKitBooks) mine, \(othersCloudKitBooks) others)", category: .sharing)
        } catch {
            AppLog.error("Failed to fetch from CloudKit: \(error)", category: .sharing)
        }
        
        var localBooks = 0
        var totalTracking = 0
        var activeCount = 0
        var myTracking = 0
        var othersTracking = 0
        var orphanedBooks = 0
        
        // PART 2: Check Local SwiftData
        do {
            let allLocalBooks = try modelContext.fetch(FetchDescriptor<Book>())
            localBooks = allLocalBooks.count
            
            let allTracking = try modelContext.fetch(FetchDescriptor<SharedRecipeBook>())
            totalTracking = allTracking.count
            
            let activeTracking = allTracking.filter { $0.isActive }
            activeCount = activeTracking.count
            
            myTracking = activeTracking.filter { $0.sharedByUserID == currentUserID }.count
            othersTracking = activeTracking.filter { $0.sharedByUserID != currentUserID }.count
            
            // Check for orphaned books
            let trackedBookIDs = Set(activeTracking.compactMap { $0.bookID })
            orphanedBooks = allLocalBooks.filter { !trackedBookIDs.contains($0.id!) }.count
            
            AppLog.info("Local: \(localBooks) books, \(activeCount) active tracking, \(orphanedBooks) orphaned", category: .sharing)
        } catch {
            AppLog.error("Failed to fetch from local: \(error)", category: .sharing)
        }
        
        return BookDiagnosticResult(
            cloudKitBooks: cloudKitBooks,
            myCloudKitBooks: myCloudKitBooks,
            othersCloudKitBooks: othersCloudKitBooks,
            localBooks: localBooks,
            activeTracking: activeCount,
            inactiveTracking: totalTracking - activeCount,
            myTracking: myTracking,
            othersTracking: othersTracking,
            duplicateBookIDs: duplicateBookIDs,
            orphanedBooks: orphanedBooks
        )
    }
    
    /// Sync local SharedRecipeBook tracking with CloudKit truth
    /// This finds recipe books in CloudKit that should be tracked locally but aren't
    func syncLocalRecipeBookTrackingWithCloudKit(modelContext: ModelContext) async throws {
        guard let currentUserID = currentUserID else {
            throw SharingError.notAuthenticated
        }
        
        AppLog.info("Starting local recipe book tracking sync", category: .sharing)
        
        // Fetch ALL recipe books from CloudKit (including current user's)
        let allCloudKitBooks = try await fetchSharedRecipeBooks(excludeCurrentUser: false)
        let myCloudKitBooks = allCloudKitBooks.filter { $0.sharedByUserID == currentUserID }
        
        // Fetch all local SharedRecipeBook tracking records
        let localTracking = try modelContext.fetch(FetchDescriptor<SharedRecipeBook>())
        let localBookIDs = Set(localTracking.compactMap { $0.bookID })
        
        AppLog.info("Found \(myCloudKitBooks.count) books in CloudKit, \(localTracking.count) local tracking records", category: .sharing)
        
        // Find CloudKit recipe books that aren't tracked locally
        var missingLocalTracking: [CloudKitRecipeBook] = []
        
        for cloudBook in myCloudKitBooks {
            if !localBookIDs.contains(cloudBook.id) {
                missingLocalTracking.append(cloudBook)
            }
        }
        
        // Find local tracking records that don't exist in CloudKit
        let cloudKitBookIDs = Set(myCloudKitBooks.map { $0.id })
        var orphanedLocalRecords: [SharedRecipeBook] = []
        
        for localRecord in localTracking where localRecord.isActive {
            if let bookID = localRecord.bookID,
               !cloudKitBookIDs.contains(bookID) {
                orphanedLocalRecords.append(localRecord)
            }
        }
        
        AppLog.info("Sync: \(missingLocalTracking.count) CloudKit books not tracked, \(orphanedLocalRecords.count) orphaned local records", category: .sharing)
        
        // Clean up orphaned local records (books that were unshared but local tracking wasn't cleaned)
        if !orphanedLocalRecords.isEmpty {
            for record in orphanedLocalRecords {
                record.isActive = false
            }
        }
        
        // Warn about missing local tracking
        if !missingLocalTracking.isEmpty {
            AppLog.warning("Found \(missingLocalTracking.count) books in CloudKit without local tracking - run cleanupGhostRecipeBooks()", category: .sharing)
        }
        
        try modelContext.save()
        
        AppLog.info("Sync complete: deactivated \(orphanedLocalRecords.count) stale records, \(missingLocalTracking.count) ghost books found", category: .sharing)
    }
    
    /// Repair missing CloudKit record IDs for shared recipe books
    /// This fixes books that were shared but don't have cloudRecordID stored
    func repairMissingRecipeBookCloudKitIDs(modelContext: ModelContext) async throws {
        guard let currentUserID = currentUserID else {
            throw SharingError.notAuthenticated
        }
        
        AppLog.info("🔧 REPAIR: Starting repair of missing recipe book CloudKit IDs...", category: .sharing)
        
        // Find all active shared books without cloudRecordID
        let allSharedBooks = try modelContext.fetch(FetchDescriptor<SharedRecipeBook>())
        let booksNeedingRepair = allSharedBooks.filter { $0.cloudRecordID == nil && $0.isActive }
        
        if booksNeedingRepair.isEmpty {
            AppLog.info("✅ REPAIR: No recipe books need repair - all have CloudKit IDs", category: .sharing)
            return
        }
        
        AppLog.info("🔧 REPAIR: Found \(booksNeedingRepair.count) books missing CloudKit IDs", category: .sharing)
        
        // Fetch all CloudKit records for current user's books
        let allCloudKitRecords = try await fetchAllCloudKitRecords(type: CloudKitRecordType.sharedRecipeBook)
        let myRecords = allCloudKitRecords.filter { record in
            guard let sharedBy = record["sharedBy"] as? String else { return false }
            return sharedBy == currentUserID
        }
        
        AppLog.info("🔧 REPAIR: Found \(myRecords.count) CloudKit records belonging to current user", category: .sharing)
        
        // Build mapping from bookID to cloudRecordID
        var bookIDToRecordID: [UUID: String] = [:]
        for record in myRecords {
            guard let bookData = record["bookData"] as? String,
                  let jsonData = bookData.data(using: .utf8),
                  let cloudBook = try? JSONDecoder().decode(CloudKitRecipeBook.self, from: jsonData) else {
                continue
            }
            
            bookIDToRecordID[cloudBook.id] = record.recordID.recordName
        }
        
        // Repair each book
        var repairedCount = 0
        for sharedBook in booksNeedingRepair {
            guard let bookID = sharedBook.bookID,
                  let cloudRecordID = bookIDToRecordID[bookID] else {
                AppLog.warning("🔧 REPAIR: Could not find CloudKit record for book '\(sharedBook.bookName)'", category: .sharing)
                continue
            }
            
            sharedBook.cloudRecordID = cloudRecordID
            repairedCount += 1
            AppLog.info("🔧 REPAIR: Fixed '\(sharedBook.bookName)' - added CloudKit ID: \(cloudRecordID)", category: .sharing)
        }
        
        try modelContext.save()
        
        AppLog.info("✅ REPAIR COMPLETE: Fixed \(repairedCount) of \(booksNeedingRepair.count) books", category: .sharing)
    }
    
    /// Remove "ghost recipe books" - books in CloudKit that users think they've unshared
    /// These are books where the CloudKit record exists but there's no active local tracking
    /// Returns: (ghostsFound: Int, deleted: Int, failed: Int)
    func cleanupGhostRecipeBooks(modelContext: ModelContext) async throws -> (ghostsFound: Int, deleted: Int, failed: Int) {
        guard let currentUserID = currentUserID else {
            throw SharingError.notAuthenticated
        }
        
        AppLog.info("👻 GHOST CLEANUP: Starting ghost recipe book detection...", category: .sharing)
        
        // Fetch ALL my recipe books from CloudKit
        let allCloudKitBooks = try await fetchSharedRecipeBooks(excludeCurrentUser: false)
        let myCloudKitBooks = allCloudKitBooks.filter { $0.sharedByUserID == currentUserID }
        
        AppLog.info("👻 Found \(myCloudKitBooks.count) of my recipe books in CloudKit", category: .sharing)
        
        // Fetch all ACTIVE local SharedRecipeBook tracking records
        let activeTracking = try modelContext.fetch(
            FetchDescriptor<SharedRecipeBook>(
                predicate: #Predicate<SharedRecipeBook> { $0.isActive == true }
            )
        )
        let activeBookIDs = Set(activeTracking.compactMap { $0.bookID })
        
        AppLog.info("👻 Found \(activeTracking.count) active local tracking records", category: .sharing)
        
        // Find CloudKit recipe books that aren't actively tracked (these are ghosts!)
        var ghostBooks: [(book: CloudKitRecipeBook, cloudRecordID: String)] = []
        
        // We need to fetch the actual CloudKit records to get their record IDs for deletion
        let allCloudKitRecords = try await fetchAllCloudKitRecords(type: CloudKitRecordType.sharedRecipeBook)
        
        for record in allCloudKitRecords {
            guard let sharedBy = record["sharedBy"] as? String,
                  sharedBy == currentUserID,
                  let bookData = record["bookData"] as? String,
                  let jsonData = bookData.data(using: .utf8),
                  let cloudBook = try? JSONDecoder().decode(CloudKitRecipeBook.self, from: jsonData) else {
                continue
            }
            
            // If this book isn't actively tracked locally, it's a ghost
            if !activeBookIDs.contains(cloudBook.id) {
                ghostBooks.append((cloudBook, record.recordID.recordName))
                AppLog.warning("👻 Found ghost recipe book: '\(cloudBook.name)' (ID: \(cloudBook.id))", category: .sharing)
            }
        }
        
        AppLog.info("👻 Found \(ghostBooks.count) ghost recipe books", category: .sharing)
        
        if ghostBooks.isEmpty {
            AppLog.info("✅ No ghost recipe books found - everything is in sync!", category: .sharing)
            return (ghostsFound: 0, deleted: 0, failed: 0)
        }
        
        // Delete ghost recipe books from CloudKit
        AppLog.info("👻 Deleting \(ghostBooks.count) ghost recipe books from CloudKit...", category: .sharing)
        var successCount = 0
        var failCount = 0
        
        for (book, cloudRecordID) in ghostBooks {
            do {
                let recordID = CKRecord.ID(recordName: cloudRecordID)
                try await publicDatabase.deleteRecord(withID: recordID)
                AppLog.info("👻   Deleted '\(book.name)'", category: .sharing)
                successCount += 1
            } catch {
                AppLog.error("👻   Failed to delete '\(book.name)': \(error)", category: .sharing)
                failCount += 1
            }
        }
        
        AppLog.info("✅ GHOST CLEANUP COMPLETE: Deleted \(successCount) ghost recipe books, \(failCount) failures", category: .sharing)
        
        return (ghostsFound: ghostBooks.count, deleted: successCount, failed: failCount)
    }
    
    // MARK: - Auto-Sync Management
    
    /// Start automatic background syncing
    /// Call this when the app becomes active or when user enables auto-sync
    func startAutoSync(modelContext: ModelContext) async {
        guard autoSyncEnabled else {
            return
        }
        
        guard syncTimer == nil else {
            return
        }
        
        // Store model context reference
        self.currentModelContext = modelContext
        
        AppLog.info("Starting auto-sync (interval: \(Int(syncInterval/60))min)", category: .sharing)
        
        // Sync immediately on start
        await performBackgroundSync(modelContext: modelContext)
        
        // Schedule periodic sync on main thread
        // Use weak reference to avoid retain cycle and nonisolated(unsafe) to handle non-Sendable ModelContext
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                // Access currentModelContext inside the MainActor-isolated Task
                guard let context = self.currentModelContext else { return }
                nonisolated(unsafe) let modelContext = context
                await self.performBackgroundSync(modelContext: modelContext)
            }
        }
        
        // Ensure timer fires even when scrolling
        if let timer = syncTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    /// Stop automatic background syncing
    func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        currentModelContext = nil
        AppLog.info("Stopped auto-sync", category: .sharing)
    }
    
    /// Perform a background sync (checks for changes without blocking UI)
    private func performBackgroundSync(modelContext: ModelContext) async {
        guard !isSyncing else {
            return
        }
        
        // Debounce: prevent syncs that are too close together
        if let lastAttempt = lastSyncAttempt {
            let timeSinceLastSync = Date().timeIntervalSince(lastAttempt)
            if timeSinceLastSync < minimumSyncInterval {
                return
            }
        }
        
        guard isCloudKitAvailable else {
            return
        }
        
        isSyncing = true
        lastSyncAttempt = Date()
        defer { isSyncing = false }
        
        let startTime = Date()
        AppLog.info("Starting background sync", category: .sharing)
        
        do {
            // Sync community recipes (limit to recent 100 to keep it fast)
            try await syncCommunityRecipesForViewing(modelContext: modelContext, limit: 100)
            
            // Sync community books
            try await syncCommunityBooksToLocal(modelContext: modelContext)
            
            lastSyncDate = Date()
            let duration = Date().timeIntervalSince(startTime)
            AppLog.info("Auto-sync completed in \(String(format: "%.1f", duration))s", category: .sharing)
        } catch {
            AppLog.error("Auto-sync failed: \(error.localizedDescription)", category: .sharing)
        }
    }
    
    /// Manually trigger a sync (for user pull-to-refresh)
    func manualSync(modelContext: ModelContext) async {
        // For manual sync, bypass the debounce
        let previousAttempt = lastSyncAttempt
        lastSyncAttempt = nil
        await performBackgroundSync(modelContext: modelContext)
        if lastSyncAttempt == nil {
            lastSyncAttempt = previousAttempt
        }
    }
    
    /// Get a human-readable description of the current sync interval
    var syncIntervalDescription: String {
        let seconds = Int(syncInterval)
        if seconds < 60 {
            return "\(seconds) second\(seconds == 1 ? "" : "s")"
        } else {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
    }
    
    /// Get time until next sync (for display in UI)
    var timeUntilNextSync: TimeInterval? {
        guard autoSyncEnabled, let lastSync = lastSyncDate else { return nil }
        let nextSyncTime = lastSync.addingTimeInterval(syncInterval)
        return nextSyncTime.timeIntervalSinceNow
    }
    
    // MARK: - Community Recipes Sync (Temporary Cache)
    
    /// Sync community recipes for viewing (not permanent import)
    /// Creates temporary cache for viewing, cooking, etc. with automatic cleanup
    /// Uses pagination to fetch all available recipes efficiently
    func syncCommunityRecipesForViewing(modelContext: ModelContext, limit: Int = Int.max, includeSelf: Bool = true) async throws {
        guard isCloudKitAvailable else {
            throw SharingError.cloudKitUnavailable()
        }

        let isFetchingAll = limit == Int.max
        AppLog.info("📖 SYNC: Syncing community recipes for viewing\(isFetchingAll ? " (ALL recipes)" : " (limit: \(limit))")\(includeSelf ? " incl. self" : "")...", category: .sharing)

        // Fetch shared recipes from CloudKit with pagination
        // The fetchSharedRecipes method automatically handles pagination in batches of 100.
        // Communal library: includeSelf == true pulls the current user's own shared recipes too.
        let cloudRecipes = try await fetchSharedRecipes(limit: limit, excludeCurrentUser: !includeSelf)
        let recipesToCache = isFetchingAll ? cloudRecipes : Array(cloudRecipes.prefix(limit))
        
        AppLog.info("📖 SYNC: Found \(cloudRecipes.count) community recipes, caching \(recipesToCache.count)", category: .sharing)
        
        // Fetch existing cached recipes
        let existingCached = try modelContext.fetch(FetchDescriptor<CachedSharedRecipe>())
        var existingByID = [UUID: CachedSharedRecipe]()
        for cached in existingCached {
            existingByID[cached.id] = cached
        }
        
        // Track which recipes are still in CloudKit
        var currentCloudRecipeIDs = Set<UUID>()
        
        var addedCount = 0
        var updatedCount = 0
        
        // Process each CloudKit recipe
        for cloudRecipe in recipesToCache {
            currentCloudRecipeIDs.insert(cloudRecipe.id)
            
            if let existingCached = existingByID[cloudRecipe.id] {
                // Update existing cache
                existingCached.title = cloudRecipe.title
                existingCached.headerNotes = cloudRecipe.headerNotes
                existingCached.yield = cloudRecipe.yield
                existingCached.ingredientSections = cloudRecipe.ingredientSections
                existingCached.instructionSections = cloudRecipe.instructionSections
                existingCached.notes = cloudRecipe.notes
                existingCached.reference = cloudRecipe.reference
                existingCached.imageName = cloudRecipe.imageName
                existingCached.additionalImageNames = cloudRecipe.additionalImageNames
                existingCached.sharedByUserName = cloudRecipe.sharedByUserName
                existingCached.cachedDate = Date()
                // Carry through the downloaded image asset so thumbnails appear
                if let imageData = cloudRecipe.imageData {
                    existingCached.imageData = imageData
                }
                updatedCount += 1
                AppLog.info("📖   Updated cached recipe: '\(cloudRecipe.title)'\(cloudRecipe.imageData != nil ? " (with image)" : "")", category: .sharing)
            } else {
                // Create new cached recipe
                let newCached = CachedSharedRecipe(from: cloudRecipe)
                // Carry through the downloaded image asset so thumbnails appear
                if let imageData = cloudRecipe.imageData {
                    newCached.imageData = imageData
                }
                modelContext.insert(newCached)
                addedCount += 1
                AppLog.info("📖   Cached new recipe: '\(cloudRecipe.title)' by \(cloudRecipe.sharedByUserName ?? "Unknown")\(cloudRecipe.imageData != nil ? " (with image)" : "")", category: .sharing)
            }
        }
        
        // Clean up cached recipes that are no longer available or old
        var removedCount = 0
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        for cached in existingCached {
            let shouldRemove = !currentCloudRecipeIDs.contains(cached.id) || cached.lastAccessedDate < thirtyDaysAgo
            
            if shouldRemove {
                modelContext.delete(cached)
                removedCount += 1
                AppLog.info("📖   Removed cached recipe: '\(cached.title)'", category: .sharing)
            }
        }
        
        try modelContext.save()
        
        AppLog.info("✅ SYNC COMPLETE: Community recipes cached for viewing", category: .sharing)
        AppLog.info("   - Added: \(addedCount) recipes", category: .sharing)
        AppLog.info("   - Updated: \(updatedCount) recipes", category: .sharing)
        AppLog.info("   - Removed: \(removedCount) recipes", category: .sharing)
    }
    
    /// Update last accessed date for a cached recipe (prevents auto-cleanup)
    func markCachedRecipeAsAccessed(_ recipeID: UUID, modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<CachedSharedRecipe>(
            predicate: #Predicate<CachedSharedRecipe> { $0.id == recipeID }
        )
        
        if let cached = try modelContext.fetch(descriptor).first {
            cached.lastAccessedDate = Date()
            try modelContext.save()
            AppLog.info("📖 Marked cached recipe as accessed: '\(cached.title)'", category: .sharing)
        }
    }
    
    /// Convert a cached recipe to permanent import
    func importCachedRecipe(_ cachedRecipe: CachedSharedRecipe, modelContext: ModelContext) throws {
        // Create RecipeX directly from cached data
        let encoder = JSONEncoder()
        
        let recipe = RecipeX(
            id: UUID(), // New ID - independent copy
            title: cachedRecipe.title,
            headerNotes: cachedRecipe.headerNotes,
            recipeYield: cachedRecipe.yield,
            reference: cachedRecipe.reference,
            ingredientSectionsData: try? encoder.encode(cachedRecipe.ingredientSections),
            instructionSectionsData: try? encoder.encode(cachedRecipe.instructionSections),
            notesData: try? encoder.encode(cachedRecipe.notes),
            imageName: cachedRecipe.imageName,
            additionalImageNames: cachedRecipe.additionalImageNames
        )
        
        modelContext.insert(recipe)
        try modelContext.save()
        
        AppLog.info("Imported cached recipe to permanent collection: \(cachedRecipe.title)", category: .sharing)
    }
    
    /// Clean up old cached recipes (not accessed in 30 days)
    func cleanupOldCachedRecipes(modelContext: ModelContext) throws {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        let descriptor = FetchDescriptor<CachedSharedRecipe>(
            predicate: #Predicate<CachedSharedRecipe> { recipe in
                recipe.lastAccessedDate < thirtyDaysAgo
            }
        )
        
        let oldRecipes = try modelContext.fetch(descriptor)
        
        for recipe in oldRecipes {
            modelContext.delete(recipe)
        }
        
        try modelContext.save()
        
        AppLog.info("🧹 Cleaned up \(oldRecipes.count) old cached recipes", category: .sharing)
    }
    
    // MARK: - Community Books Sync
    
    /// Sync community recipe books from CloudKit to local SwiftData
    /// This allows shared books to appear in the Books view's "Shared" tab
    /// Phase 4: Enhanced with recipe previews and thumbnail downloads
    func syncCommunityBooksToLocal(modelContext: ModelContext) async throws {
        guard isCloudKitAvailable else {
            throw SharingError.cloudKitUnavailable()
        }
        
        AppLog.info("📚 SYNC: Starting enhanced community books sync to local SwiftData...", category: .sharing)
        
        // Step 1: Fetch all CloudKit records (including assets)
        AppLog.info("📚 Step 1: Fetching CloudKit records with assets...", category: .sharing)
        let allCloudKitRecords = try await fetchAllCloudKitRecords(type: CloudKitRecordType.sharedRecipeBook)
        
        // Filter to exclude current user's books
        let communityRecords = allCloudKitRecords.filter { record in
            guard let sharedBy = record["sharedBy"] as? String else { return false }
            return sharedBy != currentUserID
        }
        
        AppLog.info("📚 Found \(communityRecords.count) community book records in CloudKit", category: .sharing)
        
        // Fetch all existing SharedRecipeBook records that are shared by others
        let existingSharedBooks = try modelContext.fetch(
            FetchDescriptor<SharedRecipeBook>(
                predicate: #Predicate<SharedRecipeBook> { book in
                    book.sharedByUserID != nil && book.isActive == true
                }
            )
        )
        
        // Fetch all existing RecipeBook records
        let allRecipeBooks = try modelContext.fetch(FetchDescriptor<Book>())
        
        // Fetch all existing CloudKitRecipePreview records
        let allPreviews = try modelContext.fetch(FetchDescriptor<CloudKitRecipePreview>())
        
        // Create dictionaries for quick lookup
        var existingSharedBooksByID = [UUID: SharedRecipeBook]()
        var existingRecipeBooksByID = [UUID: Book]()
        var existingPreviewsByBookID = [UUID: [CloudKitRecipePreview]]()
        
        for book in existingSharedBooks {
            if let bookID = book.bookID {
                existingSharedBooksByID[bookID] = book
            }
        }
        
        for book in allRecipeBooks {
            existingRecipeBooksByID[book.id!] = book
        }
        
        for preview in allPreviews {
            if let bookID = preview.bookID {
                existingPreviewsByBookID[bookID, default: []].append(preview)
            }
        }
        
        AppLog.info("📚 SYNC: Found \(existingSharedBooks.count) existing community book tracking records", category: .sharing)
        AppLog.info("📚 SYNC: Found \(allRecipeBooks.count) total RecipeBook entries", category: .sharing)
        AppLog.info("📚 SYNC: Found \(allPreviews.count) existing recipe previews", category: .sharing)
        
        // Track which CloudKit books we've seen (to identify books to remove)
        var cloudKitBookIDs = Set<UUID>()
        
        var addedCount = 0
        var updatedCount = 0
        var previewsCreated = 0
        var thumbnailsDownloaded = 0
        
        // Step 2-6: Process each CloudKit book record
        for record in communityRecords {
            // Parse book data
            guard let bookData = record["bookData"] as? String,
                  let jsonData = bookData.data(using: .utf8),
                  let cloudBook = try? JSONDecoder().decode(CloudKitRecipeBook.self, from: jsonData) else {
                AppLog.warning("📚 Skipping invalid book record: \(record.recordID.recordName)", category: .sharing)
                continue
            }
            
            cloudKitBookIDs.insert(cloudBook.id)
            let cloudRecordID = record.recordID.recordName
            
            AppLog.info("📚 Processing book: '\(cloudBook.name)' (\(cloudBook.recipeIDs.count) recipes)", category: .sharing)
            
            // Step 2: Download cover image
            if let coverImageAsset = record["coverImage"] as? CKAsset,
               let coverImageURL = coverImageAsset.fileURL,
               let coverImageData = try? Data(contentsOf: coverImageURL) {
                // Save cover image to local storage
                let coverImageName = "shared_cover_\(cloudBook.id).jpg"
                try? saveImageToDocuments(data: coverImageData, filename: coverImageName)
                AppLog.info("📚   ✅ Downloaded cover image: \(coverImageName)", category: .sharing)
            }
            
            // Step 3: Parse recipe previews JSON
            var recipePreviews: [RecipePreviewData] = []
            if let previewsJSON = record["recipePreviews"] as? String,
               let previewsData = previewsJSON.data(using: .utf8),
               let previews = try? JSONDecoder().decode([RecipePreviewData].self, from: previewsData) {
                recipePreviews = previews
                AppLog.info("📚   ✅ Parsed \(previews.count) recipe previews", category: .sharing)
            } else {
                AppLog.warning("📚   ⚠️ No recipe previews found in record", category: .sharing)
            }
            
            // Check if RecipeBook entity exists
            let book: Book
            if let existingRecipeBook = existingRecipeBooksByID[cloudBook.id] {
                book = existingRecipeBook
                
                // Update RecipeBook properties if needed
                var needsUpdate = false
                if book.name != cloudBook.name {
                    book.name = cloudBook.name
                    needsUpdate = true
                }
                if book.bookDescription != cloudBook.bookDescription {
                    book.bookDescription = cloudBook.bookDescription
                    needsUpdate = true
                }
                if book.color != cloudBook.color {
                    book.color = cloudBook.color
                    needsUpdate = true
                }
                
                // Ensure owner information is set for shared books
                if book.ownerUserID != cloudBook.sharedByUserID {
                    book.ownerUserID = cloudBook.sharedByUserID
                    needsUpdate = true
                }
                if book.ownerDisplayName != cloudBook.sharedByUserName {
                    book.ownerDisplayName = cloudBook.sharedByUserName
                    needsUpdate = true
                }
                
                if needsUpdate {
                    book.dateModified = Date()
                    updatedCount += 1
                    AppLog.info("📚   Updated RecipeBook: '\(cloudBook.name)'", category: .sharing)
                }
            } else {
                // Create new Book entity
                let coverImageName = "shared_cover_\(cloudBook.id).jpg"
                book = Book(
                    id: cloudBook.id,
                    name: cloudBook.name,
                    bookDescription: cloudBook.bookDescription,
                    coverImageName: coverImageName,
                    color: cloudBook.color, recipeIDs: cloudBook.recipeIDs, dateCreated: cloudBook.sharedDate,
                    dateModified: cloudBook.sharedDate
                )
                
                // Set owner information for shared books
                book.ownerUserID = cloudBook.sharedByUserID
                book.ownerDisplayName = cloudBook.sharedByUserName
                
                modelContext.insert(book)
                addedCount += 1
                AppLog.info("📚   Created RecipeBook: '\(cloudBook.name)' by \(cloudBook.sharedByUserName ?? "Unknown")", category: .sharing)
            }
            
            // Check if SharedRecipeBook tracking entry exists
            if let existingSharedBook = existingSharedBooksByID[cloudBook.id] {
                // Update existing tracking entry if needed
                var needsUpdate = false
                
                if existingSharedBook.bookName != cloudBook.name {
                    existingSharedBook.bookName = cloudBook.name
                    needsUpdate = true
                }
                
                if existingSharedBook.bookDescription != cloudBook.bookDescription {
                    existingSharedBook.bookDescription = cloudBook.bookDescription
                    needsUpdate = true
                }
                
                if existingSharedBook.sharedByUserName != cloudBook.sharedByUserName {
                    existingSharedBook.sharedByUserName = cloudBook.sharedByUserName
                    needsUpdate = true
                }
                
                if existingSharedBook.cloudRecordID != cloudRecordID {
                    existingSharedBook.cloudRecordID = cloudRecordID
                    needsUpdate = true
                }
                
                if needsUpdate {
                    AppLog.info("📚   Updated SharedRecipeBook tracking: '\(cloudBook.name)'", category: .sharing)
                }
            } else {
                // Create new SharedRecipeBook tracking entry
                let newSharedBook = SharedRecipeBook(
                    bookID: cloudBook.id,
                    cloudRecordID: cloudRecordID,
                    sharedByUserID: cloudBook.sharedByUserID,
                    sharedByUserName: cloudBook.sharedByUserName,
                    sharedDate: cloudBook.sharedDate,
                    bookName: cloudBook.name,
                    bookDescription: cloudBook.bookDescription,
                    coverImageName: cloudBook.coverImageName
                )
                
                modelContext.insert(newSharedBook)
                AppLog.info("📚   Created SharedRecipeBook tracking: '\(cloudBook.name)' by \(cloudBook.sharedByUserName ?? "Unknown")", category: .sharing)
            }
            
            // Step 4-5: Decode thumbnails from base64 and create CloudKitRecipePreview entries
            if !recipePreviews.isEmpty {
                // Delete old previews for this book
                if let oldPreviews = existingPreviewsByBookID[cloudBook.id] {
                    for oldPreview in oldPreviews {
                        modelContext.delete(oldPreview)
                    }
                }
                
                // Create new previews
                for previewData in recipePreviews {
                    // Step 4: Decode thumbnail from base64
                    var thumbnailData: Data?
                    if let base64String = previewData.thumbnailBase64,
                       let data = Data(base64Encoded: base64String) {
                        thumbnailData = data
                        thumbnailsDownloaded += 1
                        AppLog.info("📚     ✅ Decoded thumbnail: '\(previewData.title)'", category: .sharing)
                    } else {
                        AppLog.info("📚     ⚪️ No thumbnail for '\(previewData.title)'", category: .sharing)
                    }
                    
                    // Step 5: Create CloudKitRecipePreview entry
                    let preview = CloudKitRecipePreview(
                        id: previewData.id,
                        title: previewData.title,
                        headerNotes: previewData.headerNotes,
                        imageName: previewData.imageName,
                        imageData: thumbnailData,
                        sharedByUserID: cloudBook.sharedByUserID,
                        sharedByUserName: cloudBook.sharedByUserName,
                        recipeYield: previewData.recipeYield,
                        bookID: cloudBook.id,
                        cloudRecordID: previewData.cloudRecordID
                    )
                    
                    modelContext.insert(preview)
                    previewsCreated += 1
                }
                
                AppLog.info("📚   ✅ Created \(recipePreviews.count) recipe previews", category: .sharing)
            }
        }
        
        // Find and remove books that are no longer in CloudKit
        var removedCount = 0
        for existingSharedBook in existingSharedBooks {
            guard let bookID = existingSharedBook.bookID else { continue }
            
            // If this book is not in CloudKit anymore, mark it as inactive and delete the RecipeBook
            if !cloudKitBookIDs.contains(bookID) {
                // Only remove books shared by others, not the current user's own shared books
                if existingSharedBook.sharedByUserID != currentUserID {
                    AppLog.info("📚   Removing book (no longer shared): '\(existingSharedBook.bookName)'", category: .sharing)
                    
                    // Step 1: Delete associated recipe previews
                    if let previews = existingPreviewsByBookID[bookID] {
                        AppLog.info("📚     Deleting \(previews.count) recipe previews", category: .sharing)
                        for preview in previews {
                            modelContext.delete(preview)
                        }
                    }
                    
                    // Step 2: Delete the RecipeBook entity and its cover image
                    if let recipeBook = existingRecipeBooksByID[bookID] {
                        // Try to delete cover image file if it exists
                        if let coverImageName = recipeBook.coverImageName {
                            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            let fileURL = documentsPath.appendingPathComponent(coverImageName)
                            do {
                                try FileManager.default.removeItem(at: fileURL)
                                AppLog.info("📚     Deleted cover image: \(coverImageName)", category: .sharing)
                            } catch {
                                // File might not exist, which is fine
                                AppLog.debug("📚     Cover image file not found (already deleted): \(error)", category: .sharing)
                            }
                        }
                        
                        // Note: We intentionally DO NOT delete the Recipe entities themselves
                        // because they might be used in other books or standalone.
                        // Only delete the book container.
                        AppLog.info("📚     Deleting RecipeBook entity", category: .sharing)
                        modelContext.delete(recipeBook)
                    } else {
                        // RecipeBook might have already been deleted, but tracking remains
                        AppLog.warning("📚     RecipeBook entity not found (might have been already deleted)", category: .sharing)
                    }
                    
                    // Step 3: Delete the tracking entry completely (not just marking inactive)
                    // This ensures the book disappears from ALL tabs, including "All"
                    AppLog.info("📚     Deleting SharedRecipeBook tracking entry", category: .sharing)
                    modelContext.delete(existingSharedBook)
                    
                    removedCount += 1
                    AppLog.info("📚   ✅ Removed book '\(existingSharedBook.bookName)' and cleaned up associated data", category: .sharing)
                }
            }
        }
        
        // Save changes with error handling
        do {
            try modelContext.save()
            AppLog.info("✅ SYNC COMPLETE: Enhanced community books sync finished", category: .sharing)
        } catch {
            AppLog.error("❌ Failed to save sync changes: \(error)", category: .sharing)
            // Try to rollback to prevent partial state
            modelContext.rollback()
            throw error
        }
        
        AppLog.info("   - Added: \(addedCount) books", category: .sharing)
        AppLog.info("   - Updated: \(updatedCount) books", category: .sharing)
        AppLog.info("   - Removed: \(removedCount) books", category: .sharing)
        AppLog.info("   - Recipe previews created: \(previewsCreated)", category: .sharing)
        AppLog.info("   - Thumbnails decoded: \(thumbnailsDownloaded)", category: .sharing)
    }
    
    /// Helper: Save image data to Documents directory
    private func saveImageToDocuments(data: Data, filename: String) throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        try data.write(to: fileURL)
    }
    
    /// Helper: Create a small thumbnail from an image.
    /// Prefers the file on disk at `imageName`; falls back to `imageData` when the file
    /// is missing (e.g. recipes stored exclusively via SwiftData after setImage()).
    /// Returns JPEG data resized to maxSize (width/height), compressed to keep file size small.
    private func createThumbnail(for imageName: String?, imageData: Data?, maxSize: CGFloat = 200) -> Data? {
        var image: UIImage?

        // --- Try the on-disk file first ---
        if let imageName = imageName {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let imageURL = documentsPath.appendingPathComponent(imageName)

            if FileManager.default.fileExists(atPath: imageURL.path),
               let diskData = try? Data(contentsOf: imageURL) {
                image = UIImage(data: diskData)
            }
        }

        // --- Fall back to inline imageData ---
        if image == nil, let data = imageData {
            image = UIImage(data: data)
        }

        guard let sourceImage = image else { return nil }

        // Use centralized compression utility for thumbnails
        return ImageCompressionUtility.compressForThumbnail(sourceImage)
    }
    
    /// Remove orphaned recipes from CloudKit (recipes with invalid/missing sharedByUserID)
    func removeOrphanedRecipes() async throws {
        AppLog.info("🧹 ORPHAN CLEANUP: Starting orphan detection...", category: .sharing)
        
        guard currentUserID != nil else {
            throw SharingError.notAuthenticated
        }
        
        // Fetch all CloudKit records
        let allRecords = try await fetchAllCloudKitRecords(type: CloudKitRecordType.sharedRecipe)
        AppLog.info("🧹 Found \(allRecords.count) total records in CloudKit", category: .sharing)
        
        var orphanedRecords: [CKRecord.ID] = []
        var validUserIDs = Set<String>()
        
        // Identify orphans
        for record in allRecords {
            guard let sharedBy = record["sharedBy"] as? String,
                  !sharedBy.isEmpty else {
                // No valid sharedByUserID - this is an orphan
                orphanedRecords.append(record.recordID)
                AppLog.warning("🧹 Found orphan (no sharedBy): \(record.recordID.recordName)", category: .sharing)
                continue
            }
            
            // Track valid user IDs
            validUserIDs.insert(sharedBy)
        }
        
        AppLog.info("🧹 Found \(orphanedRecords.count) orphaned records", category: .sharing)
        AppLog.info("🧹 Found \(validUserIDs.count) distinct valid users", category: .sharing)
        
        // Delete orphans
        if !orphanedRecords.isEmpty {
            AppLog.info("🧹 Deleting \(orphanedRecords.count) orphaned records...", category: .sharing)
            
            let batches = stride(from: 0, to: orphanedRecords.count, by: 100).map {
                Array(orphanedRecords[$0..<min($0 + 100, orphanedRecords.count)])
            }
            
            for (index, batch) in batches.enumerated() {
                do {
                    _ = try await publicDatabase.modifyRecords(saving: [], deleting: batch)
                    AppLog.info("🧹 Deleted orphan batch \(index + 1)/\(batches.count) (\(batch.count) records)", category: .sharing)
                } catch {
                    AppLog.error("🧹 Failed to delete orphan batch \(index + 1): \(error)", category: .sharing)
                }
            }
            
            AppLog.info("✅ Orphan cleanup complete: Removed \(orphanedRecords.count) orphans", category: .sharing)
        } else {
            AppLog.info("✅ No orphans found - CloudKit is clean!", category: .sharing)
        }
    }
    
    /// Clean up all stale shared content and re-sync from CloudKit
    /// WARNING: This removes ALL local sharing tracking and rebuilds from CloudKit truth
    func cleanupAndResyncSharing(modelContext: ModelContext) async throws {
        AppLog.info("🧹 CLEANUP: Starting comprehensive sharing cleanup...", category: .sharing)
        
        guard let currentUserID = currentUserID else {
            throw SharingError.notAuthenticated
        }
        
        // Step 0: Check for duplicate local Recipe records first
        AppLog.info("🧹 Step 0: Checking for duplicate local Recipe records...", category: .sharing)
        let allLocalRecipes = try modelContext.fetch(FetchDescriptor<RecipeX>())
        let uniqueRecipeIDs = Set(allLocalRecipes.compactMap { $0.id })
        let duplicateCount = allLocalRecipes.count - uniqueRecipeIDs.count
        
        if duplicateCount > 0 {
            AppLog.warning("🧹 Found \(duplicateCount) duplicate Recipe records in local database!", category: .sharing)
            AppLog.warning("🧹 ⚠️ IMPORTANT: You have \(allLocalRecipes.count) recipes but only \(uniqueRecipeIDs.count) unique IDs", category: .sharing)
            AppLog.warning("🧹 Please use Settings → Database Recovery to clean up local duplicates first", category: .sharing)
            throw SharingError.invalidData
        }
        
        AppLog.info("🧹 Local database clean: \(allLocalRecipes.count) recipes, all unique ✅", category: .sharing)
        
        // Step 1: Delete ALL local SharedRecipe tracking records
        AppLog.info("🧹 Step 1: Removing all local SharedRecipe tracking...", category: .sharing)
        let allSharedRecipes = try modelContext.fetch(FetchDescriptor<SharedRecipe>())
        let allSharedBooks = try modelContext.fetch(FetchDescriptor<SharedRecipeBook>())
        
        for recipe in allSharedRecipes {
            modelContext.delete(recipe)
        }
        for book in allSharedBooks {
            modelContext.delete(book)
        }
        try modelContext.save()
        AppLog.info("🧹 Deleted \(allSharedRecipes.count) SharedRecipe and \(allSharedBooks.count) SharedRecipeBook tracking records", category: .sharing)
        
        // Step 2: Fetch ALL records from CloudKit public database
        AppLog.info("🧹 Step 2: Fetching all CloudKit public database records...", category: .sharing)
        let allCloudRecipes = try await fetchAllCloudKitRecords(type: CloudKitRecordType.sharedRecipe)
        AppLog.info("🧹 Found \(allCloudRecipes.count) total records in CloudKit public database", category: .sharing)
        
        // Step 3: Find and delete duplicates + records not owned by current user
        AppLog.info("🧹 Step 3: Identifying stale and duplicate records...", category: .sharing)
        
        // Group by recipe ID to find duplicates
        var recordsToKeep: [CKRecord.ID] = []
        var recordsToDelete: [CKRecord.ID] = []
        var seenRecipeIDs: [UUID: CKRecord] = [:]
        
        for record in allCloudRecipes {
            guard let recipeData = record["recipeData"] as? String,
                  let jsonData = recipeData.data(using: .utf8),
                  let cloudRecipe = try? JSONDecoder().decode(CloudKitRecipe.self, from: jsonData) else {
                // Invalid record - delete it
                recordsToDelete.append(record.recordID)
                AppLog.warning("🧹 Marking invalid record for deletion: \(record.recordID.recordName)", category: .sharing)
                continue
            }
            
            let sharedBy = record["sharedBy"] as? String ?? ""
            let isMyRecord = sharedBy == currentUserID
            
            // Check if we've seen this recipe ID before
            if let existingRecord = seenRecipeIDs[cloudRecipe.id] {
                // Duplicate found!
                let existingSharedBy = existingRecord["sharedBy"] as? String ?? ""
                
                if isMyRecord && existingSharedBy != currentUserID {
                    // Keep mine, delete the other
                    recordsToDelete.append(existingRecord.recordID)
                    seenRecipeIDs[cloudRecipe.id] = record
                    recordsToKeep.append(record.recordID)
                    AppLog.info("🧹 Duplicate: Keeping my record, deleting other for recipe \(cloudRecipe.title)", category: .sharing)
                } else if existingSharedBy == currentUserID && !isMyRecord {
                    // Keep existing (mine), delete this one
                    recordsToDelete.append(record.recordID)
                    AppLog.info("🧹 Duplicate: Keeping existing record, deleting duplicate for recipe \(cloudRecipe.title)", category: .sharing)
                } else {
                    // Both from same user - keep newer one
                    let existingDate = existingRecord["sharedDate"] as? Date ?? Date.distantPast
                    let currentDate = record["sharedDate"] as? Date ?? Date.distantPast
                    
                    if currentDate > existingDate {
                        recordsToDelete.append(existingRecord.recordID)
                        seenRecipeIDs[cloudRecipe.id] = record
                        recordsToKeep.append(record.recordID)
                    } else {
                        recordsToDelete.append(record.recordID)
                    }
                    AppLog.info("🧹 Duplicate: Keeping newer record for recipe \(cloudRecipe.title)", category: .sharing)
                }
            } else {
                // First time seeing this recipe ID
                seenRecipeIDs[cloudRecipe.id] = record
                recordsToKeep.append(record.recordID)
            }
        }
        
        // Step 4: Delete stale/duplicate records from CloudKit
        AppLog.info("🧹 Step 4: Deleting \(recordsToDelete.count) stale/duplicate records from CloudKit...", category: .sharing)
        
        if !recordsToDelete.isEmpty {
            // Delete in batches of 100
            let batches = stride(from: 0, to: recordsToDelete.count, by: 100).map {
                Array(recordsToDelete[$0..<min($0 + 100, recordsToDelete.count)])
            }
            
            for (index, batch) in batches.enumerated() {
                do {
                    _ = try await publicDatabase.modifyRecords(saving: [], deleting: batch)
                    AppLog.info("🧹 Deleted batch \(index + 1)/\(batches.count) (\(batch.count) records)", category: .sharing)
                } catch {
                    AppLog.error("🧹 Failed to delete batch \(index + 1): \(error)", category: .sharing)
                }
            }
        }
        
        // Step 5: Rebuild local tracking from clean CloudKit data
        AppLog.info("🧹 Step 5: Rebuilding local SharedRecipe tracking from \(seenRecipeIDs.count) clean records...", category: .sharing)
        
        for (_, record) in seenRecipeIDs {
            guard let recipeData = record["recipeData"] as? String,
                  let jsonData = recipeData.data(using: .utf8),
                  let cloudRecipe = try? JSONDecoder().decode(CloudKitRecipe.self, from: jsonData) else {
                continue
            }
            
            let sharedBy = record["sharedBy"] as? String ?? ""
            let isMyRecord = sharedBy == currentUserID
            
            if isMyRecord {
                // Track my own shared recipe
                let sharedRecipe = SharedRecipe(
                    recipeID: cloudRecipe.id,
                    cloudRecordID: record.recordID.recordName,
                    sharedByUserID: currentUserID,
                    sharedByUserName: currentUserName,
                    sharedDate: record["sharedDate"] as? Date ?? Date(),
                    recipeTitle: cloudRecipe.title,
                    recipeImageName: cloudRecipe.imageName
                )
                modelContext.insert(sharedRecipe)
            }
        }
        
        try modelContext.save()
        
        AppLog.info("✅ CLEANUP COMPLETE: Removed \(recordsToDelete.count) duplicates, kept \(seenRecipeIDs.count) clean records", category: .sharing)
        AppLog.info("✅ You should now see accurate counts: Mine=\(seenRecipeIDs.values.filter { ($0["sharedBy"] as? String) == currentUserID }.count), Shared=\(seenRecipeIDs.count)", category: .sharing)
    }
    
    /// Fetch all CloudKit records of a given type (with pagination)
    /// 
    /// ⚠️ IMPORTANT: CloudKit Schema Configuration Required
    /// If you get "Field 'recordName' is not marked queryable" errors:
    /// 1. Go to CloudKit Dashboard: https://icloud.developer.apple.com/dashboard
    /// 2. Select your container: iCloud.com.headydiscy.reczipes
    /// 3. Go to Schema → Indexes
    /// 4. For each Record Type (SharedRecipe, SharedRecipeBook):
    ///    - Add QUERYABLE index on "recordName" field
    ///    - Add SORTABLE index on "sharedDate" field  
    ///    - Deploy to Production
    private func fetchAllCloudKitRecords(type: String) async throws -> [CKRecord] {
        AppLog.info("📦 Fetching all '\(type)' records from CloudKit Public Database...", category: .sharing)
        
        var allRecords: [CKRecord] = []
        
        // Create the most basic query - no sort, no filters
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: type, predicate: predicate)
        
        // Fetch initial batch
        var currentCursor: CKQueryOperation.Cursor?
        let batchSize = 100
        var batchNumber = 1
        
        do {
            // Initial query
            let results = try await publicDatabase.records(matching: query, desiredKeys: nil, resultsLimit: batchSize)
            
            // Process initial batch
            for (_, result) in results.matchResults {
                switch result {
                case .success(let record):
                    allRecords.append(record)
                case .failure(let error):
                    AppLog.error("❌ Error fetching record: \(error)", category: .sharing)
                }
            }
            
            currentCursor = results.queryCursor
            AppLog.info("📦 Batch #\(batchNumber): Fetched \(results.matchResults.count) records, total: \(allRecords.count)", category: .sharing)
            
            // Continue with cursor if available
            while let cursor = currentCursor {
                batchNumber += 1
                
                let nextResults = try await publicDatabase.records(
                    continuingMatchFrom: cursor,
                    desiredKeys: nil,
                    resultsLimit: batchSize
                )
                
                // Process batch
                for (_, result) in nextResults.matchResults {
                    switch result {
                    case .success(let record):
                        allRecords.append(record)
                    case .failure(let error):
                        AppLog.error("❌ Error fetching record: \(error)", category: .sharing)
                    }
                }
                
                currentCursor = nextResults.queryCursor
                AppLog.info("📦 Batch #\(batchNumber): Fetched \(nextResults.matchResults.count) records, total: \(allRecords.count)", category: .sharing)
                
                // Safety: prevent infinite loops
                if batchNumber > 100 {
                    AppLog.warning("📦 Reached maximum batch limit (100), stopping pagination", category: .sharing)
                    break
                }
            }
            
            // Sort in memory by date
            let sorted = allRecords.sorted { r1, r2 in
                let date1 = r1["sharedDate"] as? Date ?? .distantPast
                let date2 = r2["sharedDate"] as? Date ?? .distantPast
                return date1 > date2
            }
            
            AppLog.info("✅ Fetched all \(sorted.count) '\(type)' records in \(batchNumber) batches", category: .sharing)
            return sorted
            
        } catch let error as CKError {
            AppLog.error("❌ CloudKit query failed for '\(type)': \(error)", category: .sharing)
            
            // Check if it's the "recordName not queryable" error
            if error.code == .invalidArguments {
                let errorMessage = error.localizedDescription
                if errorMessage.contains("recordName") || errorMessage.contains("queryable") {
                    throw SharingError.cloudKitUnavailable(
                        message: "CloudKit schema not configured. Please add queryable indexes in CloudKit Dashboard for record type '\(type)'. See CloudKitSharingService.swift for instructions."
                    )
                }
            }
            
            throw error
        }
    }
    
    /// Decode note strings encoded as "[type] text" back into RecipeNote objects.
    /// This is the inverse of the encoding done in shareRecipe:
    ///     "[\(note.type.rawValue)] \(note.text)"
    static func decodeNoteStrings(_ noteStrings: [String]?) -> [RecipeNote] {
        guard let strings = noteStrings else { return [] }
        return strings.compactMap { string in
            // Expected format: "[rawValue] text"
            guard string.hasPrefix("["),
                  let closingIndex = string.firstIndex(of: "]") else {
                // No valid prefix – fall back to a general note with the full string
                return RecipeNote(type: .general, text: string)
            }
            let typeStart = string.index(after: string.startIndex)
            let rawValue = String(string[typeStart..<closingIndex])
            guard let noteType = RecipeNoteType(rawValue: rawValue) else {
                return RecipeNote(type: .general, text: string)
            }
            // Text begins after "] " (skip the space if present)
            let afterBracket = string.index(after: closingIndex)
            let textStart = afterBracket < string.endIndex && string[afterBracket] == " "
                ? string.index(after: afterBracket)
                : afterBracket
            let text = String(string[textStart...])
            return RecipeNote(type: noteType, text: text)
        }
    }

    /// Import a shared recipe into the user's local collection
    func importSharedRecipe(_ cloudRecipe: CloudKitRecipe, modelContext: ModelContext) async throws {
        // Create RecipeX directly from CloudKitRecipe
        let encoder = JSONEncoder()
        
        // Encode notes directly — CloudKitRecipe.notes is already [RecipeNote].
        let notesData = try? encoder.encode(cloudRecipe.notes)
        
        let recipe = RecipeX(
            id: UUID(), // Generate new ID (don't conflict with original)
            title: "\(cloudRecipe.title) (from \(cloudRecipe.sharedByUserName ?? "community"))",
            headerNotes: cloudRecipe.headerNotes,
            recipeYield: cloudRecipe.yield,
            reference: cloudRecipe.reference,
            ingredientSectionsData: try? encoder.encode(cloudRecipe.ingredientSections),
            instructionSectionsData: try? encoder.encode(cloudRecipe.instructionSections),
            notesData: notesData,
            imageName: cloudRecipe.imageName,
            additionalImageNames: cloudRecipe.additionalImageNames
        )
 
        modelContext.insert(recipe)
        try modelContext.save()
        
        AppLog.info("Imported shared recipe: \(cloudRecipe.title)", category: .sharing)
    }
}
