//
//  BackgroundProcessingManager.swift
//  Reczipes2
//
//  Created for true background processing support
//

import Foundation
#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import UserNotifications
import SwiftData
import Combine

/// Manager for handling background processing tasks when app is backgrounded
class BackgroundProcessingManager: ObservableObject {
    static let shared = BackgroundProcessingManager()
    
    // Background task identifier - must match Info.plist
    private let backgroundTaskIdentifier = "com.reczipes.backgroundExtraction"
    
    // Processing state (main actor isolated for UI updates)
    @MainActor @Published var isBackgroundTaskActive = false
    @MainActor @Published var backgroundProgress: Double = 0.0
    
    // Background task reference (accessed from multiple threads)
    private let backgroundTaskLock = NSLock()
    #if os(iOS)
    private var _backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTask: UIBackgroundTaskIdentifier {
        get {
            backgroundTaskLock.lock()
            defer { backgroundTaskLock.unlock() }
            return _backgroundTask
        }
        set {
            backgroundTaskLock.lock()
            defer { backgroundTaskLock.unlock() }
            _backgroundTask = newValue
        }
    }
    #endif
    
    // Queue for pending extractions (thread-safe via actor)
    private let extractionQueue = ExtractionQueue()
    private var apiKey: String?
    private var modelContext: ModelContext?
    
    private init() {}
    
    // MARK: - Configuration
    
    /// Register background task handler - call from AppDelegate
    func registerBackgroundTasks() {
        #if os(iOS)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self else { return }

            // Cast to BGProcessingTask
            guard let processingTask = task as? BGProcessingTask else {
                AppLog.error("Task is not a BGProcessingTask", category: .background)
                task.setTaskCompleted(success: false)
                return
            }

            // Handle the task directly without Task.detached to avoid sendability issues
            // The handler already runs on a background queue
            Task { [weak self] in
                guard let self = self else {
                    processingTask.setTaskCompleted(success: false)
                    return
                }

                await self.handleBackgroundProcessing(
                    task: processingTask,
                    apiKey: self.apiKey,
                    modelContext: self.modelContext,
                    extractionQueue: self.extractionQueue
                )
            }
        }

