//
//  BatchExtractionManager.swift
//  Reczipes2
//
//  Created for background batch recipe extraction
//

import SwiftUI
import SwiftData
import Combine

/// Detailed extraction step for better progress tracking
enum ExtractionStep: String {
    case fetching = "Fetching recipe page..."
    case analyzing = "Analyzing with Claude AI..."
    case downloadingImages = "Downloading images..."
    case savingRecipe = "Saving recipe..."
    case waiting = "Waiting before next extraction..."
    case complete = "Complete"
    case failed = "Failed"
}

/// Detailed status for current extraction
struct ExtractionStatus {
    let currentIndex: Int
    let totalCount: Int
    let currentLink: SavedLink?
    let currentRecipe: RecipeX?
    let currentStep: ExtractionStep
    let stepProgress: Double // 0.0 to 1.0 for current step
    let imagesDownloaded: Int
    let totalImages: Int
    let timeElapsed: TimeInterval
    let estimatedTimeRemaining: TimeInterval?
}

/// Singleton manager for background batch extraction
@MainActor
class BatchExtractionManager: ObservableObject {
    static let shared = BatchExtractionManager()
    
    // MARK: - Published Properties
    
    @Published var isExtracting = false
    @Published var isPaused = false
    @Published var currentStatus: ExtractionStatus?
    @Published var totalProcessed: Int = 0
    @Published var successCount: Int = 0
    @Published var failureCount: Int = 0
    @Published var errorLog: [(link: String, error: String, timestamp: Date)] = []
    @Published var currentRecipe: RecipeX?
    @Published var recentlyExtracted: [RecipeX] = [] // Last 5 extracted recipes
    
    // MARK: - Private Properties
    
    private var modelContext: ModelContext?
    private var apiKey: String?
    private let extractionInterval: TimeInterval = 5.0
    private let maxBatchSize: Int = 50
    private var extractionTask: Task<Void, Never>?
    private var startTime: Date?
    private var averageExtractionTime: TimeInterval = 30.0 // Initial estimate
    private var extractionTimes: [TimeInterval] = []
    
    private let webImageDownloader = WebImageDownloader()
    
    // MARK: - Initialization
    
    private init() {
        AppLog.info("BatchExtractionManager initialized", category: .batch)
    }
    
    // MARK: - Configuration
    
    func configure(apiKey: String, modelContext: ModelContext) {
        self.apiKey = apiKey
        self.modelContext = modelContext
    }
    
    // MARK: - Public Methods
    
    /// Start batch extraction in the background
    func startBatchExtraction(links: [SavedLink]) {
        guard !isExtracting else {
            AppLog.warning("Extraction already in progress", category: .batch)
            return
        }
        
        guard let apiKey = apiKey, let modelContext = modelContext else {
            AppLog.error("BatchExtractionManager not configured", category: .batch)
            return
        }
        
        let unprocessedLinks = links.filter { !$0.isProcessed }
        guard !unprocessedLinks.isEmpty else {
            AppLog.info("No unprocessed links to extract", category: .batch)
            return
        }
        
        // Limit to maxBatchSize recipes
        let linksToProcess = Array(unprocessedLinks.prefix(maxBatchSize))
        
        isExtracting = true
        isPaused = false
        totalProcessed = 0
        successCount = 0
        failureCount = 0
        errorLog = []
        recentlyExtracted = []
        startTime = Date()
        
        AppLog.info("Starting batch extraction of \(linksToProcess.count) links", category: .batch)
        
        // Start extraction task that runs independently
        // Use Task (inherits actor context) instead of Task.detached to avoid data races
        extractionTask = Task { [weak self] in
            await self?.performBatchExtraction(links: linksToProcess, apiKey: apiKey, modelContext: modelContext)
        }
    }
    
    /// Pause the batch extraction
    func pause() {
        isPaused = true
        AppLog.info("Batch extraction paused", category: .batch)
    }
    
    /// Resume the batch extraction
    func resume() {
        isPaused = false
        AppLog.info("Batch extraction resumed", category: .batch)
    }
    
    /// Stop the batch extraction
    func stop() {
        extractionTask?.cancel()
        extractionTask = nil
        
        Task { @MainActor in
            self.isExtracting = false
            self.isPaused = false
            self.currentStatus = nil
            AppLog.info("Batch extraction stopped", category: .batch)
        }
    }
    
