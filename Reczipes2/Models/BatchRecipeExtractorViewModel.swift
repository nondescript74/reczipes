//
//  BatchRecipeExtractorViewModel.swift
//  Reczipes2
//
//  Created for automated batch recipe extraction from saved links
//

import SwiftUI
import SwiftData
import Combine

/// View model for managing automated batch extraction of recipes from saved links
@MainActor
class BatchRecipeExtractorViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isExtracting = false
    @Published var isPaused = false
    @Published var currentLink: SavedLink?
    @Published var currentRecipe: RecipeX?
    @Published var currentProgress: Int = 0
    @Published var totalToExtract: Int = 0
    @Published var successCount: Int = 0
    @Published var failureCount: Int = 0
    @Published var currentStatus: String = ""
    @Published var errorLog: [(link: String, error: String)] = []
    
    // MARK: - Private Properties
    
    private let apiKey: String
    private let modelContext: ModelContext
    private let extractionInterval: TimeInterval = 5.0 // 5 seconds between extractions
    private let maxBatchSize: Int = 50 // Maximum recipes per batch
    private var extractionTask: Task<Void, Never>?
    private let webImageDownloader = WebImageDownloader()
    private let retryManager = ExtractionRetryManager()
    
    // Retry configuration - can be adjusted per user preference
    private let retryConfiguration = ExtractionRetryManager.RetryConfiguration.default
    
    // MARK: - Initialization
    
    init(apiKey: String, modelContext: ModelContext) {
        self.apiKey = apiKey
        self.modelContext = modelContext
    }
    
    // MARK: - Public Methods
    
    /// Start batch extraction of all unprocessed links
    func startBatchExtraction(links: [SavedLink]) {
        guard !isExtracting else { return }
        
        let unprocessedLinks = links.filter { !$0.isProcessed }
        guard !unprocessedLinks.isEmpty else {
            AppLog.info("No unprocessed links to extract", category: .batch)
            return
        }
        
        // Limit to maxBatchSize recipes
        let linksToProcess = Array(unprocessedLinks.prefix(maxBatchSize))
        let remainingCount = unprocessedLinks.count - linksToProcess.count
        
        isExtracting = true
        isPaused = false
        currentProgress = 0
        totalToExtract = linksToProcess.count
        successCount = 0
        failureCount = 0
        errorLog = []
        
        if remainingCount > 0 {
            currentStatus = "Starting batch extraction (limited to \(maxBatchSize) recipes, \(remainingCount) will remain)..."
            AppLog.info("Starting batch extraction of \(totalToExtract) links (limited from \(unprocessedLinks.count))", category: .batch)
        } else {
            currentStatus = "Starting batch extraction..."
            AppLog.info("Starting batch extraction of \(totalToExtract) links", category: .batch)
        }
        
        extractionTask = Task {
            await extractLinks(linksToProcess)
        }
    }
    
    /// Pause the batch extraction
    func pause() {
        isPaused = true
        currentStatus = "Paused"
        AppLog.info("Batch extraction paused", category: .batch)
    }
    
    /// Resume the batch extraction
    func resume() {
        isPaused = false
        currentStatus = "Resuming..."
        AppLog.info("Batch extraction resumed", category: .batch)
    }
    
    /// Stop the batch extraction
    func stop() {
        extractionTask?.cancel()
        extractionTask = nil
        isExtracting = false
        isPaused = false
        currentLink = nil
        currentRecipe = nil
        currentStatus = "Stopped"
        AppLog.info("Batch extraction stopped", category: .batch)
    }
    
    /// Reset all counters and state
    func reset() {
        currentProgress = 0
        totalToExtract = 0
        successCount = 0
        failureCount = 0
        currentStatus = ""
        errorLog = []
        currentLink = nil
        currentRecipe = nil
    }
    
    // MARK: - Private Methods
    
    /// Extract recipes from a list of links with interval between each
    private func extractLinks(_ links: [SavedLink]) async {
        for (index, link) in links.enumerated() {
            // Check if task was cancelled
            guard !Task.isCancelled else {
                currentStatus = "Cancelled"
                AppLog.info("Batch extraction cancelled", category: .batch)
                break
            }
            
            // Wait while paused
            while isPaused && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            guard !Task.isCancelled else { break }
            
            currentLink = link
            currentProgress = index + 1
            currentStatus = "Extracting \(index + 1) of \(totalToExtract): \(link.title)"
            
            AppLog.info("Extracting link \(index + 1)/\(totalToExtract): \(link.title)", category: .batch)
            
            // Extract the recipe
            await extractSingleLink(link)
            
            // Wait for the interval before next extraction (except for last one)
            if index < links.count - 1 && !Task.isCancelled {
                currentStatus = "Waiting \(Int(extractionInterval)) seconds before next extraction..."
                AppLog.info("Waiting \(extractionInterval) seconds before next extraction", category: .batch)
                
                // Use a loop to check for pause/cancel during wait
                let intervalSteps = Int(extractionInterval * 2) // Check every 0.5 seconds
                for step in 0..<intervalSteps {
                    guard !Task.isCancelled else { break }
                    
                    while isPaused && !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                    
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    // Update countdown status
                    let remaining = Int(extractionInterval) - (step / 2)
                    if remaining > 0 {
                        currentStatus = "Waiting \(remaining) seconds before next extraction..."
                    }
                }
            }
        }
        
        // Extraction complete
        if !Task.isCancelled {
            isExtracting = false
            currentStatus = "Complete! ✓ \(successCount) succeeded, ✗ \(failureCount) failed"
            AppLog.info("Batch extraction complete: \(successCount) succeeded, \(failureCount) failed", category: .batch)
        }
    }
    
    /// Extract a single recipe from a link with automatic retry on failure
    private func extractSingleLink(_ link: SavedLink) async {
        // Extract values needed to avoid capturing non-Sendable link
        let linkID = link.id
        let linkURL = link.url
        let linkTitle = link.title
        
        // Manual retry logic since we can't use retryManager with non-Sendable return types
        var attempt = 0
        let maxAttempts = retryConfiguration.maxAttempts
        
        while attempt < maxAttempts {
            attempt += 1
            
            do {
                // Perform the extraction
                let (recipe, downloadedImages) = try await performExtractionWithValues(
                    linkID: linkID,
                    url: linkURL,
                    title: linkTitle
                )
                
                // Save recipe to database
                currentStatus = "Saving recipe..."
                try await saveRecipe(recipe, images: downloadedImages, link: link)
                
                // Mark as success
                successCount += 1
                link.isProcessed = true
                link.processingError = nil
                
                if attempt > 1 {
                    AppLog.info("Successfully extracted '\(String(describing: recipe.title))' after \(attempt) attempts", category: .batch)
                } else {
                    AppLog.info("Successfully extracted and saved: \(String(describing: recipe.title))", category: .batch)
                }
                
                // Success - break out of retry loop
                break
                
            } catch {
                // Check if we should retry
                if attempt < maxAttempts {
                    let delay = calculateRetryDelay(attempt: attempt)
                    AppLog.warning("Extraction attempt \(attempt) failed for '\(linkTitle)', retrying in \(delay)s: \(error)", category: .batch)
                    currentStatus = "Attempt \(attempt) failed, retrying in \(Int(delay))s..."
                    
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    // All retries exhausted
                    failureCount += 1
                    link.isProcessed = true
                    link.processingError = error.localizedDescription
                    errorLog.append((link: link.title, error: error.localizedDescription))
                    
                    AppLog.error("Failed to extract '\(link.title)' after \(attempt) attempt(s): \(error)", category: .batch)
                }
            }
        }
        
        // Save link status
        do {
            try modelContext.save()
        } catch {
            AppLog.error("Failed to save link status: \(error)", category: .batch)
        }
    }
    
    /// Calculate retry delay using exponential backoff
    private func calculateRetryDelay(attempt: Int) -> TimeInterval {
        let baseDelay = retryConfiguration.initialDelay
        let multiplier = retryConfiguration.backoffMultiplier
        let maxDelay = retryConfiguration.maxDelay
        
        var delay = baseDelay * pow(multiplier, Double(attempt - 1))
        delay = min(delay, maxDelay)
        
        // Add jitter if configured
        if retryConfiguration.useJitter {
            let jitter = Double.random(in: 0...0.3) * delay
            delay += jitter
        }
        
        return delay
    }
    
    /// Perform the actual extraction
    /// - Parameters:
    ///   - linkID: The UUID of the saved link
    ///   - url: The URL to extract from
    ///   - title: The title of the link (for logging)
    /// - Returns: Tuple of (recipe, downloaded images)
    /// - Throws: Any error during extraction
    private func performExtractionWithValues(linkID: UUID, url: String, title: String) async throws -> (RecipeX, [PlatformImage]) {
        // Create extractor for this link
        let extractor = RecipeExtractorViewModel(apiKey: apiKey)
        
        // Extract recipe
        await extractor.extractRecipe(from: url)
        
        // Check if extraction was successful
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
        
        // Store the current recipe for display
        currentRecipe = recipe
        
        // Get image URLs from extractor (new method - more reliable than notes)
        let imageURLs = extractor.extractedImageURLs
        AppLog.info("Found \(imageURLs.count) image URL(s) from extractor for '\(title)'", category: .batch)
        if !imageURLs.isEmpty {
            AppLog.info("First 3 image URLs: \(Array(imageURLs.prefix(3)))", category: .batch)
        }
        
        // Download images if available
        var downloadedImages: [PlatformImage] = []
        if !imageURLs.isEmpty {
            currentStatus = "Downloading \(imageURLs.count) image(s)..."
            AppLog.info("Downloading \(imageURLs.count) images for: \(String(describing: recipe.title))", category: .batch)
            
            for (_ , imageURL) in imageURLs.enumerated() {
                // Try to download each image with basic retry
                var imageAttempt = 0
                let maxImageAttempts = 2
                
                while imageAttempt < maxImageAttempts {
                    imageAttempt += 1
                    
                    do {
                        let image = try await webImageDownloader.downloadImage(from: imageURL)
                        downloadedImages.append(image)
                        break // Success
                    } catch {
                        if imageAttempt < maxImageAttempts {
                            AppLog.warning("Image download attempt \(imageAttempt) failed, retrying: \(error)", category: .batch)
                            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        } else {
                            AppLog.warning("Failed to download image after \(imageAttempt) attempts: \(error)", category: .batch)
                            // Continue with other images - don't fail the whole extraction
                        }
                    }
                }
            }
        }
        
        return (recipe, downloadedImages)
    }
    
    /// Save a recipe with its images to the database
    private func saveRecipe(_ recipe: RecipeX, images: [PlatformImage], link: SavedLink) async throws {
        
        // Set reference to the original link URL
        recipe.reference = link.url
        recipe.extractionSource = "web"
        
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
        
        // Save images using setImage() method (CloudKit-synced)
        for (index, image) in images.enumerated() {
            if index == 0 {
                recipe.setImage(image, isMainImage: true)
            } else {
                recipe.setImage(image, isMainImage: false)
            }
        }
        
        AppLog.info("✅ Saved \(images.count) image(s) using setImage() (CloudKit-synced)", category: .batch)
        
        // Insert into SwiftData context
        modelContext.insert(recipe)
        
        // Update the link to mark it as processed
        link.extractedRecipeID = recipe.id
        
        // Save the context
        do {
            try modelContext.save()
            AppLog.info("Recipe saved successfully: \(String(describing: recipe.title)) with \(images.count) image(s) in SwiftData", category: .batch)
        } catch {
            AppLog.error("Failed to save recipe to database: \(error)", category: .batch)
            throw error
        }
    }
    
    /// Extract image URLs from recipe notes (DEPRECATED - no longer used)
    /// This function is kept for backward compatibility with old recipes.
    /// New extractions store URLs in the reference field instead.
    private func extractImageURLsFromNotes(_ recipe: RecipeX) -> [String] {
        let notes = recipe.notes
        
        for note in notes {
            if note.text.hasPrefix("Image URLs from source:") {
                // Extract URLs from the note text
                let lines = note.text.components(separatedBy: .newlines)
                // Skip the first line which is "Image URLs from source:"
                let urls = lines.dropFirst().compactMap { line -> String? in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    // Validate it looks like a URL
                    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                        return trimmed
                    }
                    return nil
                }
                return urls
            }
        }
        
        return []
    }
}
