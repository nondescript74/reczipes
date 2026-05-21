//
//  ModelContainerManager.swift
//  Reczipes2
//
//  Created to handle dynamic ModelContainer creation and iCloud state changes
//

import Foundation
import SwiftUI
import SwiftData
import CloudKit
import Combine

/// Manages ModelContainer lifecycle and handles iCloud account changes
@MainActor
class ModelContainerManager: ObservableObject {
    static let shared = ModelContainerManager()
    
    @Published private(set) var container: ModelContainer
    @Published private(set) var isCloudKitEnabled: Bool = false
    @Published private(set) var isRecreating: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    private nonisolated(unsafe) var accountStatusObserver: NSObjectProtocol?
    
    private init() {
        // IMPORTANT: Try CloudKit first for community sharing features
        // Only fall back to local-only if CloudKit is genuinely unavailable
        logInfo("🚀 ModelContainerManager initializing...", category: "storage")
        logInfo("   Attempting CloudKit container first (required for community sharing)", category: "storage")
        logInfo("   Will fall back to local-only if CloudKit unavailable", category: "storage")
        
        let (container, cloudKitEnabled) = Self.createModelContainer(forceCloudKit: true)
        self.container = container
        self.isCloudKitEnabled = cloudKitEnabled
        
        // Monitor CloudKit account changes
        setupAccountMonitoring()
        
        // Log user-facing diagnostic
        logUserDiagnostic(
            .info,
            category: .storage,
            title: "Storage Initialized",
            message: cloudKitEnabled 
                ? "Your recipe data is syncing with iCloud."
                : "Your recipe data is stored locally on this device.",
            technicalDetails: "ModelContainer created with CloudKit: \(cloudKitEnabled)"
        )
        
        // Defer health check to avoid blocking initialization
        // This allows the app to start even if health check takes time
        Task { @MainActor in
            // Add a small delay to let the app fully initialize first
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Check if task was cancelled (e.g., due to backgrounding)
            guard !Task.isCancelled else {
                logInfo("🔍 Startup health check cancelled (app may have been backgrounded)", category: "storage")
                return
            }
            
            logInfo("🔍 Performing startup health check...", category: "storage")
            let isHealthy = await self.verifyContainerHealth()
            
            // Check cancellation again after async work
            guard !Task.isCancelled else {
                logInfo("🔍 Startup health check cancelled after verification", category: "storage")
                return
            }
            
            if !isHealthy {
                logWarning("⚠️ Container health check failed on startup", category: "storage")
                logWarning("   Attempting automatic recovery...", category: "storage")
                
                let recovered = await self.attemptContainerRecovery()
                
                // Check cancellation after recovery attempt
                guard !Task.isCancelled else {
                    logInfo("🔍 Container recovery cancelled", category: "storage")
                    return
                }
                
                if !recovered {
                    logCritical("❌ CRITICAL: Container recovery failed!", category: "storage")
                    logCritical("   App may not function correctly", category: "storage")
                    logCritical("   User should delete and reinstall app to resolve", category: "storage")
                    
                    // Log user-facing critical diagnostic
                    logUserDiagnostic(
                        .critical,
                        category: .storage,
                        title: "Storage Recovery Failed",
                        message: "Automatic recovery couldn't fix the storage issue. Your data may be in iCloud.",
                        technicalDetails: "All recovery attempts exhausted",
                        suggestedActions: [
                            DiagnosticAction(
                                title: "Check iCloud Status",
                                description: "Verify you're signed into iCloud and have sync enabled",
                                actionType: .checkCloudKitStatus
                            ),
                            DiagnosticAction(
                                title: "Reinstall Reczipes",
                                description: "Delete the app and reinstall it. Your iCloud data will sync back automatically.",
                                actionType: .deleteAndReinstall
                            ),
                            DiagnosticAction(
                                title: "Contact Support",
                                description: "If the problem persists, reach out for help",
                                actionType: .contactSupport
                            )
                        ]
                    )
                    
                    // Log full diagnostic info for troubleshooting
                    await self.logDiagnosticInfo()
                }
            } else {
                logInfo("✅ Startup health check passed", category: "storage")
            }
        }
    }
    