    /// Reset all state
    func reset() {
        totalProcessed = 0
        successCount = 0
        failureCount = 0
        errorLog = []
        currentStatus = nil
        currentRecipe = nil
        recentlyExtracted = []
        startTime = nil
    }
    
    /// Clear configuration (primarily for testing)
    func clearConfiguration() {
        apiKey = nil
        modelContext = nil
    }
    
    // MARK: - Background Extraction
    
    private func performBatchExtraction(links: [SavedLink], apiKey: String, modelContext: ModelContext) async {
        for (index, link) in links.enumerated() {
            // Check if task was cancelled
            guard !Task.isCancelled else {
                await MainActor.run {
                    self.isExtracting = false
                }
                AppLog.info("Batch extraction cancelled", category: .batch)
                break
            }
            
            // Wait while paused
            while await isPausedCheck() && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            guard !Task.isCancelled else { break }
            
            let extractionStart = Date()
            
            // Update status
            await updateStatus(
                currentIndex: index + 1,
                totalCount: links.count,
                currentLink: link,
                step: .fetching,
                stepProgress: 0.0
            )
            
            // Extract the recipe
            await extractSingleLink(link, index: index + 1, total: links.count, modelContext: modelContext, apiKey: apiKey)
            
            // Record extraction time
            let extractionTime = Date().timeIntervalSince(extractionStart)
            await recordExtractionTime(extractionTime)
            
            // Wait for the interval before next extraction (except for last one)
            if index < links.count - 1 && !Task.isCancelled {
                await performWait(remaining: links.count - index - 1)
            }
        }
        
        // Extraction complete
        if !Task.isCancelled {
            await MainActor.run {
                self.isExtracting = false
                AppLog.info("Batch extraction complete: \(self.successCount) succeeded, \(self.failureCount) failed", category: .batch)
            }
        }
    }
    
    @MainActor
    private func extractSingleLink(_ link: SavedLink, index: Int, total: Int, modelContext: ModelContext, apiKey: String) async {
        do {
            // Step 1: Fetch and analyze
            await updateStatus(
                currentIndex: index,
                totalCount: total,
                currentLink: link,
                step: .analyzing,
                stepProgress: 0.1
            )
            
            // Create extractor (we're on MainActor now)
            let extractor = RecipeExtractorViewModel(apiKey: apiKey)
            
            // Perform extraction
            await extractor.extractRecipe(from: link.url)
            
            // Check for errors
            if let error = extractor.errorMessage {
                throw NSError(
                    domain: "BatchExtraction",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: error]
                )
            }
            
            guard let recipe = extractor.extractedRecipe else {
                throw NSError(
                    domain: "BatchExtraction",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "No recipe extracted"]
                )
            }
            
            // Get image URLs
            let imageURLs = extractor.extractedImageURLs
            AppLog.info("DEBUG: extractor.extractedImageURLs has \(imageURLs.count) URLs", category: .batch)
            if !imageURLs.isEmpty {
                let firstThree = Array(imageURLs.prefix(3))
                AppLog.info("DEBUG: First 3 URLs: \(firstThree)", category: .batch)
            }
            
            await updateStatus(
                currentIndex: index,
                totalCount: total,
                currentLink: link,
                step: .analyzing,
                stepProgress: 0.5
            )
            
            // Store current recipe
            self.currentRecipe = recipe
            
            // Step 2: Download images
            var downloadedImages: [UIImage] = []
            
            AppLog.info("Found \(imageURLs.count) image URL(s) from extractor for '\(link.title)'", category: .batch)
            if imageURLs.isEmpty {
                AppLog.warning("No images found for '\(link.title)' - recipe will be saved without images", category: .batch)
            } else {
                AppLog.info("Image URLs: \(imageURLs.prefix(3).joined(separator: ", "))", category: .batch)
            }
            
