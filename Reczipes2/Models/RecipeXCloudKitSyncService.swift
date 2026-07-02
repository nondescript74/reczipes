//
//  RecipeXCloudKitSyncService.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/26/26.
//
//  Automatic CloudKit sync service for RecipeX models
//  Monitors `needsCloudSync` flag and uploads recipes to iCloud Public Database

import Foundation
import SwiftData
import CloudKit
import Combine

/// Service that automatically syncs RecipeX models to CloudKit Public Database
///
/// ⚠️ DEPRECATED (2026-07-01): This service writes a non-consensual, write-only `RecipeX`
/// public corpus that nothing reads back (`startAutomaticSync` has no callers). Communal
/// sharing is now unified on the consent-gated `sharedRecipe` path (CloudKitSharingService,
/// SharingPreferences.shareAllRecipes / browseCommunity). Do NOT re-wire `startAutomaticSync`
/// into app startup — doing so would publish every recipe to the public database regardless
/// of user consent, violating the opt-in sharing model. Retained only for reference/removal.
/// See Docs/COMMUNAL_LIBRARY_SPEC.md.
///
/// DESIGN (historical):
/// - Monitors SwiftData for RecipeX models with `needsCloudSync = true`
/// - Uploads/updates recipes in CloudKit Public Database
/// - Handles conflicts, retries, and error logging
/// - Runs automatically in background with periodic checks
@MainActor
class RecipeXCloudKitSyncService: ObservableObject {
    
    static let shared = RecipeXCloudKitSyncService()
    
    // MARK: - Published State
    
    @Published private(set) var isSyncing = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastError: String?
    
    // MARK: - Private Properties
    
    private let publicDatabase = CKContainer(identifier: "iCloud.com.headydiscy.reczipes").publicCloudDatabase
    private var syncTimer: Timer?
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    
    // Configuration
    private let syncInterval: TimeInterval = 60 // Sync every 60 seconds
    private let maxRetries = 3
    private let batchSize = 10 // Upload 10 recipes at a time
    
    // MARK: - Initialization
    
    private init() {
        AppLog.info("📤 RecipeXCloudKitSyncService initialized", category: .cloudKit)
    }
    
    // MARK: - Public API
    