    deinit {
        if let observer = accountStatusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Container Creation
    
    private static func createModelContainer(forceCloudKit: Bool? = nil) -> (ModelContainer, Bool) {
        // Log schema version information
        logInfo("🚀 STARTING MODEL CONTAINER INITIALIZATION", category: "storage")
        logInfo("   Schema Version: \(SchemaVersionManager.versionString(SchemaVersionManager.currentVersion))", category: "storage")
        SchemaVersionManager.logSchemaInfo()
        
        // Use the forced CloudKit setting
        let shouldUseCloudKit = forceCloudKit ?? false
        
        if shouldUseCloudKit {
            logInfo("📦 Creating container with CloudKit enabled", category: "storage")
            // Try CloudKit configuration
            if let container = tryCreateCloudKitContainer() {
                return (container, true)
            }
            logWarning("⚠️ CloudKit container creation failed, falling back to local-only", category: "storage")
        } else {
            logInfo("📦 Creating local-only container (CloudKit will be checked asynchronously)", category: "storage")
        }
        
        // Fall back to local-only configuration
        return (createLocalContainer(), false)
    }
    
    private static func tryCreateCloudKitContainer() -> ModelContainer? {
        let cloudKitURL = URL.applicationSupportDirectory.appending(path: "CloudKitModel.sqlite")
        
        // NOTE: We removed the pre-check that was deleting the database on every launch.
        // Database compatibility issues will be handled in the catch block below
        // if container creation fails. This prevents accidental data loss.
        
        let cloudKitConfiguration = ModelConfiguration(
            url: cloudKitURL,
            cloudKitDatabase: .private("iCloud.com.headydiscy.reczipes")
        )
        
        logInfo("📦 Attempting to create ModelContainer with CloudKit...", category: "storage")
        do {
            let container = try ModelContainer(
                for: RecipeX.self,              // Unified recipe model (CloudKit compatible)
                Book.self,                      // Unified book model (CloudKit compatible)
                RecipeImageAssignment.self,
                UserAllergenProfile.self,
                CachedDiabeticAnalysis.self,
                SavedLink.self,
                CookingSession.self,
                SharedRecipe.self,              // CloudKit sharing tracking
                SharedRecipeBook.self,          // CloudKit sharing models
                SharingPreferences.self,        // CloudKit sharing models
                CachedSharedRecipe.self,
                CloudKitRecipePreview.self,
                VersionHistoryRecord.self,
                Meal.self,                      // Meals (groupings of recipes)
                migrationPlan: Reczipes2MigrationPlan.self,
                configurations: cloudKitConfiguration
            )
            logInfo("✅ ModelContainer created successfully with CloudKit sync enabled", category: "storage")
            logInfo("   Container: iCloud.com.headydiscy.reczipes", category: "storage")
            logInfo("   Database: CloudKitModel.sqlite", category: "storage")
            return container
        } catch let error as NSError {
            // Log the full error details for debugging
            logError("❌ CloudKit ModelContainer creation failed: \(error.localizedDescription)", category: "storage")
            logError("   Error domain: \(error.domain), code: \(error.code)", category: "storage")
            logError("   Underlying error: \(String(describing: error.userInfo[NSUnderlyingErrorKey]))", category: "storage")
            
            // ✨ NEW: Analyze error chain
            let analysis = DatabaseRecoveryLogger.analyzeError(error)
            analysis.logAnalysis()
            
            if analysis.isSchemaIssue {
                // ✨ NEW: Begin tracking recovery
                DatabaseRecoveryLogger.shared.beginRecoveryAttempt()
                
                // ✨ NEW: Capture database size before deletion
                let databaseSizeMB = DatabaseRecoveryLogger.getDatabaseSize(at: cloudKitURL)
                
                logWarning("⚠️ Database incompatible with current schema (unknown model version)", category: "storage")
                logWarning("   This usually happens when the database was created with a schema version that no longer exists", category: "storage")
                logWarning("   Attempting to delete incompatible database and start fresh...", category: "storage")
                
                // Try to delete the old database files
                let fileManager = FileManager.default
                let filesToDelete = [
                    cloudKitURL.path,
                    cloudKitURL.path + "-shm",
                    cloudKitURL.path + "-wal"
                ]
                
                var filesDeleted: [String] = []
                
                // Track which files were deleted
                for filePath in filesToDelete {
                    if fileManager.fileExists(atPath: filePath) {
                        do {
                            try fileManager.removeItem(atPath: filePath)
                            filesDeleted.append(filePath.split(separator: "/").last.map(String.init) ?? filePath)
                            logInfo("   ✅ Deleted: \(filesDeleted.last!)", category: "storage")
                        } catch {
                            logError("   ❌ Failed to delete \(filePath): \(error)", category: "storage")
                        }
                    }
                }
                
                if filesDeleted.count > 0 {
                    // Try creating container again
                    do {
                        let container = try ModelContainer(
                            for: RecipeX.self,              // Unified recipe model (CloudKit compatible)
                            Book.self,                      // Unified book model (CloudKit compatible)
                            RecipeImageAssignment.self,
                            UserAllergenProfile.self,
                            CachedDiabeticAnalysis.self,
                            SavedLink.self,
                            CookingSession.self,
                            SharedRecipe.self,              // CloudKit sharing tracking
                            SharedRecipeBook.self,          // CloudKit sharing models
                            SharingPreferences.self,        // CloudKit sharing models
                            CachedSharedRecipe.self,
                            CloudKitRecipePreview.self,
                            VersionHistoryRecord.self,
                            Meal.self,                      // Meals (groupings of recipes)
                            migrationPlan: Reczipes2MigrationPlan.self,
                            configurations: cloudKitConfiguration
                        )
                        
                        // ✨ NEW: Log successful recovery
                        DatabaseRecoveryLogger.shared.logRecoverySuccess(
                            error: error,
                            filesDeleted: filesDeleted,
                            cloudKitEnabled: true,
                            databaseSizeMB: databaseSizeMB
                        )
                        
                        return container
                    } catch let recreationError {
                        // ✨ NEW: Log failed recovery
                        DatabaseRecoveryLogger.shared.logRecoveryFailure(
                            error: error,
                            filesDeleted: filesDeleted,
                            cloudKitEnabled: true,
                            secondaryError: recreationError
                        )
                        
                        return nil
                    }
                }
            }

            
            // Check for the specific "unknown model version" error (error code 134504)
            // This error can be nested at different levels in the error chain
            func containsUnknownModelError(_ error: NSError) -> Bool {
                // Check the error itself
                if error.domain == "NSCocoaErrorDomain" && error.code == 134504 {
                    return true
                }
                
                // Check the underlying error
                if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                    return containsUnknownModelError(underlyingError)
                }
                
                // Check for SwiftData wrapped errors
                if error.domain == "SwiftData.SwiftDataError" && error.code == 1 {
                    // SwiftData error code 1 is loadIssueModelContainer
                    // This often wraps a Core Data migration error
                    logWarning("   SwiftData loadIssueModelContainer error detected", category: "storage")
                    return true
                }
                
                return false
            }
            
            let isUnknownModelVersion = containsUnknownModelError(error)
            
            if isUnknownModelVersion {
                logWarning("⚠️ Database incompatible with current schema (unknown model version)", category: "storage")
                logWarning("   This usually happens when the database was created with a schema version that no longer exists", category: "storage")
                logWarning("   Attempting to delete incompatible database and start fresh...", category: "storage")
                
                // Try to delete the old database files
                let fileManager = FileManager.default
                let filesToDelete = [
                    cloudKitURL.path,
                    cloudKitURL.path + "-shm",
                    cloudKitURL.path + "-wal"
                ]
                
                var deletedCount = 0
                for filePath in filesToDelete {
                    if fileManager.fileExists(atPath: filePath) {
                        do {
                            try fileManager.removeItem(atPath: filePath)
                            deletedCount += 1
                            logInfo("   ✅ Deleted: \(filePath.split(separator: "/").last ?? "")", category: "storage")
                        } catch {
                            logError("   ❌ Failed to delete \(filePath): \(error)", category: "storage")
                        }
                    }
                }
                
                if deletedCount > 0 {
                    logInfo("   Deleted \(deletedCount) database file(s), attempting to recreate...", category: "storage")
                    
                    // Try creating container again with clean slate
                    do {
                        let container = try ModelContainer(
                            for: RecipeX.self,              // Unified recipe model (CloudKit compatible)
                            Book.self,                      // Unified book model (CloudKit compatible)
                            RecipeImageAssignment.self,
                            UserAllergenProfile.self,
                            CachedDiabeticAnalysis.self,
                            SavedLink.self,
                            CookingSession.self,
                            SharedRecipe.self,              // CloudKit sharing tracking
                            SharedRecipeBook.self,          // CloudKit sharing models
                            SharingPreferences.self,        // CloudKit sharing models
                            CachedSharedRecipe.self,
                            CloudKitRecipePreview.self,
                            VersionHistoryRecord.self,
                            Meal.self,                      // Meals (groupings of recipes)
                            migrationPlan: Reczipes2MigrationPlan.self,
                            configurations: cloudKitConfiguration
                        )
                        logInfo("✅ ModelContainer recreated successfully after database cleanup", category: "storage")
                        logWarning("   Note: Previous local data was lost, but CloudKit data should sync back", category: "storage")
                        return container
                    } catch {
                        logError("❌ Failed to recreate container after cleanup: \(error)", category: "storage")
                        return nil
                    }
                } else {
                    logError("   No database files found to delete", category: "storage")
                    return nil
                }
            } else {
                logError("❌ CloudKit ModelContainer creation failed: \(error.localizedDescription)", category: "storage")
                return nil
            }
        }
    }
    