        AppLog.info("Background task handler registered: \(backgroundTaskIdentifier)", category: .background)
        #else
        AppLog.info("Background task registration is a no-op on this platform", category: .background)
        #endif
    }

    /// Configure with API key and model context
    func configure(apiKey: String, modelContext: ModelContext) {
        self.apiKey = apiKey
        self.modelContext = modelContext
        AppLog.info("BackgroundProcessingManager configured", category: .background)
    }

    // MARK: - Background Task Scheduling

    /// Schedule a background processing task
    func scheduleBackgroundExtraction() {
        #if os(iOS)
        let request = BGProcessingTaskRequest(identifier: backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false // Allow on battery
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1) // Start ASAP

        do {
            try BGTaskScheduler.shared.submit(request)
            AppLog.info("Background extraction task scheduled", category: .background)
        } catch {
            AppLog.error("Failed to schedule background task: \(error)", category: .background)
        }
        #endif
    }

    /// Cancel any scheduled background tasks
    func cancelBackgroundTasks() {
        #if os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskIdentifier)
        #endif
    }

    // MARK: - Foreground Background Task (for immediate backgrounding)

    /// Start a foreground background task that continues when app is backgrounded
    func beginBackgroundTask(name: String = "Recipe Extraction") {
        #if os(iOS)
        endBackgroundTask() // End any existing task

        let newTask = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // Task expiration handler
            AppLog.warning("Background task expired, cleaning up", category: .background)
            self?.endBackgroundTask()
        }

        backgroundTask = newTask

        if newTask != .invalid {
            Task { @MainActor in
                self.isBackgroundTaskActive = true
            }
        } else {
            AppLog.error("Failed to start background task", category: .background)
        }
        #endif
    }

    /// End the foreground background task
    func endBackgroundTask() {
        #if os(iOS)
        let taskToEnd = backgroundTask
        guard taskToEnd != .invalid else { return }

        UIApplication.shared.endBackgroundTask(taskToEnd)
        backgroundTask = .invalid

        Task { @MainActor in
            self.isBackgroundTaskActive = false
        }
        #endif
    }
    
    // MARK: - Background Processing Handler
    
    #if os(iOS)
    /// Handle background processing task (runs on background queue)
    private func handleBackgroundProcessing(
        task: BGProcessingTask,
        apiKey: String?,
        modelContext: ModelContext?,
        extractionQueue: ExtractionQueue
    ) async {
        AppLog.info("Background processing task started", category: .background)

        // Track if task was expired
        var taskExpired = false

        // Set expiration handler
        task.expirationHandler = {
            AppLog.warning("Background processing task expired", category: .background)
            taskExpired = true
        }

        // Get pending extractions safely
        let extractionsToProcess = await extractionQueue.getAll()

        // Process pending extractions
        guard !extractionsToProcess.isEmpty,
              let apiKey = apiKey,
              let modelContext = modelContext else {
            AppLog.warning("No pending extractions or missing configuration", category: .background)
            task.setTaskCompleted(success: true)
            return
        }

        AppLog.info("Processing \(extractionsToProcess.count) pending extractions in background", category: .background)

        let apiClient = ClaudeAPIClient(apiKey: apiKey)
        var successCount = 0
        var failureCount = 0

        for (imageData, _) in extractionsToProcess {
            // Bail if the system signaled expiration via the handler above.
            guard !taskExpired else { break }

            do {
                let recipe = try await apiClient.extractRecipe(
                    from: imageData,
                    usePreprocessing: true
                )

                // Save recipe on background thread
                await saveRecipe(recipe, withImageData: imageData, modelContext: modelContext)

                successCount += 1
                let progress = Double(successCount + failureCount) / Double(extractionsToProcess.count)

                // Update UI on main actor
                await MainActor.run {
                    self.backgroundProgress = progress
                }
            } catch {
                AppLog.error("Failed to extract recipe in background: \(error)", category: .background)
                failureCount += 1
                let progress = Double(successCount + failureCount) / Double(extractionsToProcess.count)

                // Update UI on main actor
                await MainActor.run {
                    self.backgroundProgress = progress
                }
            }
        }

        // Clear queue safely
        await extractionQueue.clear()

        // Reset progress on main actor
        await MainActor.run {
            self.backgroundProgress = 0.0
        }

        AppLog.info("Background processing complete: \(successCount) success, \(failureCount) failures", category: .background)

        // Mark task as completed
        task.setTaskCompleted(success: successCount > 0)

        // Schedule notification if needed
        await scheduleCompletionNotification(successCount: successCount, failureCount: failureCount)
    }
    #endif

    // MARK: - Queue Management

    /// Add images to the pending extraction queue
    func queueExtractions(images: [(data: Data, index: Int)]) {
        Task {
            let converted = images.map { (imageData: $0.data, index: $0.index) }
            await extractionQueue.append(contentsOf: converted)
            let count = await extractionQueue.count
            AppLog.info("Added \(images.count) images to extraction queue. Total: \(count)", category: .background)
        }
    }

    /// Clear the extraction queue
    func clearQueue() {
        Task {
            await extractionQueue.clear()

            await MainActor.run {
                self.backgroundProgress = 0.0
            }
            AppLog.info("Extraction queue cleared", category: .background)
        }
    }
    
    /// Get the number of pending extractions
    var pendingCount: Int {
        get async {
            await extractionQueue.count
        }
    }
    
    // MARK: - Helper Methods
    
    private func saveRecipe(_ recipe: RecipeX, withImageData imageData: Data, modelContext: ModelContext) async {

        // Convert Data back to PlatformImage for saving
        if let image = PlatformImage(data: imageData) {
            recipe.setImage(image, isMainImage: true)
        }
        
        modelContext.insert(recipe)
        
        if let imageName = recipe.imageName {
            let assignment = RecipeImageAssignment(recipeID: recipe.id!, imageName: imageName)
            modelContext.insert(assignment)
        }
        
        do {
            try modelContext.save()
        } catch {
            AppLog.error("Failed to save recipe in background: \(error)", category: .background)
        }
    }

    private func scheduleCompletionNotification(successCount: Int, failureCount: Int) async {
        guard successCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Recipe Extraction Complete"
        content.body = "Extracted \(successCount) recipes successfully"
        if failureCount > 0 {
            content.body += " (\(failureCount) failed)"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "recipe-extraction-complete",
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            AppLog.error("Failed to schedule notification: \(error)", category: .background)
        }
    }
}

