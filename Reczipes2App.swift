//
//  Reczipes2App.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/4/25.
//

import SwiftUI
import SwiftData
import Combine

@main
struct Reczipes2App: App {
    
    // State management
    @StateObject private var appState = AppStateManager.shared
    @StateObject private var taskRestoration = TaskRestorationCoordinator.shared
    @StateObject private var containerManager = ModelContainerManager.shared
    @StateObject private var onboarding = CloudKitOnboardingService.shared
    
    @AppStorage("hasCompletedCloudKitOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboardingSheet = false
    
    // Startup state tracking
    @State private var isInitializing = true
    @State private var initializationComplete = false
    
    // Document handling
    @StateObject private var documentHandler = RecipeBookDocumentHandler.shared
    
    init() {
        // Suppress Auto Layout constraint warnings from UIKit internals
        UserDefaults.standard.set(false, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
        
        // Handle UI testing mode
        if ProcessInfo.processInfo.arguments.contains("UI_TESTING") {
            // Accept license and set up API key for testing
            LicenseHelper.acceptLicense()
            // Set a dummy API key for testing (won't actually work but allows UI to load)
            _ = APIKeyHelper.setAPIKey("sk-ant-test-key-for-ui-testing")
            // Skip first launch screens
            UserDefaults.standard.set(false, forKey: "shouldShowLaunchScreen")
            logInfo("🧪 UI Testing mode enabled - bypassing onboarding", category: "testing")
        }
        
        // Log CloudKit configuration for debugging (synchronous, no blocking)
        logCloudKitConfiguration()
        
        // NOTE: CloudKit checks are now deferred to background tasks after UI appears
        // See .task modifier in MainTabView for background initialization
    }
    
    // Use the shared container from the manager instead of creating our own
    var sharedModelContainer: ModelContainer {
        containerManager.container
    }
    
    // Keep the old static initializer for reference, but don't use it
    // NOTE: This is no longer used - ModelContainerManager handles container creation
    private static var _legacySharedModelContainer: ModelContainer = {
        logInfo("🚀 Legacy container initializer called (should not be used)", category: "storage")
        fatalError("Legacy container initializer should not be called - use ModelContainerManager.shared instead")
    }()
    
    @State private var showLicenseAgreement = !LicenseHelper.hasAcceptedLicense
    @State private var showAPIKeySetup = false
    @State private var showLaunchScreen = false
    @State private var showAppClipImportBanner = false
    @State private var importedRecipeName = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Show loading overlay when container is being recreated
                if containerManager.isRecreating {
                    containerRecreationOverlay
                } else {
                    MainTabView()
                        .modelContainer(sharedModelContainer)
                        .environmentObject(appState)
                        .environmentObject(taskRestoration)
                        .environmentObject(documentHandler)
                        .fullScreenCover(isPresented: $showLicenseAgreement) {
                            LicenseAgreementView(isPresented: $showLicenseAgreement)
                                .onDisappear {
                                    // After license is accepted, check if API key setup is needed
                                    if LicenseHelper.hasAcceptedLicense {
                                        showAPIKeySetup = !APIKeyHelper.isConfigured
                                    }
                                }
                        }
                        .fullScreenCover(isPresented: $showAPIKeySetup) {
                            APIKeySetupView(isPresented: $showAPIKeySetup)
                        }
                        .diagnosticsCapable()
                        .shakeToShowDiagnostics()
                        .onAppear {
                            // Only perform non-critical UI setup on appear
                            // Defer async work until we're sure the app is active
                            showLicenseAgreement = !LicenseHelper.hasAcceptedLicense
                            if LicenseHelper.hasAcceptedLicense {
                                showAPIKeySetup = !APIKeyHelper.isConfigured
                            }
                            
                            // Show launch screen every launch (only if onboarding is complete)
                            if LicenseHelper.hasAcceptedLicense && APIKeyHelper.isConfigured {
                                showLaunchScreen = appState.shouldShowLaunchScreen()
                            }
                        }
                        .task {
                            // Guard against backgrounding during startup
                            guard scenePhase != .background else {
                                logWarning("⚠️ Skipping startup tasks - app is in background", category: "state")
                                return
                            }
                            
                            // Perform startup initialization in a structured way
                            await performStartupInitialization()
                        }
                        .sheet(isPresented: $showOnboardingSheet) {
                            CloudKitOnboardingView()
                                .environmentObject(onboarding)
                                .onDisappear {
                                    // Mark as completed when they dismiss
                                    // (even if not fully set up, don't nag them)
                                    hasCompletedOnboarding = true
                                }
                        }
                        .sheet(isPresented: $documentHandler.showImportSheet) {
                            RecipeBookImportSheet(handler: documentHandler)
                                .modelContainer(sharedModelContainer)
                        }
                    
                    // Launch screen overlay - shows briefly on every launch (after onboarding)
                    if showLaunchScreen && LicenseHelper.hasAcceptedLicense && APIKeyHelper.isConfigured {
                        LaunchScreenView {
                            // Dismiss launch screen
                            withAnimation {
                                showLaunchScreen = false
                            }
                        }
                        .transition(.opacity)
                        .zIndex(1)
                    }
                    
                    // App Clip import banner
                    if showAppClipImportBanner {
                        VStack {
                            AppClipImportBanner(
                                recipeName: importedRecipeName,
                                isPresented: $showAppClipImportBanner
                            )
                            .padding()
                            Spacer()
                        }
                        .zIndex(2)
                    }
                    
                    // Task restoration prompt
                    if taskRestoration.showRestorationPrompt {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .zIndex(2)
                        
                        TaskRestorationPromptView(
                            coordinator: taskRestoration,
                            modelContainer: sharedModelContainer
                        )
                        .zIndex(3)
                    }
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                logInfo("Scene phase changing: \(String(describing: oldPhase)) -> \(String(describing: newPhase))", category: "state")
                handleScenePhaseChange(oldPhase: oldPhase, newPhase: newPhase)
            }
            .onOpenURL { url in
                logInfo("Received URL: \(url)", category: "document")
                
                // Check if this is a .recipebook file
                if url.pathExtension == RecipeBookPackageType.fileExtension {
                    documentHandler.handleIncomingDocument(url)
                }
            }
        }
        .handlesExternalEvents(matching: [])
    }
    