    private static func createLocalContainer() -> ModelContainer {
        // CRITICAL: Use the same database file as CloudKit config to preserve data!
        let cloudKitURL = URL.applicationSupportDirectory.appending(path: "CloudKitModel.sqlite")
        let localConfiguration = ModelConfiguration(
            url: cloudKitURL  // Use same database file, CloudKit disabled by not specifying cloudKitDatabase
        )
        
        do {
            let container = try ModelContainer(
                for: RecipeX.self,              // Unified recipe model (CloudKit compatible)
                Book.self,                      // Unified book model (CloudKit compatible)
                RecipeImageAssignment.self,
                UserAllergenProfile.self,
                CachedDiabeticAnalysis.self,
                SavedLink.self,
                CookingSession.self,
                SharedRecipe.self,              // CloudKit sharing tracking
                SharedRecipeBook.self,          // CloudKit sharing models
                SharingPreferences.self,        // CloudKit sharing models
                CachedSharedRecipe.self,
                CloudKitRecipePreview.self,
                VersionHistoryRecord.self,
                Meal.self,                      // Meals (groupings of recipes)
                migrationPlan: Reczipes2MigrationPlan.self,
                configurations: localConfiguration
            )
            logInfo("✅ ModelContainer created successfully (local-only, no CloudKit sync)", category: "storage")
            logInfo("   Using existing database: CloudKitModel.sqlite", category: "storage")
            logInfo("   Your data is preserved even though CloudKit is disabled", category: "storage")
            return container
        } catch let error as NSError {
            // Log the full error details for debugging
            logError("❌ Local ModelContainer creation failed: \(error.localizedDescription)", category: "storage")
            logError("   Error domain: \(error.domain), code: \(error.code)", category: "storage")
            logError("   Underlying error: \(String(describing: error.userInfo[NSUnderlyingErrorKey]))", category: "storage")
            
            // ✨ NEW: Analyze error chain
            let analysis = DatabaseRecoveryLogger.analyzeError(error)
            analysis.logAnalysis()
            
            if analysis.isSchemaIssue {
                // ✨ NEW: Begin tracking recovery
                DatabaseRecoveryLogger.shared.beginRecoveryAttempt()
                
                // ✨ NEW: Capture database size before deletion
                let databaseSizeMB = DatabaseRecoveryLogger.getDatabaseSize(at: cloudKitURL)
                
                logWarning("⚠️ Database incompatible with current schema (unknown model version)", category: "storage")
                logWarning("   This usually happens when the database was created with a schema version that no longer exists", category: "storage")
                logWarning("   Attempting to delete incompatible database and start fresh...", category: "storage")
                
                // Try to delete the old database files
                let fileManager = FileManager.default
                let filesToDelete = [
                    cloudKitURL.path,
                    cloudKitURL.path + "-shm",
                    cloudKitURL.path + "-wal"
                ]
                
                var filesDeleted: [String] = []
                
                // Track which files were deleted
                for filePath in filesToDelete {
                    if fileManager.fileExists(atPath: filePath) {
                        do {
                            try fileManager.removeItem(atPath: filePath)
                            filesDeleted.append(filePath.split(separator: "/").last.map(String.init) ?? filePath)
                            logInfo("   ✅ Deleted: \(filesDeleted.last!)", category: "storage")
                        } catch {
                            logError("   ❌ Failed to delete \(filePath): \(error)", category: "storage")
                        }
                    }
                }
                
                if filesDeleted.count > 0 {
                    logInfo("   Deleted \(filesDeleted.count) database file(s), attempting to recreate...", category: "storage")
                    
                    // Try creating container again with clean slate
                    do {
                        let container = try ModelContainer(
                            for: RecipeX.self,              // Unified recipe model (CloudKit compatible)
                            Book.self,                      // Unified book model (CloudKit compatible)
                            RecipeImageAssignment.self,
                            UserAllergenProfile.self,
                            CachedDiabeticAnalysis.self,
                            SavedLink.self,
                            CookingSession.self,
                            SharedRecipe.self,              // CloudKit sharing tracking
                            SharedRecipeBook.self,          // CloudKit sharing models
                            SharingPreferences.self,        // CloudKit sharing models
                            CachedSharedRecipe.self,
                            CloudKitRecipePreview.self,
                            VersionHistoryRecord.self,
                            Meal.self,                      // Meals (groupings of recipes)
                            migrationPlan: Reczipes2MigrationPlan.self,
                            configurations: localConfiguration
                        )
                        
                        // ✨ NEW: Log successful recovery
                        DatabaseRecoveryLogger.shared.logRecoverySuccess(
                            error: error,
                            filesDeleted: filesDeleted,
                            cloudKitEnabled: false,
                            databaseSizeMB: databaseSizeMB
                        )
                        
                        logInfo("✅ ModelContainer recreated successfully after database cleanup", category: "storage")
                        logWarning("   Note: Previous local data was lost, but may sync back from iCloud", category: "storage")
                        return container
                    } catch let recreationError {
                        // ✨ NEW: Log failed recovery
                        DatabaseRecoveryLogger.shared.logRecoveryFailure(
                            error: error,
                            filesDeleted: filesDeleted,
                            cloudKitEnabled: false,
                            secondaryError: recreationError
                        )
                        
                        logCritical("❌ Failed to recreate container after cleanup: \(recreationError)", category: "storage")
                        fatalError("Could not create ModelContainer even after cleanup: \(recreationError)")
                    }
                } else {
                    // ✨ NEW: Log recovery failure when no files were found
                    DatabaseRecoveryLogger.shared.logRecoveryFailure(
                        error: error,
                        filesDeleted: [],
                        cloudKitEnabled: false,
                        secondaryError: nil
                    )
                    
                    logCritical("❌ No database files found to delete, cannot recover", category: "storage")
                    fatalError("Could not create ModelContainer: \(error)")
                }
            } else {
                // Non-schema issue - fatal error
                logCritical("❌ All ModelContainer initialization attempts failed", category: "storage")
                logCritical("   Final error: \(error)", category: "storage")
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }
    
    // MARK: - Account Monitoring
    
    private func setupAccountMonitoring() {
        // Listen for CKAccountChanged notifications
        accountStatusObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAccountChange()
            }
        }
    }
    
