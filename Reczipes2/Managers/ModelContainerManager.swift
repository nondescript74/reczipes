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
        AppLog.info("🚀 ModelContainerManager initializing...", category: .storage)
        AppLog.info("   Attempting CloudKit container first (required for community sharing)", category: .storage)
        AppLog.info("   Will fall back to local-only if CloudKit unavailable", category: .storage)
        
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
                AppLog.info("🔍 Startup health check cancelled (app may have been backgrounded)", category: .storage)
                return
            }
            
            AppLog.info("🔍 Performing startup health check...", category: .storage)
            let isHealthy = await self.verifyContainerHealth()
            
            // Check cancellation again after async work
            guard !Task.isCancelled else {
                AppLog.info("🔍 Startup health check cancelled after verification", category: .storage)
                return
            }
            
            if !isHealthy {
                AppLog.warning("⚠️ Container health check failed on startup", category: .storage)
                AppLog.warning("   Attempting automatic recovery...", category: .storage)
                
                let recovered = await self.attemptContainerRecovery()
                
                // Check cancellation after recovery attempt
                guard !Task.isCancelled else {
                    AppLog.info("🔍 Container recovery cancelled", category: .storage)
                    return
                }
                
                if !recovered {
                    AppLog.critical("❌ CRITICAL: Container recovery failed!", category: .storage)
                    AppLog.critical("   App may not function correctly", category: .storage)
                    AppLog.critical("   User should delete and reinstall app to resolve", category: .storage)
                    
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
                AppLog.info("✅ Startup health check passed", category: .storage)
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
        AppLog.info("🚀 STARTING MODEL CONTAINER INITIALIZATION", category: .storage)
        AppLog.info("   Schema Version: \(SchemaVersionManager.versionString(SchemaVersionManager.currentVersion))", category: .storage)
        SchemaVersionManager.logSchemaInfo()
        
        // Use the forced CloudKit setting
        let shouldUseCloudKit = forceCloudKit ?? false
        
        if shouldUseCloudKit {
            AppLog.info("📦 Creating container with CloudKit enabled", category: .storage)
            // Try CloudKit configuration
            if let container = tryCreateCloudKitContainer() {
                return (container, true)
            }
            AppLog.warning("⚠️ CloudKit container creation failed, falling back to local-only", category: .storage)
        } else {
            AppLog.info("📦 Creating local-only container (CloudKit will be checked asynchronously)", category: .storage)
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
        
        AppLog.info("📦 Attempting to create ModelContainer with CloudKit...", category: .storage)
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
            AppLog.info("✅ ModelContainer created successfully with CloudKit sync enabled", category: .storage)
            AppLog.info("   Container: iCloud.com.headydiscy.reczipes", category: .storage)
            AppLog.info("   Database: CloudKitModel.sqlite", category: .storage)
            return container
        } catch let error as NSError {
            // Log the full error details for debugging
            AppLog.error("❌ CloudKit ModelContainer creation failed: \(error.localizedDescription)", category: .storage)
            AppLog.error("   Error domain: \(error.domain), code: \(error.code)", category: .storage)
            AppLog.error("   Underlying error: \(String(describing: error.userInfo[NSUnderlyingErrorKey]))", category: .storage)
            
            // ✨ NEW: Analyze error chain
            let analysis = DatabaseRecoveryLogger.analyzeError(error)
            analysis.logAnalysis()
            
            if analysis.isSchemaIssue {
                // ✨ NEW: Begin tracking recovery
                DatabaseRecoveryLogger.shared.beginRecoveryAttempt()
                
                // ✨ NEW: Capture database size before deletion
                let databaseSizeMB = DatabaseRecoveryLogger.getDatabaseSize(at: cloudKitURL)
                
                AppLog.warning("⚠️ Database incompatible with current schema (unknown model version)", category: .storage)
                AppLog.warning("   This usually happens when the database was created with a schema version that no longer exists", category: .storage)
                AppLog.warning("   Attempting to delete incompatible database and start fresh...", category: .storage)
                
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
                            AppLog.info("   ✅ Deleted: \(filesDeleted.last!)", category: .storage)
                        } catch {
                            AppLog.error("   ❌ Failed to delete \(filePath): \(error)", category: .storage)
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
                    AppLog.warning("   SwiftData loadIssueModelContainer error detected", category: .storage)
                    return true
                }
                
                return false
            }
            
            let isUnknownModelVersion = containsUnknownModelError(error)
            
            if isUnknownModelVersion {
                AppLog.warning("⚠️ Database incompatible with current schema (unknown model version)", category: .storage)
                AppLog.warning("   This usually happens when the database was created with a schema version that no longer exists", category: .storage)
                AppLog.warning("   Attempting to delete incompatible database and start fresh...", category: .storage)
                
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
                            AppLog.info("   ✅ Deleted: \(filePath.split(separator: "/").last ?? "")", category: .storage)
                        } catch {
                            AppLog.error("   ❌ Failed to delete \(filePath): \(error)", category: .storage)
                        }
                    }
                }
                
                if deletedCount > 0 {
                    AppLog.info("   Deleted \(deletedCount) database file(s), attempting to recreate...", category: .storage)
                    
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
                        AppLog.info("✅ ModelContainer recreated successfully after database cleanup", category: .storage)
                        AppLog.warning("   Note: Previous local data was lost, but CloudKit data should sync back", category: .storage)
                        return container
                    } catch {
                        AppLog.error("❌ Failed to recreate container after cleanup: \(error)", category: .storage)
                        return nil
                    }
                } else {
                    AppLog.error("   No database files found to delete", category: .storage)
                    return nil
                }
            } else {
                AppLog.error("❌ CloudKit ModelContainer creation failed: \(error.localizedDescription)", category: .storage)
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
            AppLog.info("✅ ModelContainer created successfully (local-only, no CloudKit sync)", category: .storage)
            AppLog.info("   Using existing database: CloudKitModel.sqlite", category: .storage)
            AppLog.info("   Your data is preserved even though CloudKit is disabled", category: .storage)
            return container
        } catch let error as NSError {
            // Log the full error details for debugging
            AppLog.error("❌ Local ModelContainer creation failed: \(error.localizedDescription)", category: .storage)
            AppLog.error("   Error domain: \(error.domain), code: \(error.code)", category: .storage)
            AppLog.error("   Underlying error: \(String(describing: error.userInfo[NSUnderlyingErrorKey]))", category: .storage)
            
            // ✨ NEW: Analyze error chain
            let analysis = DatabaseRecoveryLogger.analyzeError(error)
            analysis.logAnalysis()
            
            if analysis.isSchemaIssue {
                // ✨ NEW: Begin tracking recovery
                DatabaseRecoveryLogger.shared.beginRecoveryAttempt()
                
                // ✨ NEW: Capture database size before deletion
                let databaseSizeMB = DatabaseRecoveryLogger.getDatabaseSize(at: cloudKitURL)
                
                AppLog.warning("⚠️ Database incompatible with current schema (unknown model version)", category: .storage)
                AppLog.warning("   This usually happens when the database was created with a schema version that no longer exists", category: .storage)
                AppLog.warning("   Attempting to delete incompatible database and start fresh...", category: .storage)
                
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
                            AppLog.info("   ✅ Deleted: \(filesDeleted.last!)", category: .storage)
                        } catch {
                            AppLog.error("   ❌ Failed to delete \(filePath): \(error)", category: .storage)
                        }
                    }
                }
                
                if filesDeleted.count > 0 {
                    AppLog.info("   Deleted \(filesDeleted.count) database file(s), attempting to recreate...", category: .storage)
                    
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
                        
                        AppLog.info("✅ ModelContainer recreated successfully after database cleanup", category: .storage)
                        AppLog.warning("   Note: Previous local data was lost, but may sync back from iCloud", category: .storage)
                        return container
                    } catch let recreationError {
                        // ✨ NEW: Log failed recovery
                        DatabaseRecoveryLogger.shared.logRecoveryFailure(
                            error: error,
                            filesDeleted: filesDeleted,
                            cloudKitEnabled: false,
                            secondaryError: recreationError
                        )
                        
                        AppLog.critical("❌ Failed to recreate container after cleanup: \(recreationError)", category: .storage)
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
                    
                    AppLog.critical("❌ No database files found to delete, cannot recover", category: .storage)
                    fatalError("Could not create ModelContainer: \(error)")
                }
            } else {
                // Non-schema issue - fatal error
                AppLog.critical("❌ All ModelContainer initialization attempts failed", category: .storage)
                AppLog.critical("   Final error: \(error)", category: .storage)
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
            
            AppLog.info("🔍 CloudKit check attempt \(attempt + 1)/\(retryDelays.count):", category: .storage)
            AppLog.info("   CloudKit available: \(cloudKitAvailable)", category: .storage)
            
            // If CloudKit is available, upgrade the container
            if cloudKitAvailable {
                AppLog.info("✅ CloudKit is available - upgrading container to enable sync...", category: .storage)
                await recreateContainer(withCloudKitEnabled: true)
                return // Success, exit retry loop
            }
        }
        
        AppLog.info("ℹ️ CloudKit not available after \(retryDelays.count) checks - continuing with local-only storage", category: .storage)
    }
    
    private func handleAccountChange() {
        AppLog.info("🔄 CloudKit account changed - checking if container recreation is needed...", category: .storage)
        
        Task {
            // Check new account status
            let wasCloudKitEnabled = isCloudKitEnabled
            let nowAvailable = await checkCurrentCloudKitStatus()
            
            // Only recreate if status actually changed
            if wasCloudKitEnabled != nowAvailable {
                AppLog.warning("⚠️ CloudKit availability changed: \(wasCloudKitEnabled) → \(nowAvailable)", category: .storage)
                AppLog.info("   Recreating ModelContainer to match new iCloud state...", category: .storage)
                
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
                AppLog.info("✓ CloudKit status unchanged, no container recreation needed", category: .storage)
            }
        }
    }
    
    private func checkCurrentCloudKitStatus() async -> Bool {
        do {
            let status = try await CKContainer.default().accountStatus()
            let isAvailable = (status == .available)
            AppLog.info("   Current CloudKit status: \(status.rawValue) (\(isAvailable ? "available" : "not available"))", category: .storage)
            
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
            AppLog.error("❌ Error checking CloudKit status: \(error.localizedDescription)", category: .storage)
            
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
            AppLog.warning("⚠️ Container recreation already in progress, skipping...", category: .storage)
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
        
        AppLog.info("🔄 Recreating ModelContainer...", category: .storage)
        if let enabled = cloudKitEnabled {
            AppLog.info("   Target CloudKit state: \(enabled ? "enabled" : "disabled")", category: .storage)
        }
        
        // Determine appropriate wait time based on current container state
        let wasCloudKitEnabled = await MainActor.run { isCloudKitEnabled }
        let waitTime: UInt64 = wasCloudKitEnabled ? 5_000_000_000 : 1_000_000_000 // 5s if CloudKit was on, 1s if local
        
        AppLog.info("   Waiting for previous container to tear down...", category: .storage)
        AppLog.info("   (Wait time: \(waitTime / 1_000_000_000) seconds - \(wasCloudKitEnabled ? "CloudKit cleanup needed" : "local-only, minimal wait"))", category: .storage)
        
        // Store reference to old container
        let oldContainer = await MainActor.run { container }
        
        // Give the old container time to tear down properly
        try? await Task.sleep(nanoseconds: waitTime)
        
        // Keep reference to ensure it stays alive until now
        _ = oldContainer.schema
        
        AppLog.info("   Creating new container...", category: .storage)
        
        // Create new container with known CloudKit state if provided
        let (newContainer, actualCloudKitEnabled) = Self.createModelContainer(forceCloudKit: cloudKitEnabled)
        
        // Replace the old container on MainActor
        await MainActor.run {
            container = newContainer
            isCloudKitEnabled = actualCloudKitEnabled
        }
        
        AppLog.info("✅ ModelContainer recreated successfully", category: .storage)
        AppLog.info("   CloudKit enabled: \(actualCloudKitEnabled)", category: .storage)
        
        // Post notification so views can refresh if needed
        await MainActor.run {
            NotificationCenter.default.post(name: .modelContainerRecreated, object: nil)
        }
    }
    
    /// Manually trigger container recreation (for testing or troubleshooting)
    func manuallyRecreateContainer() async {
        AppLog.info("🔧 Manually recreating ModelContainer...", category: .storage)
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
            
            AppLog.info("✅ Container health check passed (RecipeX, Book models verified)", category: .storage)
            return true
        } catch {
            AppLog.error("❌ Container health check failed: \(error)", category: .storage)
            
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
        AppLog.warning("🔧 Attempting container recovery...", category: .storage)
        
        // Log diagnostic info before attempting recovery
        await logDiagnosticInfo()
        
        // Step 1: Try recreating the container with current CloudKit state
        AppLog.info("   Step 1: Recreating container...", category: .storage)
        await recreateContainer(withCloudKitEnabled: isCloudKitEnabled)
        
        // Step 2: Verify the new container is working
        AppLog.info("   Step 2: Verifying container health...", category: .storage)
        if await verifyContainerHealth() {
            AppLog.info("✅ Container recovery successful!", category: .storage)
            return true
        }
        
        // Step 3: If still failing, try forcing CloudKit refresh
        if isCloudKitEnabled {
            AppLog.info("   Step 3: Attempting CloudKit container refresh...", category: .storage)
            await recreateContainer(withCloudKitEnabled: true)
            
            if await verifyContainerHealth() {
                AppLog.info("✅ Container recovery successful after CloudKit refresh!", category: .storage)
                return true
            }
        }
        
        // Step 4: Last resort - try local-only mode
        AppLog.warning("   Step 4: Attempting local-only fallback...", category: .storage)
        await recreateContainer(withCloudKitEnabled: false)
        
        if await verifyContainerHealth() {
            AppLog.warning("⚠️ Container recovered in local-only mode (CloudKit disabled)", category: .storage)
            AppLog.warning("   User may need to reinstall app to restore CloudKit sync", category: .storage)
            return true
        }
        
        // Complete failure - needs manual intervention
        AppLog.error("❌ Container recovery failed - manual intervention required", category: .storage)
        AppLog.error("   User should try: Delete app → Reinstall → Data will sync from CloudKit", category: .storage)
        return false
    }
    
    /// Log comprehensive diagnostic information about the container state
    func logDiagnosticInfo() async {
        AppLog.info("📊 ============ CONTAINER DIAGNOSTIC INFO ============", category: .storage)
        AppLog.info("📊 Runtime State:", category: .storage)
        AppLog.info("   CloudKit Enabled: \(isCloudKitEnabled)", category: .storage)
        AppLog.info("   Is Recreating: \(isRecreating)", category: .storage)
        
        AppLog.info("📊 Schema Information:", category: .storage)
        let entityNames = container.schema.entities.map { $0.name }.sorted()
        AppLog.info("   Entities: \(entityNames.joined(separator: ", "))", category: .storage)
        AppLog.info("   Entity Count: \(entityNames.count)", category: .storage)
        
        AppLog.info("📊 Database File:", category: .storage)
        if let dbURL = container.configurations.first?.url {
            AppLog.info("   Path: \(dbURL.path)", category: .storage)
            
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: dbURL.path) {
                do {
                    let attrs = try fileManager.attributesOfItem(atPath: dbURL.path)
                    if let size = attrs[.size] as? Int64 {
                        let sizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                        AppLog.info("   Size: \(sizeString)", category: .storage)
                    }
                    if let modDate = attrs[.modificationDate] as? Date {
                        AppLog.info("   Last Modified: \(modDate)", category: .storage)
                    }
                } catch {
                    AppLog.error("   ⚠️ Could not read file attributes: \(error)", category: .storage)
                }
                
                // Check for associated files (WAL, SHM)
                let walPath = dbURL.path + "-wal"
                let shmPath = dbURL.path + "-shm"
                AppLog.info("   WAL file exists: \(fileManager.fileExists(atPath: walPath))", category: .storage)
                AppLog.info("   SHM file exists: \(fileManager.fileExists(atPath: shmPath))", category: .storage)
            } else {
                AppLog.warning("   ⚠️ Database file does not exist!", category: .storage)
            }
        } else {
            AppLog.error("   ❌ No database URL configured!", category: .storage)
        }
        
        AppLog.info("📊 CloudKit Status:", category: .storage)
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
                AppLog.info("   Account Status: \(statusString)", category: .storage)
            } catch {
                AppLog.error("   ❌ Error checking account: \(error)", category: .storage)
            }
            
            AppLog.info("   Container: iCloud.com.headydiscy.reczipes", category: .storage)
        } else {
            AppLog.info("   CloudKit: Disabled (local-only mode)", category: .storage)
        }
        
        AppLog.info("📊 Data Counts:", category: .storage)
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
            
            AppLog.info("   === Unified Models ===", category: .storage)
            AppLog.info("   Recipes: \(recipeXCount)", category: .storage)
            AppLog.info("   Books: \(bookCount)", category: .storage)
            
            AppLog.info("   === Other Data ===", category: .storage)
            AppLog.info("   Cooking Sessions: \(sessionCount)", category: .storage)
            AppLog.info("   Saved Links: \(savedLinkCount)", category: .storage)
            AppLog.info("   Shared Recipes: \(sharedRecipeCount)", category: .storage)
            AppLog.info("   Shared Recipe Books: \(sharedBookCount)", category: .storage)
            
        } catch {
            AppLog.error("   ❌ Error fetching counts: \(error)", category: .storage)
        }
        
        AppLog.info("📊 ================================================", category: .storage)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let modelContainerRecreated = Notification.Name("modelContainerRecreated")
}