    /// Start automatic sync service
    /// Call this from your App init or when the app becomes active
    func startAutomaticSync(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        AppLog.info("🚀 Starting automatic CloudKit sync for RecipeX", category: .cloudKit)
        
        // Perform initial sync immediately
        Task {
            await syncPendingRecipes()
        }
        
        // Schedule periodic sync
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.syncPendingRecipes()
            }
        }
        
        AppLog.info("⏰ Scheduled periodic sync every \(Int(syncInterval)) seconds", category: .cloudKit)
    }
    
    /// Stop automatic sync service
    func stopAutomaticSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        AppLog.info("🛑 Stopped automatic CloudKit sync", category: .cloudKit)
    }
    
    /// Manually trigger sync (useful for immediate upload after creating a recipe)
    func syncNow() async {
        await syncPendingRecipes()
    }
    
    /// Get count of recipes waiting to be synced
    func getPendingCount(modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<RecipeX>(
            predicate: #Predicate { $0.needsCloudSync == true },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        
        do {
            let results = try modelContext.fetch(descriptor)
            return results.count
        } catch {
            AppLog.error("Failed to fetch pending recipes: \(error)", category: .cloudKit)
            return 0
        }
    }
    
    // MARK: - Private Sync Logic
    
    private func syncPendingRecipes() async {
        guard let modelContext = modelContext else {
            AppLog.warning("Cannot sync - modelContext is nil", category: .cloudKit)
            return
        }
        
        // Don't run multiple syncs simultaneously
        guard !isSyncing else {
            AppLog.debug("Sync already in progress, skipping", category: .cloudKit)
            return
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        // Fetch recipes that need syncing
        let descriptor = FetchDescriptor<RecipeX>(
            predicate: #Predicate { recipe in
                recipe.needsCloudSync == true && (recipe.syncRetryCount ?? 0) < 3
            },
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        
        do {
            let recipesToSync = try modelContext.fetch(descriptor)
            pendingCount = recipesToSync.count
            
            guard !recipesToSync.isEmpty else {
                AppLog.debug("No recipes need syncing", category: .cloudKit)
                return
            }
            
            AppLog.info("📤 Syncing \(recipesToSync.count) recipe(s) to CloudKit", category: .cloudKit)
            
            // Process in batches
            let batches = recipesToSync.chunked(into: batchSize)
            
            for (index, batch) in batches.enumerated() {
                AppLog.info("Processing batch \(index + 1)/\(batches.count) (\(batch.count) recipes)", category: .cloudKit)
                await syncBatch(batch, modelContext: modelContext)
            }
            
            lastSyncDate = Date()
            AppLog.info("✅ Sync complete", category: .cloudKit)
            
        } catch {
            AppLog.error("Failed to fetch recipes for sync: \(error)", category: .cloudKit)
            lastError = error.localizedDescription
        }
    }
    
    private func syncBatch(_ recipes: [RecipeX], modelContext: ModelContext) async {
        for recipe in recipes {
            await syncRecipe(recipe, modelContext: modelContext)
        }
    }
    
    private func syncRecipe(_ recipe: RecipeX, modelContext: ModelContext) async {
        guard let title = recipe.title else {
            AppLog.warning("Skipping recipe with no title", category: .cloudKit)
            return
        }
        
        AppLog.debug("Syncing recipe: \(title)", category: .cloudKit)
        
        do {
            // Convert RecipeX to CKRecord
            let record = try createCKRecord(from: recipe)
            
            // Save to CloudKit Public Database
            let savedRecord = try await publicDatabase.save(record)
            
            // Mark recipe as synced
            recipe.markAsSynced(recordID: savedRecord.recordID.recordName)
            
            // Save SwiftData changes
            try modelContext.save()
            
            AppLog.info("✅ Synced recipe '\(title)' to CloudKit", category: .cloudKit)
            
        } catch let error as CKError {
            handleCloudKitError(error, for: recipe, modelContext: modelContext)
        } catch {
            AppLog.error("Unexpected error syncing '\(title)': \(error)", category: .cloudKit)
            recipe.markSyncFailed(error: error.localizedDescription)
            try? modelContext.save()
        }
    }
    
    // MARK: - CKRecord Conversion
    
    private func createCKRecord(from recipe: RecipeX) throws -> CKRecord {
        let recordID: CKRecord.ID
        
        // Use existing CloudKit record ID if available, otherwise create new one
        if let existingID = recipe.cloudRecordID {
            recordID = CKRecord.ID(recordName: existingID)
        } else {
            recordID = CKRecord.ID(recordName: "RecipeX_\(recipe.safeID.uuidString)")
        }
        
        let record = CKRecord(recordType: "RecipeX", recordID: recordID)
        
        // MARK: Core fields
        record["id"] = recipe.id?.uuidString as CKRecordValue?
        record["title"] = recipe.title as CKRecordValue?
        record["headerNotes"] = recipe.headerNotes as CKRecordValue?
        record["recipeYield"] = recipe.recipeYield as CKRecordValue?
        record["reference"] = recipe.reference as CKRecordValue?
        
        // MARK: Recipe data (stored as Data/Assets)
        if let ingredientsData = recipe.ingredientSectionsData {
            record["ingredientSectionsData"] = ingredientsData as CKRecordValue
        }
        if let instructionsData = recipe.instructionSectionsData {
            record["instructionSectionsData"] = instructionsData as CKRecordValue
        }
        if let notesData = recipe.notesData {
            record["notesData"] = notesData as CKRecordValue
        }
        
        // MARK: Images (CKAsset for large data)
        if let imageData = recipe.imageData {
            let asset = try createCKAsset(from: imageData, filename: "main_image.jpg")
            record["imageAsset"] = asset
        }
        if let additionalImagesData = recipe.additionalImagesData {
            let asset = try createCKAsset(from: additionalImagesData, filename: "additional_images.json")
            record["additionalImagesAsset"] = asset
        }
        
        // MARK: Metadata
        record["dateAdded"] = recipe.dateAdded as CKRecordValue?
        record["dateCreated"] = recipe.dateCreated as CKRecordValue?
        record["lastModified"] = recipe.lastModified as CKRecordValue?
        record["version"] = recipe.version as CKRecordValue?
        record["ingredientsHash"] = recipe.ingredientsHash as CKRecordValue?
        record["contentFingerprint"] = recipe.contentFingerprint as CKRecordValue?
        
        // MARK: User attribution
        record["ownerUserID"] = recipe.ownerUserID as CKRecordValue?
        record["ownerDisplayName"] = recipe.ownerDisplayName as CKRecordValue?
        
        // MARK: Recipe metadata
        record["imageHash"] = recipe.imageHash as CKRecordValue?
        record["extractionSource"] = recipe.extractionSource as CKRecordValue?
        record["tagsData"] = recipe.tagsData as CKRecordValue?
        record["cuisine"] = recipe.cuisine as CKRecordValue?
        record["prepTimeMinutes"] = recipe.prepTimeMinutes as CKRecordValue?
        record["cookTimeMinutes"] = recipe.cookTimeMinutes as CKRecordValue?
        record["difficultyLevel"] = recipe.difficultyLevel as CKRecordValue?
        
        return record
    }
    
    private func createCKAsset(from data: Data, filename: String) throws -> CKAsset {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: tempURL)
        return CKAsset(fileURL: tempURL)
    }
    
    // MARK: - Error Handling
    
    private func handleCloudKitError(_ error: CKError, for recipe: RecipeX, modelContext: ModelContext) {
        AppLog.error("CloudKit error syncing '\(recipe.safeTitle)': \(error.localizedDescription)", category: .cloudKit)
        
        switch error.code {
        case .networkFailure, .networkUnavailable:
            // Transient error - retry later
            AppLog.warning("Network error, will retry later", category: .cloudKit)
            recipe.markSyncFailed(error: "Network unavailable")
            
        case .quotaExceeded:
            // User exceeded CloudKit quota
            AppLog.error("CloudKit quota exceeded for user", category: .cloudKit)
            recipe.markSyncFailed(error: "iCloud storage full")
            lastError = "iCloud storage quota exceeded. Please free up space."
            
        case .serverRecordChanged:
            // Conflict - server has a newer version
            AppLog.warning("Server record changed, need to resolve conflict", category: .cloudKit)
            // TODO: Implement conflict resolution
            recipe.markSyncFailed(error: "Conflict with server version")
            
        case .notAuthenticated:
            // User not signed into iCloud
            AppLog.error("User not signed into iCloud", category: .cloudKit)
            recipe.markSyncFailed(error: "Not signed into iCloud")
            lastError = "Please sign into iCloud to sync recipes"
            
        default:
            // Other error
            recipe.markSyncFailed(error: error.localizedDescription)
            lastError = error.localizedDescription
        }
        
        try? modelContext.save()
    }
}

// MARK: - Array Extension for Batching

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