    private func checkAndUpgradeToCloudKitIfAvailable() async {
        // Try multiple times with increasing delays to handle initialization race conditions
        let retryDelays: [UInt64] = [
            0,                      // Immediate first check
            2_000_000_000,          // 2 seconds
            5_000_000_000,          // 5 seconds
            10_000_000_000          // 10 seconds
        ]
        
        for (attempt, delay) in retryDelays.enumerated() {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            
            let cloudKitAvailable = await checkCurrentCloudKitStatus()
            
            logInfo("🔍 CloudKit check attempt \(attempt + 1)/\(retryDelays.count):", category: "storage")
            logInfo("   CloudKit available: \(cloudKitAvailable)", category: "storage")
            
            // If CloudKit is available, upgrade the container
            if cloudKitAvailable {
                logInfo("✅ CloudKit is available - upgrading container to enable sync...", category: "storage")
                await recreateContainer(withCloudKitEnabled: true)
                return // Success, exit retry loop
            }
        }
        
        logInfo("ℹ️ CloudKit not available after \(retryDelays.count) checks - continuing with local-only storage", category: "storage")
    }
    
    private func handleAccountChange() {
        logInfo("🔄 CloudKit account changed - checking if container recreation is needed...", category: "storage")
        
        Task {
            // Check new account status
            let wasCloudKitEnabled = isCloudKitEnabled
            let nowAvailable = await checkCurrentCloudKitStatus()
            
            // Only recreate if status actually changed
            if wasCloudKitEnabled != nowAvailable {
                logWarning("⚠️ CloudKit availability changed: \(wasCloudKitEnabled) → \(nowAvailable)", category: "storage")
                logInfo("   Recreating ModelContainer to match new iCloud state...", category: "storage")
                
                // Log user-facing diagnostic
                logUserDiagnostic(
                    nowAvailable ? .info : .warning,
                    category: .cloudKit,
                    title: nowAvailable ? "iCloud Sync Enabled" : "iCloud Sync Disabled",
                    message: nowAvailable 
                        ? "Your recipes will now sync across all your devices."
                        : "Your recipes are now saved locally only.",
                    technicalDetails: "CloudKit account status changed from \(wasCloudKitEnabled) to \(nowAvailable)",
                    suggestedActions: nowAvailable ? [
                        DiagnosticAction(
                            title: "Wait for Sync",
                            description: "It may take a few moments for all your data to sync",
                            actionType: .retryOperation
                        )
                    ] : [
                        DiagnosticAction(
                            title: "Check iCloud Status",
                            description: "Verify you're signed into iCloud",
                            actionType: .openSettings(.icloud)
                        )
                    ]
                )
                
                await recreateContainer(withCloudKitEnabled: nowAvailable)
            } else {
                logInfo("✓ CloudKit status unchanged, no container recreation needed", category: "storage")
            }
        }
    }
    