// MARK: - App Lifecycle Integration

extension BackgroundProcessingManager {
    
    /// Call this when app enters background during extraction
    /// Note: This must complete quickly to avoid crashes. Heavy work is deferred.
    func handleAppDidEnterBackground() {
        // INTENTIONAL: `Task.detached` is load-bearing here. A plain `Task { @MainActor in ... }`
        // inherits the caller's MainActor context, which can be suspended mid-flight when the
        // scene phase transitions to `.background` — that produced the historical crash fixed
        // in Docs/STARTUP_BACKGROUND_CRASH_FIX.md. Detaching keeps this query off MainActor so
        // it survives the suspension, then we hop back to MainActor explicitly for UI calls.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            let count = await self.extractionQueue.count
            guard count > 0 else {
                AppLog.info("App entering background with no pending extractions", category: .lifecycle)
                return
            }

            await MainActor.run {
                AppLog.info("App entering background with \(count) pending extractions", category: .lifecycle)

                // Start a background task to give us more time
                self.beginBackgroundTask(name: "Recipe Extraction Continuation")

                // Also schedule a background processing task for later
                self.scheduleBackgroundExtraction()
            }
        }
    }

    /// Call this when app enters foreground
    func handleAppWillEnterForeground() {
        AppLog.info("App entering foreground", category: .lifecycle)

        // End any active background tasks immediately
        // This is safe and should be done synchronously
        #if os(iOS)
        if backgroundTask != .invalid {
            endBackgroundTask()
        }
        #endif

        // INTENTIONAL: `Task.detached` is load-bearing — see `handleAppDidEnterBackground`
        // above and Docs/STARTUP_BACKGROUND_CRASH_FIX.md. Do not convert to a plain
        // `Task { @MainActor in ... }`; the detached context decouples this work from
        // the scene-phase transition that triggered it.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            let count = await self.extractionQueue.count

            await MainActor.run {
                // Cancel any scheduled background tasks since we're back in foreground
                if count == 0 {
                    self.cancelBackgroundTasks()
                } else {
                    AppLog.info("Still have \(count) pending extractions, keeping background task active", category: .lifecycle)
                }
            }
        }
    }

    /// Call this when app is about to terminate
    func handleAppWillTerminate() {
        Task {
            let count = await extractionQueue.count
            AppLog.info("App terminating with \(count) pending extractions", category: .lifecycle)

            // Schedule background task to finish later
            if count > 0 {
                scheduleBackgroundExtraction()
            }
        }

        // Clean up any active background tasks
        endBackgroundTask()
    }
}
// MARK: - Extraction Queue Actor

/// Thread-safe actor for managing the extraction queue
private actor ExtractionQueue {
    private var items: [(imageData: Data, index: Int)] = []
    
    func append(contentsOf newItems: [(imageData: Data, index: Int)]) {
        items.append(contentsOf: newItems)
    }
    
    func getAll() -> [(imageData: Data, index: Int)] {
        return items
    }
    
    func clear() {
        items.removeAll()
    }
    
    var count: Int {
        items.count
    }
}