    // MARK: - Container Recreation Overlay
    
    private var containerRecreationOverlay: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                
                Text("Updating iCloud Connection")
                    .font(.headline)
                
                Text("Please wait while we reconnect to iCloud...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }
    
    
    // MARK: - App Clip Data Import
    
    private func checkForAppClipData() {
        let modelContext = sharedModelContainer.mainContext
        
        Task { @MainActor in
            let didImport = AppClipDataHandler.checkForPendingRecipe(modelContext: modelContext)
            
            if didImport {
                // Show success banner
                withAnimation {
                    importedRecipeName = "Recipe imported successfully"
                    showAppClipImportBanner = true
                }
                
                // Auto-dismiss after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation {
                        showAppClipImportBanner = false
                    }
                }
                
                // Share API key with App Clip if available
                if let apiKey = APIKeyHelper.getAPIKey() {
                    AppClipDataHandler.shareAPIKeyWithAppClip(apiKey)
                }
            }
        }
    }
    
    // MARK: - Version History Initialization
    
    @MainActor
    private func initializeVersionHistory() async {
        let modelContext = sharedModelContainer.mainContext
        
        // Initialize the service
        VersionHistoryService.shared.initialize(modelContext: modelContext)
        
        // Import historical data (one-time migration)
        // This checks for duplicates, so it's safe to call every time
        do {
            try await VersionHistoryMigration.importHistoricalData(into: modelContext)
        } catch {
            logError("Failed to import version history: \(error)", category: "version-history")
        }
        
        // Add/update current version entry
        await addCurrentVersionToHistory(modelContext: modelContext)
    }
    
    // MARK: - Startup Initialization
    
    @MainActor
    private func performStartupInitialization() async {
        isInitializing = true
        
        logInfo("🚀 Starting app initialization...", category: "state")
        
        // Check scene phase before each async operation
        guard scenePhase != .background else {
            logWarning("⚠️ Initialization cancelled - app moved to background", category: "state")
            isInitializing = false
            return
        }
        
        // Step 1: Check for App Clip data (quick, non-blocking)
        checkForAppClipData()
        
        // Step 2: Initialize version history (async but safe to defer)
        await initializeVersionHistory()
        
        // Check scene phase again
        guard scenePhase != .background else {
            logWarning("⚠️ Initialization cancelled - app moved to background", category: "state")
            isInitializing = false
            return
        }
        
        // Step 3: Run CloudKit diagnostics if needed
        if !hasCompletedOnboarding {
            await onboarding.runComprehensiveDiagnostics()
            
            // Check scene phase after diagnostics
            guard scenePhase != .background else {
                logWarning("⚠️ Initialization cancelled - app moved to background", category: "state")
                isInitializing = false
                return
            }
            
            // Show onboarding if not ready
            if case .ready = onboarding.onboardingState {
                hasCompletedOnboarding = true
            } else {
                showOnboardingSheet = true
            }
        }
        
        isInitializing = false
        initializationComplete = true
        logInfo("✅ App initialization complete", category: "state")
    }
    
    // MARK: - Scene Phase Handling
    
    private func handleScenePhaseChange(oldPhase: ScenePhase, newPhase: ScenePhase) {
        // Notify app state manager
        appState.handleScenePhaseChange(newPhase)
        
        switch newPhase {
        case .active:
            logInfo("App became active", category: "state")
            
            // If we were interrupted during initialization, retry it
            if isInitializing && !initializationComplete {
                logInfo("   Resuming interrupted initialization...", category: "state")
                Task { @MainActor in
                    await performStartupInitialization()
                }
            } else if oldPhase == .background && initializationComplete {
                logInfo("   App returning from background", category: "state")
                
                // Ensure we're on main actor for all UI and state operations
                Task { @MainActor in
                    taskRestoration.checkForTaskRestoration()
                    
                    // Notify background manager on main actor
                    BackgroundProcessingManager.shared.handleAppWillEnterForeground()
                }
            }
            
        case .inactive:
            // App is becoming inactive (e.g., phone call, control center)
            // This is our last chance to save before potential force-kill
            logInfo("App becoming inactive - saving data", category: "state")
            savePendingChanges()
            
        case .background:
            // App is going to background - state is automatically saved by AppStateManager
            logInfo("App entering background", category: "state")
            
            // If we're still initializing, mark it as cancelled
            if isInitializing {
                logWarning("   App backgrounded during initialization", category: "state")
                isInitializing = false
            }
            
            // Save data synchronously to avoid race conditions
            savePendingChanges()
            
            // Handle background processing - this is now non-blocking
            BackgroundProcessingManager.shared.handleAppDidEnterBackground()
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Data Persistence
    
    /// Saves pending changes synchronously to ensure no data loss during state transitions
    @MainActor
    private func savePendingChanges() {
        let modelContext = sharedModelContainer.mainContext
        
        guard modelContext.hasChanges else {
            logDebug("No pending changes to save", category: "state")
            return
        }
        
        do {
            try modelContext.save()
            logInfo("✅ Successfully saved pending changes to SwiftData", category: "state")
        } catch {
            logError("❌ Failed to save pending changes: \(error)", category: "state")
            
            logUserDiagnostic(
                .error,
                category: .storage,
                title: "Save Failed",
                message: "Could not save your recent changes. They may be lost.",
                technicalDetails: error.localizedDescription,
                suggestedActions: [
                    DiagnosticAction(
                        title: "Check Storage Space",
                        description: "Make sure your device has enough storage space",
                        actionType: .openSettings(.general)
                    )
                ]
            )
        }
    }
    
    // MARK: - CloudKit Diagnostics
    
    private func logCloudKitConfiguration() {
        logInfo("📱 CLOUDKIT CONFIGURATION", category: "storage")
        logInfo("   Container ID: iCloud.com.headydiscy.reczipes", category: "storage")
        logInfo("   Configuration: Private Database", category: "storage")
        logInfo("   Framework: SwiftData (not Core Data)", category: "storage")
        
        // Log user-facing diagnostic
        logUserDiagnostic(
            .info,
            category: .storage,
            title: "App Configuration",
            message: "Using iCloud container: iCloud.com.headydiscy.reczipes",
            technicalDetails: "Private Database with SwiftData framework"
        )
        
        // Check for multiple database files
        checkForMultipleDatabases()
    }
    
    private func checkForMultipleDatabases() {
        logInfo("🔍 DATABASE FILE DIAGNOSTICS", category: "storage")
        
        let appSupport = URL.applicationSupportDirectory
        let fileManager = FileManager.default
        
        // Check for different database files
        let possibleDatabases = [
            "CloudKitModel.sqlite",
            "default.store",
            "Model.sqlite",
            "Reczipes2.sqlite"
        ]
        
        var foundDatabases: [(name: String, size: Int64, modified: Date)] = []
        
        for dbName in possibleDatabases {
            let dbURL = appSupport.appendingPathComponent(dbName)
            
            if fileManager.fileExists(atPath: dbURL.path) {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: dbURL.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    let modDate = attributes[.modificationDate] as? Date ?? Date.distantPast
                    
                    foundDatabases.append((name: dbName, size: fileSize, modified: modDate))
                    
                    let sizeString = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                    logInfo("✅ Found database: \(dbName) (\(sizeString))", category: "storage")
                } catch {
                    logWarning("⚠️ Found \(dbName) but couldn't read attributes: \(error)", category: "storage")
                }
            }
        }
        
        if foundDatabases.isEmpty {
            logInfo("Fresh install - no existing database files", category: "storage")
            
            logUserDiagnostic(
                .info,
                category: .storage,
                title: "Fresh Installation",
                message: "This is a new installation with no existing data.",
                technicalDetails: "No database files found in app support directory"
            )
        } else if foundDatabases.count > 1 {
            logWarning("🚨 CRITICAL: Multiple database files detected!", category: "storage")
            logWarning("   This may explain missing recipes after update", category: "storage")
            
            if let largest = foundDatabases.max(by: { $0.size < $1.size }) {
                let sizeString = ByteCountFormatter.string(fromByteCount: largest.size, countStyle: .file)
                logInfo("   Largest file (active): \(largest.name) - \(sizeString)", category: "storage")
                
                // Log user-facing diagnostic about multiple databases
                logUserDiagnostic(
                    .warning,
                    category: .storage,
                    title: "Multiple Database Files Detected",
                    message: "Found \(foundDatabases.count) database files. Using: \(largest.name)",
                    technicalDetails: "Files: \(foundDatabases.map { $0.name }.joined(separator: ", "))",
                    suggestedActions: [
                        DiagnosticAction(
                            title: "Check Data",
                            description: "Verify all your recipes are showing correctly",
                            actionType: .retryOperation
                        ),
                        DiagnosticAction(
                            title: "Database Maintenance",
                            description: "Go to Settings > Developer Tools > Database Maintenance",
                            actionType: .openSettings(.general)
                        )
                    ]
                )
            }
        } else {
            // Single database found - this is normal
            if let db = foundDatabases.first {
                let sizeString = ByteCountFormatter.string(fromByteCount: db.size, countStyle: .file)
                logInfo("Using database: \(db.name) (\(sizeString))", category: "storage")
            }
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject private var appState: AppStateManager
    @StateObject private var sharingService = CloudKitSharingService.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $appState.currentTab) {
            // Existing recipes tab
            ContentView()
                .tabItem {
                    Label("Recipes", systemImage: "book.fill")
                }
                .tag(AppTab.recipes)
            
            // Recipe Books tab
            RecipeBooksView()
                .tabItem {
                    Label("Books", systemImage: "books.vertical.fill")
                }
                .tag(AppTab.books)
            // Meals tab — group recipes into a complete meal
            MealsView()
                .tabItem {
                    Label("Meals", systemImage: "fork.knife.circle.fill")
                }
                .tag(AppTab.meals)
            // NEW: Cooking Mode tab
            CookingView()
                .tabItem {
                    Label("Cooking", systemImage: "flame.fill")
                }
                .tag(AppTab.cooking)
            // Extraction tab - always visible
            RecipeExtractorTabWrapper()
                .tabItem {
                    Label("Extract", systemImage: "camera.fill")
                }
                .tag(AppTab.extract)
            // Settings tab
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(AppTab.settings)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                DiagnosticButton()
            }
        }
        .task {
            // Perform background initialization tasks after UI has appeared
            // This prevents blocking the UI during app launch
            await performBackgroundInitialization()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(oldPhase: oldPhase, newPhase: newPhase)
        }
    }
    
    // MARK: - Background Initialization
    
    /// Performs non-critical initialization tasks in the background after UI appears
    private func performBackgroundInitialization() async {
        // Check CloudKit status (non-blocking)
        // The ModelContainerManager will automatically upgrade to CloudKit if available
        await CloudKitSyncMonitor.shared.checkAccountStatus()

        // Start auto-sync if enabled
        if sharingService.autoSyncEnabled {
            await sharingService.startAutoSync(modelContext: modelContext)
            logInfo("🔄 Auto-sync started during app initialization", category: "sharing")
        }

        // Note: ModelContainerManager already handles CloudKit upgrade asynchronously
        // in its own init() with a 1-second delay, so we don't need to trigger it here

        // Run image optimization migration if needed
        await runImageMigrationIfNeeded()
    }

    /// Run image optimization migration in background
    private func runImageMigrationIfNeeded() async {
        let migrationManager = ImageMigrationManager.shared

        // Check if migration is needed
        guard migrationManager.needsMigration() else {
            logInfo("Image optimization migration not needed", category: "image")
            return
        }

        logInfo("🖼️ Starting background image optimization migration...", category: "image")

        // Run migration in background
        await migrationManager.runFullMigration(modelContext: modelContext)

        // Migration completed - automatic CloudKit sync will handle the rest
        // (recipes marked with needsCloudSync will be synced by RecipeXCloudKitSyncService)
        logInfo("✅ Image migration completed - modified recipes will sync to CloudKit automatically", category: "image")
    }
    
    // MARK: - Scene Phase Handling
    
    private func handleScenePhaseChange(oldPhase: ScenePhase, newPhase: ScenePhase) {
        Task { @MainActor in
            switch newPhase {
            case .active:
                // App became active - restart auto-sync if enabled
                if sharingService.autoSyncEnabled {
                    await sharingService.startAutoSync(modelContext: modelContext)
                    logInfo("🔄 Auto-sync restarted (app became active)", category: "sharing")
                }
                
            case .background, .inactive:
                // App going to background/inactive - stop auto-sync to save battery
                sharingService.stopAutoSync()
                logInfo("🔄 Auto-sync stopped (app entering background/inactive)", category: "sharing")
                
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Recipe Extractor Tab Wrapper

struct RecipeExtractorTabWrapper: View {
    @State private var isAPIKeyConfigured = APIKeyHelper.isConfigured
    
    var body: some View {
        if isAPIKeyConfigured, let apiKey = APIKeyHelper.getAPIKey() {
            RecipeExtractorView(apiKey: apiKey)
                .onAppear {
                    // Refresh API key status when tab appears
                    isAPIKeyConfigured = APIKeyHelper.isConfigured
                }
        } else {
            // Show a helpful message when API key isn't configured
            NavigationView {
                VStack(spacing: 20) {
                    Image(systemName: "key.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("API Key Required")
                        .font(.title2)
                        .bold()
                    
                    Text("To extract recipes from images, you need to configure your Claude API key.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    NavigationLink(destination: APIKeyManagerView()) {
                        Label("Set Up API Key", systemImage: "key.fill")
                            .font(.headline)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    Text("You can also set up your API key in Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .navigationTitle("Extract Recipe")
                .onAppear {
                    // Refresh API key status when tab appears
                    isAPIKeyConfigured = APIKeyHelper.isConfigured
                }
            }
        }
    }
}