    private func checkCurrentCloudKitStatus() async -> Bool {
        do {
            let status = try await CKContainer.default().accountStatus()
            let isAvailable = (status == .available)
            logInfo("   Current CloudKit status: \(status.rawValue) (\(isAvailable ? "available" : "not available"))", category: "storage")
            
            // Log user-facing diagnostic if CloudKit is unavailable
            if !isAvailable {
                let reason: String
                switch status {
                case .noAccount:
                    reason = "No iCloud account signed in"
                case .restricted:
                    reason = "iCloud access is restricted"
                case .couldNotDetermine:
                    reason = "Could not determine iCloud status"
                case .temporarilyUnavailable:
                    reason = "iCloud temporarily unavailable"
                default:
                    reason = "Unknown status: \(status.rawValue)"
                }
                
                logUserDiagnostic(
                    .warning,
                    category: .cloudKit,
                    title: "iCloud Sync Unavailable",
                    message: reason + ". Your recipes are saved locally.",
                    technicalDetails: "CloudKit account status: \(status.rawValue)",
                    suggestedActions: status == .noAccount ? [
                        DiagnosticAction(
                            title: "Sign Into iCloud",
                            description: "Go to Settings > [Your Name] to sign in",
                            actionType: .openSettings(.icloud)
                        )
                    ] : [
                        DiagnosticAction(
                            title: "Check iCloud Settings",
                            description: "Verify iCloud is enabled for Reczipes",
                            actionType: .openSettings(.icloud)
                        )
                    ]
                )
            } else {
                logUserDiagnostic(
                    .info,
                    category: .cloudKit,
                    title: "iCloud Sync Active",
                    message: "Your recipes are syncing across all your devices.",
                    technicalDetails: "CloudKit account status: available"
                )
            }
            
            return isAvailable
        } catch {
            logError("❌ Error checking CloudKit status: \(error.localizedDescription)", category: "storage")
            
            logUserDiagnostic(
                .error,
                category: .cloudKit,
                title: "iCloud Status Check Failed",
                message: "Couldn't verify iCloud status. Your recipes are saved locally.",
                technicalDetails: error.localizedDescription,
                suggestedActions: [
                    DiagnosticAction(
                        title: "Check Internet Connection",
                        description: "Make sure you're connected to the internet",
                        actionType: .checkNetworkConnection
                    ),
                    DiagnosticAction(
                        title: "Try Again",
                        description: "Restart the app to retry",
                        actionType: .retryOperation
                    )
                ]
            )
            
            return false
        }
    }
    