            if !imageURLs.isEmpty {
                await updateStatus(
                    currentIndex: index,
                    totalCount: total,
                    currentLink: link,
                    step: .downloadingImages,
                    stepProgress: 0.0,
                    imagesDownloaded: 0,
                    totalImages: imageURLs.count
                )
                
                for (imgIndex, imageURL) in imageURLs.enumerated() {
                    do {
                        let image = try await webImageDownloader.downloadImage(from: imageURL)
                        downloadedImages.append(image)
                        
                        await updateStatus(
                            currentIndex: index,
                            totalCount: total,
                            currentLink: link,
                            step: .downloadingImages,
                            stepProgress: Double(imgIndex + 1) / Double(imageURLs.count),
                            imagesDownloaded: imgIndex + 1,
                            totalImages: imageURLs.count
                        )
                    } catch {
                        AppLog.warning("Failed to download image \(imgIndex + 1): \(error)", category: .batch)
                    }
                }
            }
            
            // Step 3: Save recipe
            await updateStatus(
                currentIndex: index,
                totalCount: total,
                currentLink: link,
                step: .savingRecipe,
                stepProgress: 0.8
            )
            
            // Clean up image URL notes before saving
            cleanupImageURLNotes(from: recipe)
            
            // Save recipe with downloaded images
            try await saveRecipe(recipe, images: downloadedImages, link: link, modelContext: modelContext)
            
            // Mark as success
            self.successCount += 1
            self.totalProcessed += 1
            
            // Add to recently extracted (keep last 5)
            self.recentlyExtracted.insert(recipe, at: 0)
            if self.recentlyExtracted.count > 5 {
                self.recentlyExtracted = Array(self.recentlyExtracted.prefix(5))
            }
            
            link.isProcessed = true
            link.processingError = nil
            