    // MARK: - Container Recreation
    
    func recreateContainer(withCloudKitEnabled cloudKitEnabled: Bool? = nil) async {
        guard !isRecreating else {
            logWarning("⚠️ Container recreation already in progress, skipping...", category: "storage")
            return
        }
        
        // Ensure we're on MainActor for thread safety
        await MainActor.run {
            isRecreating = true
        }
        
        defer {
            Task { @MainActor in
                isRecreating = false
            }
        }
        
        logInfo("🔄 Recreating ModelContainer...", category: "storage")
        if let enabled = cloudKitEnabled {
            logInfo("   Target CloudKit state: \(enabled ? "enabled" : "disabled")", category: "storage")
        }
        
        // Determine appropriate wait time based on current container state
        let wasCloudKitEnabled = await MainActor.run { isCloudKitEnabled }
        let waitTime: UInt64 = wasCloudKitEnabled ? 5_000_000_000 : 1_000_000_000 // 5s if CloudKit was on, 1s if local
        
        logInfo("   Waiting for previous container to tear down...", category: "storage")
        logInfo("   (Wait time: \(waitTime / 1_000_000_000) seconds - \(wasCloudKitEnabled ? "CloudKit cleanup needed" : "local-only, minimal wait"))", category: "storage")
        
        // Store reference to old container
        let oldContainer = await MainActor.run { container }
        
        // Give the old container time to tear down properly
        try? await Task.sleep(nanoseconds: waitTime)
        
        // Keep reference to ensure it stays alive until now
        _ = oldContainer.schema
        
        logInfo("   Creating new container...", category: "storage")
        
        // Create new container with known CloudKit state if provided
        let (newContainer, actualCloudKitEnabled) = Self.createModelContainer(forceCloudKit: cloudKitEnabled)
        
        // Replace the old container on MainActor
        await MainActor.run {
            container = newContainer
            isCloudKitEnabled = actualCloudKitEnabled
        }
        
        logInfo("✅ ModelContainer recreated successfully", category: "storage")
        logInfo("   CloudKit enabled: \(actualCloudKitEnabled)", category: "storage")
        
        // Post notification so views can refresh if needed
        await MainActor.run {
            NotificationCenter.default.post(name: .modelContainerRecreated, object: nil)
        }
    }
    
    /// Manually trigger container recreation (for testing or troubleshooting)
    func manuallyRecreateContainer() async {
        logInfo("🔧 Manually recreating ModelContainer...", category: "storage")
        await recreateContainer()
    }
    
    // MARK: - Container Health & Recovery
    
    /// Verify that the container is functional by attempting a basic fetch
    func verifyContainerHealth() async -> Bool {
        do {
            let context = container.mainContext
            
            // Try fetching from the new unified models to verify container health
            var recipeDescriptor = FetchDescriptor<RecipeX>(predicate: nil)
            recipeDescriptor.fetchLimit = 1
            _ = try context.fetch(recipeDescriptor)
            
            var bookDescriptor = FetchDescriptor<Book>(predicate: nil)
            bookDescriptor.fetchLimit = 1
            _ = try context.fetch(bookDescriptor)
            
            logInfo("✅ Container health check passed (RecipeX, Book models verified)", category: "storage")
            return true
        } catch {
            logError("❌ Container health check failed: \(error)", category: "storage")
            
            logUserDiagnostic(
                .error,
                category: .storage,
                title: "Storage Health Check Failed",
                message: "There was a problem accessing your recipe data.",
                technicalDetails: "Health check error: \(error.localizedDescription)",
                suggestedActions: [
                    DiagnosticAction(
                        title: "Restart the App",
                        description: "Close and reopen Reczipes to attempt automatic recovery",
                        actionType: .retryOperation
                    ),
                    DiagnosticAction(
                        title: "Check Available Storage",
                        description: "Make sure your device has enough free storage space",
                        actionType: .openSettings(.general)
                    )
                ]
            )
            
            return false
        }
    }
    
    /// Attempt to recover from container failures
    /// Returns true if recovery was successful, false if manual intervention needed
    func attemptContainerRecovery() async -> Bool {
        logWarning("🔧 Attempting container recovery...", category: "storage")
        
        // Log diagnostic info before attempting recovery
        await logDiagnosticInfo()
        
        // Step 1: Try recreating the container with current CloudKit state
        logInfo("   Step 1: Recreating container...", category: "storage")
        await recreateContainer(withCloudKitEnabled: isCloudKitEnabled)
        
        // Step 2: Verify the new container is working
        logInfo("   Step 2: Verifying container health...", category: "storage")
        if await verifyContainerHealth() {
            logInfo("✅ Container recovery successful!", category: "storage")
            return true
        }
        
        // Step 3: If still failing, try forcing CloudKit refresh
        if isCloudKitEnabled {
            logInfo("   Step 3: Attempting CloudKit container refresh...", category: "storage")
            await recreateContainer(withCloudKitEnabled: true)
            
            if await verifyContainerHealth() {
                logInfo("✅ Container recovery successful after CloudKit refresh!", category: "storage")
                return true
            }
        }
        
        // Step 4: Last resort - try local-only mode
        logWarning("   Step 4: Attempting local-only fallback...", category: "storage")
        await recreateContainer(withCloudKitEnabled: false)
        
        if await verifyContainerHealth() {
            logWarning("⚠️ Container recovered in local-only mode (CloudKit disabled)", category: "storage")
            logWarning("   User may need to reinstall app to restore CloudKit sync", category: "storage")
            return true
        }
        
        // Complete failure - needs manual intervention
        logError("❌ Container recovery failed - manual intervention required", category: "storage")
        logError("   User should try: Delete app → Reinstall → Data will sync from CloudKit", category: "storage")
        return false
    }
    