            AppLog.info("Successfully extracted: \(String(describing: recipe.title))", category: .batch)
            
        } catch {
            // Mark as failure
            self.failureCount += 1
            self.totalProcessed += 1
            self.errorLog.append((link: link.title, error: error.localizedDescription, timestamp: Date()))
            
            link.isProcessed = true
            link.processingError = error.localizedDescription
            
            AppLog.error("Failed to extract \(link.title): \(error)", category: .batch)
        }
        
        // Save link status
        do {
            try modelContext.save()
        } catch {
            AppLog.error("Failed to save link status: \(error)", category: .batch)
        }
    }
    
    private func saveRecipe(_ recipe: RecipeX, images: [UIImage], link: SavedLink, modelContext: ModelContext) async throws {
         
         
        recipe.reference = link.url
        recipe.extractionSource = "web"
        recipe.originalFileName = nil
        
        // Initialize CloudKit sync properties
        recipe.needsCloudSync = true
        recipe.syncRetryCount = 0
        recipe.lastSyncError = nil
        recipe.cloudRecordID = nil
        recipe.lastSyncedToCloud = nil
        
        // Set timestamps
        let now = Date()
        recipe.dateAdded = now
        recipe.dateCreated = now
        recipe.lastModified = now
        
        // Set initial version
        recipe.version = 1
        
        // Get current user info for attribution (if available)
        // Note: CloudKit user info will be populated by the sync service
        // For now, just mark that this recipe was created locally
        recipe.ownerUserID = nil // Will be set by CloudKit sync service
        recipe.ownerDisplayName = nil // Will be set by CloudKit sync service
        recipe.lastModifiedDeviceID = UIDevice.current.identifierForVendor?.uuidString
        
        // Save images using setImage() method (CloudKit-synced)
        for (index, image) in images.enumerated() {
            if index == 0 {
                // First image is the main thumbnail
                recipe.setImage(image, isMainImage: true)
                AppLog.info("Set main image for '\(recipe.safeTitle)' (size: \(image.size))", category: .batch)
            } else {
                // Additional images
                recipe.setImage(image, isMainImage: false)
            }
        }
        
        // Verify images were saved
        if images.isEmpty {
            AppLog.warning("⚠️ No images saved for '\(recipe.safeTitle)'", category: .batch)
        } else {
            AppLog.info("✅ Saved \(images.count) image(s) using setImage() (CloudKit-synced)", category: .batch)
            AppLog.info("Recipe imageData is \(recipe.imageData != nil ? "set" : "nil"), imageName is '\(recipe.imageName ?? "nil")'", category: .batch)
        }
        
        // Calculate content fingerprint for duplicate detection
        recipe.updateContentFingerprint()
        
        // Insert recipe into SwiftData
        modelContext.insert(recipe)
        link.extractedRecipeID = recipe.safeID
        
        try modelContext.save()
        AppLog.info("Recipe saved: \(recipe.safeTitle) (RecipeX with CloudKit sync enabled)", category: .batch)
    }
    
    // MARK: - Deprecated Image Methods (kept for reference)
    
    @available(*, deprecated, message: "Use recipe.setImage() instead")
    private func saveImageToDisk(_ image: UIImage, filename: String) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            AppLog.error("Failed to convert image to JPEG data", category: .batch)
            return
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        
        do {
            try imageData.write(to: fileURL)
        } catch {
            AppLog.error("Failed to save image \(filename): \(error)", category: .batch)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Extract image URLs from recipe notes (DEPRECATED - no longer used)
    /// This function is kept for backward compatibility with old recipes that may have
    /// image URLs stored in notes. New extractions store URLs in the reference field instead.
    private func extractImageURLs(from recipe: RecipeX) -> [String] {
        let notes = recipe.notes
        
        // Look for the note containing image URLs
        for note in notes {
            let text = note.text
            if text.hasPrefix("Image URLs from source:") {
                // Extract URLs from the note
                let lines = text.components(separatedBy: .newlines)
                // Skip the first line ("Image URLs from source:")
                let urls = lines.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                return Array(urls)
            }
        }
        
        return []
    }
    
    /// Remove image URL notes from recipe after images have been downloaded (DEPRECATED)
    /// This function is kept for backward compatibility to clean up old recipes.
    /// New extractions no longer add image URLs to notes.
    @MainActor
    private func cleanupImageURLNotes(from recipe: RecipeX) {
        var notes = recipe.notes
        
        // Remove notes that contain image URLs
        notes.removeAll { note in
            note.text.hasPrefix("Image URLs from source:")
        }
        
        // Update the recipe with cleaned notes
        if let encodedNotes = try? JSONEncoder().encode(notes) {
            recipe.notesData = encodedNotes.isEmpty ? nil : encodedNotes
        }
    }
    
    // MARK: - Status Updates
    
    private func updateStatus(
        currentIndex: Int,
        totalCount: Int,
        currentLink: SavedLink?,
        step: ExtractionStep,
        stepProgress: Double,
        imagesDownloaded: Int = 0,
        totalImages: Int = 0
    ) async {
        let timeElapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let estimatedRemaining = calculateEstimatedTimeRemaining(
            currentIndex: currentIndex,
            totalCount: totalCount,
            timeElapsed: timeElapsed
        )
        
        await MainActor.run {
            self.currentStatus = ExtractionStatus(
                currentIndex: currentIndex,
                totalCount: totalCount,
                currentLink: currentLink,
                currentRecipe: self.currentRecipe,
                currentStep: step,
                stepProgress: stepProgress,
                imagesDownloaded: imagesDownloaded,
                totalImages: totalImages,
                timeElapsed: timeElapsed,
                estimatedTimeRemaining: estimatedRemaining
            )
        }
    }
    
    private func calculateEstimatedTimeRemaining(currentIndex: Int, totalCount: Int, timeElapsed: TimeInterval) -> TimeInterval? {
        guard currentIndex > 0 else { return nil }
        
        let averageTimePerRecipe = timeElapsed / Double(currentIndex)
        let remaining = totalCount - currentIndex
        return averageTimePerRecipe * Double(remaining)
    }
    
    private func recordExtractionTime(_ time: TimeInterval) async {
        await MainActor.run {
            self.extractionTimes.append(time)
            
            // Keep only last 10 times for rolling average
            if self.extractionTimes.count > 10 {
                self.extractionTimes.removeFirst()
            }
            
            // Calculate average
            self.averageExtractionTime = self.extractionTimes.reduce(0, +) / Double(self.extractionTimes.count)
        }
    }
    
    private func performWait(remaining: Int) async {
        guard !Task.isCancelled else { return }
        
        let intervalSteps = Int(extractionInterval * 2) // Check every 0.5 seconds
        for _ in 0..<intervalSteps {
            guard !Task.isCancelled else { break }
            
            while await isPausedCheck() && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            guard !Task.isCancelled else { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
    
    private func isPausedCheck() async -> Bool {
        await MainActor.run {
            return self.isPaused
        }
    }
}