    /// Log comprehensive diagnostic information about the container state
    func logDiagnosticInfo() async {
        logInfo("📊 ============ CONTAINER DIAGNOSTIC INFO ============", category: "storage")
        logInfo("📊 Runtime State:", category: "storage")
        logInfo("   CloudKit Enabled: \(isCloudKitEnabled)", category: "storage")
        logInfo("   Is Recreating: \(isRecreating)", category: "storage")
        
        logInfo("📊 Schema Information:", category: "storage")
        let entityNames = container.schema.entities.map { $0.name }.sorted()
        logInfo("   Entities: \(entityNames.joined(separator: ", "))", category: "storage")
        logInfo("   Entity Count: \(entityNames.count)", category: "storage")
        
        logInfo("📊 Database File:", category: "storage")
        if let dbURL = container.configurations.first?.url {
            logInfo("   Path: \(dbURL.path)", category: "storage")
            
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: dbURL.path) {
                do {
                    let attrs = try fileManager.attributesOfItem(atPath: dbURL.path)
                    if let size = attrs[.size] as? Int64 {
                        let sizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                        logInfo("   Size: \(sizeString)", category: "storage")
                    }
                    if let modDate = attrs[.modificationDate] as? Date {
                        logInfo("   Last Modified: \(modDate)", category: "storage")
                    }
                } catch {
                    logError("   ⚠️ Could not read file attributes: \(error)", category: "storage")
                }
                
                // Check for associated files (WAL, SHM)
                let walPath = dbURL.path + "-wal"
                let shmPath = dbURL.path + "-shm"
                logInfo("   WAL file exists: \(fileManager.fileExists(atPath: walPath))", category: "storage")
                logInfo("   SHM file exists: \(fileManager.fileExists(atPath: shmPath))", category: "storage")
            } else {
                logWarning("   ⚠️ Database file does not exist!", category: "storage")
            }
        } else {
            logError("   ❌ No database URL configured!", category: "storage")
        }
        
        logInfo("📊 CloudKit Status:", category: "storage")
        if isCloudKitEnabled {
            // Check CloudKit account status
            do {
                let status = try await CKContainer.default().accountStatus()
                let statusString: String
                switch status {
                case .available:
                    statusString = "Available ✅"
                case .noAccount:
                    statusString = "No Account ⚠️"
                case .restricted:
                    statusString = "Restricted ⚠️"
                case .couldNotDetermine:
                    statusString = "Could Not Determine ⚠️"
                case .temporarilyUnavailable:
                    statusString = "Temporarily Unavailable ⚠️"
                @unknown default:
                    statusString = "Unknown ⚠️"
                }
                logInfo("   Account Status: \(statusString)", category: "storage")
            } catch {
                logError("   ❌ Error checking account: \(error)", category: "storage")
            }
            
            logInfo("   Container: iCloud.com.headydiscy.reczipes", category: "storage")
        } else {
            logInfo("   CloudKit: Disabled (local-only mode)", category: "storage")
        }
        
        logInfo("📊 Data Counts:", category: "storage")
        let context = container.mainContext
        do {
            // New unified models (RecipeX and Book)
            let recipeXCount = try context.fetchCount(FetchDescriptor<RecipeX>())
            let bookCount = try context.fetchCount(FetchDescriptor<Book>())
            
            // Other models
            let sessionCount = try context.fetchCount(FetchDescriptor<CookingSession>())
            let sharedRecipeCount = try context.fetchCount(FetchDescriptor<SharedRecipe>())
            let sharedBookCount = try context.fetchCount(FetchDescriptor<SharedRecipeBook>())
            let savedLinkCount = try context.fetchCount(FetchDescriptor<SavedLink>())
            
            logInfo("   === Unified Models ===", category: "storage")
            logInfo("   Recipes: \(recipeXCount)", category: "storage")
            logInfo("   Books: \(bookCount)", category: "storage")
            
            logInfo("   === Other Data ===", category: "storage")
            logInfo("   Cooking Sessions: \(sessionCount)", category: "storage")
            logInfo("   Saved Links: \(savedLinkCount)", category: "storage")
            logInfo("   Shared Recipes: \(sharedRecipeCount)", category: "storage")
            logInfo("   Shared Recipe Books: \(sharedBookCount)", category: "storage")
            
        } catch {
            logError("   ❌ Error fetching counts: \(error)", category: "storage")
        }
        
        logInfo("📊 ================================================", category: "storage")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let modelContainerRecreated = Notification.Name("modelContainerRecreated")
}
