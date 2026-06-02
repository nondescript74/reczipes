//
//  BatchImageExtractorViewModel.swift
//  Reczipes2
//
//  Created for batch recipe extraction from Photos library
//

import SwiftUI
import SwiftData
import Photos
import Combine

/// ViewModel managing batch extraction workflow from Photos library images
@MainActor
class BatchImageExtractorViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isExtracting = false
    @Published var isPaused = false
    @Published var isWaitingForCrop = false
    
    @Published var currentProgress = 0
    @Published var totalToExtract = 0
    @Published var successCount = 0
    @Published var failureCount = 0
    
    @Published var currentImage: UIImage?
    @Published var currentRecipe: RecipeX?
    @Published var currentStatus = "Ready"
    
    @Published var remainingAssets: [PHAsset] = []
    @Published var remainingImages: [UIImage] = []   // mirrors remainingAssets but for UIImage queues
    @Published var errorLog: [(imageIndex: Int, error: String)] = []
    
    // Crop integration properties
    @Published var showingCropForBatch = false
    @Published var imageToCropInBatch: UIImage?
    
    // MARK: - Private Properties
    
    private let apiKey: String
    private let modelContext: ModelContext
    private let apiClient: ClaudeAPIClient
    private let imagePreprocessor = ImagePreprocessor()
    
    private var allAssets: [PHAsset] = []
    private var processedAssets: Set<String> = []
    private var shouldCrop = false
    private var currentBatch: [UIImage] = []
    private var extractionTask: Task<Void, Never>?
    
    private var cropContinuation: CheckedContinuation<Bool, Never>?
    private var cropImageContinuation: CheckedContinuation<UIImage?, Never>?
    
    // Background extraction support
    private let batchManager = BatchExtractionManager.shared
    private let backgroundManager = BackgroundProcessingManager.shared
    private var isUsingBackgroundExtraction = false
    
    // MARK: - Computed Properties
    
    var remainingCount: Int {
        remainingAssets.count + remainingImages.count
    }
    
    // MARK: - Initialization
    
    init(apiKey: String, modelContext: ModelContext) {
        self.apiKey = apiKey
        self.modelContext = modelContext
        self.apiClient = ClaudeAPIClient(apiKey: apiKey)
        
        // Configure background extraction managers
        batchManager.configure(apiKey: apiKey, modelContext: modelContext)
        backgroundManager.configure(apiKey: apiKey, modelContext: modelContext)
    }
    
    // MARK: - Public Methods
    
    func startBatchExtraction(
        assets: [PHAsset],
        photoManager: PhotoLibraryManager,
        shouldCrop: Bool
    ) {
        guard !assets.isEmpty else { return }
        
        AppLog.info("Starting batch image extraction with \(assets.count) images, shouldCrop: \(shouldCrop)", category: .batch)
        
        self.allAssets = assets
        self.remainingAssets = assets
        self.shouldCrop = shouldCrop
        self.totalToExtract = assets.count
        self.currentProgress = 0
        self.successCount = 0
        self.failureCount = 0
        self.errorLog = []
        self.processedAssets = []
        self.isExtracting = true
        self.isPaused = false
        
        // If cropping is disabled, use background extraction
        if !shouldCrop {
            isUsingBackgroundExtraction = true
            startBackgroundExtractionFromAssets(assets: assets, photoManager: photoManager)
        } else {
            isUsingBackgroundExtraction = false
            // Start extraction task with cropping (must stay in foreground)
            extractionTask = Task {
                await processBatch(photoManager: photoManager)
            }
        }
    }
    
    func startBatchExtractionFromImages(
        images: [UIImage],
        shouldCrop: Bool
    ) {
        guard !images.isEmpty else { return }
        
        AppLog.info("Starting batch image extraction from \(images.count) UIImages (Files/iCloud Drive), shouldCrop: \(shouldCrop)", category: .batch)
        
        self.currentBatch = images
        self.shouldCrop = shouldCrop
        self.totalToExtract = images.count
        self.currentProgress = 0
        self.successCount = 0
        self.failureCount = 0
        self.errorLog = []
        self.isExtracting = true
        self.isPaused = false
        
        // Clear asset-related state
        self.allAssets = []
        self.remainingAssets = []
        self.remainingImages = images   // seed the remaining queue for the view
        self.processedAssets = []
        
        // If cropping is disabled, use background extraction
        if !shouldCrop {
            isUsingBackgroundExtraction = true
            startBackgroundExtractionFromImages(images: images)
        } else {
            isUsingBackgroundExtraction = false
            // Start extraction task with cropping (must stay in foreground)
            extractionTask = Task {
                await processImageBatch()
            }
        }
    }
    
    func pause() {
        isPaused = true
        currentStatus = "Paused"
        AppLog.info("Batch extraction paused", category: .batch)
    }
    
    func resume() {
        isPaused = false
        currentStatus = "Resuming..."
        AppLog.info("Batch extraction resumed", category: .batch)
    }
    
    func stop() {
        extractionTask?.cancel()
        isExtracting = false
        isPaused = false
        isWaitingForCrop = false
        currentStatus = "Stopped"
        AppLog.info("Batch extraction stopped", category: .batch)
    }
    
    func skipCropping() {
        cropContinuation?.resume(returning: false)
        cropContinuation = nil
        isWaitingForCrop = false
    }
    
    func showCropping() {
        cropContinuation?.resume(returning: true)
        cropContinuation = nil
        isWaitingForCrop = false
    }
    
    func handleCroppedImage(_ image: UIImage?) {
        cropImageContinuation?.resume(returning: image)
        cropImageContinuation = nil
        imageToCropInBatch = nil
        showingCropForBatch = false
    }
    
    func reset() {
        currentImage = nil
        currentRecipe = nil
        currentProgress = 0
        totalToExtract = 0
        successCount = 0
        failureCount = 0
        remainingAssets = []
        remainingImages = []
        allAssets = []
        processedAssets = []
        errorLog = []
        currentStatus = "Ready"
        isExtracting = false
        isPaused = false
        isWaitingForCrop = false
    }
    
    // MARK: - Private Methods
    
    private func requestCrop(for image: UIImage) async -> UIImage? {
        await withCheckedContinuation { continuation in
            self.cropImageContinuation = continuation
            self.imageToCropInBatch = image
            self.showingCropForBatch = true
        }
    }
    
    private func processBatch(photoManager: PhotoLibraryManager) async {
        AppLog.info("Processing batch of \(allAssets.count) images", category: .batch)
        
        for (index, asset) in allAssets.enumerated() {
            // Check if stopped
            guard isExtracting else {
                AppLog.info("Extraction stopped", category: .batch)
                break
            }
            
            // Wait while paused
            while isPaused && isExtracting {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            // Skip if already processed
            if processedAssets.contains(asset.localIdentifier) {
                continue
            }
            
            currentStatus = "Processing image \(index + 1) of \(totalToExtract)..."
            AppLog.info("Processing image \(index + 1) of \(totalToExtract)", category: .batch)
            
            // Load full resolution image
            guard let image = await photoManager.loadImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize
            ) else {
                AppLog.error("Failed to load image \(index + 1)", category: .batch)
                errorLog.append((imageIndex: index, error: "Failed to load image from Photos library"))
                failureCount += 1
                currentProgress += 1
                remainingAssets.removeFirst()
                continue
            }
            
            currentImage = image
            
            // Handle cropping if enabled
            var imageToProcess = image
            if shouldCrop {
                let shouldCropThisImage = await askToCrop()
                
                if shouldCropThisImage {
                    if let croppedImage = await requestCrop(for: image) {
                        imageToProcess = croppedImage
                        AppLog.info("Image cropped successfully for batch extraction", category: .batch)
                    } else {
                        AppLog.info("Crop cancelled, using original image", category: .batch)
                    }
                }
            }
            
            // Extract recipe from image
            await extractRecipeFromImage(imageToProcess, imageIndex: index)
            
            // Mark as processed and update queue
            processedAssets.insert(asset.localIdentifier)
            currentProgress += 1
            if !remainingAssets.isEmpty {
                remainingAssets.removeFirst()
            }
            
            // Process in batches of 10
            if currentProgress % 10 == 0 && currentProgress < totalToExtract {
                currentStatus = "Completed \(currentProgress) images. Continuing with next batch..."
                AppLog.info("Completed batch of 10, continuing...", category: .batch)
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second pause
            }
        }
        
        // Extraction complete
        currentStatus = "Complete! Extracted \(successCount) recipes."
        isExtracting = false
        AppLog.info("Batch extraction complete: \(successCount) success, \(failureCount) failures", category: .batch)
    }
    
    private func askToCrop() async -> Bool {
        await withCheckedContinuation { continuation in
            self.cropContinuation = continuation
            self.isWaitingForCrop = true
        }
    }
    
    private func extractRecipeFromImage(_ image: UIImage, imageIndex: Int) async {
        do {
            currentStatus = "Extracting recipe from image \(imageIndex + 1)..."
            
            // Reduce image size to 10-20KB before sending (text extraction only)
            guard let imageData = imagePreprocessor.reduceImageSize(image, maxSizeBytes: 20_000) else {
                throw NSError(
                    domain: "BatchExtraction",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to process image"]
                )
            }
            
            AppLog.info("Calling API for image \(imageIndex + 1), size: \(imageData.count) bytes (~\(imageData.count / 1024)KB)", category: .batch)
            
            // Extract recipe using Claude API
            let recipe = try await apiClient.extractRecipe(
                from: imageData,
                usePreprocessing: true
            )
            
            currentRecipe = recipe
            
            // Save recipe to SwiftData
            await saveRecipe(recipe, withImage: image)
            
            successCount += 1
            AppLog.info("Successfully extracted recipe: \(String(describing: recipe.title))", category: .batch)
            
        } catch let error as ClaudeAPIError {
            AppLog.error("API error for image \(imageIndex + 1): \(error.errorDescription ?? "unknown")", category: .batch)
            errorLog.append((imageIndex: imageIndex, error: error.errorDescription ?? "API error"))
            failureCount += 1
            currentRecipe = nil
            
        } catch {
            AppLog.error("Unexpected error for image \(imageIndex + 1): \(error.localizedDescription)", category: .batch)
            errorLog.append((imageIndex: imageIndex, error: error.localizedDescription))
            failureCount += 1
            currentRecipe = nil
        }
    }
    
    private func processImageBatch() async {
        AppLog.info("Processing batch of \(currentBatch.count) UIImages from Files/iCloud Drive", category: .batch)
        
        for (index, image) in currentBatch.enumerated() {
            // Check if stopped
            guard isExtracting else {
                AppLog.info("Extraction stopped", category: .batch)
                break
            }
            
            // Wait while paused
            while isPaused && isExtracting {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            currentStatus = "Processing image \(index + 1) of \(totalToExtract)..."
            AppLog.info("Processing UIImage \(index + 1) of \(totalToExtract)", category: .batch)
            
            currentImage = image
            
            // Handle cropping if enabled
            var imageToProcess = image
            if shouldCrop {
                let shouldCropThisImage = await askToCrop()
                
                if shouldCropThisImage {
                    if let croppedImage = await requestCrop(for: image) {
                        imageToProcess = croppedImage
                        AppLog.info("Image cropped successfully for batch extraction", category: .batch)
                    } else {
                        AppLog.info("Crop cancelled, using original image", category: .batch)
                    }
                }
            }
            
            // Extract recipe from image
            await extractRecipeFromImage(imageToProcess, imageIndex: index)
            
            currentProgress += 1
            if !remainingImages.isEmpty {
                remainingImages.removeFirst()
            }
            
            // Process in batches of 10
            if currentProgress % 10 == 0 && currentProgress < totalToExtract {
                currentStatus = "Completed \(currentProgress) images. Continuing with next batch..."
                AppLog.info("Completed batch of 10, continuing...", category: .batch)
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second pause
            }
        }
        
        // Extraction complete
        currentStatus = "Complete! Extracted \(successCount) recipes."
        isExtracting = false
        currentBatch = []
        AppLog.info("Batch extraction from UIImages complete: \(successCount) success, \(failureCount) failures", category: .batch)
    }
    
    private func saveRecipe(_ recipeX: RecipeX, withImage image: UIImage) async {
        AppLog.info("Saving recipe: \(String(describing: recipeX.title))", category: .batch)
//
//        // Convert to SwiftData RecipeX (NEW unified model)
//        let recipeX = RecipeX(from: recipeModel)
        
        // Set owner info (get from CloudKit if available)
        if let userID = CloudKitSharingService.shared.currentUserID {
            recipeX.ownerUserID = userID
        }
        if let displayName = CloudKitSharingService.shared.currentUserName {
            recipeX.ownerDisplayName = displayName
        }
        
        // Set extraction source
        recipeX.extractionSource = "batch"
        
        // Set device identifier
        recipeX.lastModifiedDeviceID = UIDevice.current.identifierForVendor?.uuidString
        
        // Save image directly to SwiftData (CloudKit-synced)
        recipeX.setImage(image, isMainImage: true)
        
        // Generate content fingerprint for duplicate detection
        recipeX.updateContentFingerprint()
        
        // Mark for CloudKit sync (automatic sharing)
        recipeX.needsCloudSync = true
        
        // Insert into SwiftData
        modelContext.insert(recipeX)
        
        // Save context
        do {
            try modelContext.save()
            AppLog.info("✅ Recipe saved to database as RecipeX (CloudKit-synced, auto-sharing enabled)", category: .batch)
        } catch {
            AppLog.error("Failed to save recipe to database: \(error)", category: .batch)
        }
    }
    
    // MARK: - Background Extraction Methods
    
    private func startBackgroundExtractionFromImages(images: [UIImage]) {
        AppLog.info("Starting background extraction from \(images.count) images", category: .batch)
        
        // Start a task to process images and feed them to the background manager
        extractionTask = Task {
            var processedImages: [(image: UIImage, index: Int)] = []
            
            for (index, image) in images.enumerated() {
                processedImages.append((image: image, index: index))
            }
            
            // Hand off to background manager
            await startBackgroundExtractionWithProcessedImages(processedImages)
        }
    }
    
    private func startBackgroundExtractionFromAssets(assets: [PHAsset], photoManager: PhotoLibraryManager) {
        AppLog.info("Starting background extraction from \(assets.count) assets", category: .batch)
        
        // Start a task to load images from assets and feed them to the background manager
        extractionTask = Task {
            var processedImages: [(image: UIImage, index: Int)] = []
            
            for (index, asset) in assets.enumerated() {
                if let image = await photoManager.loadImage(for: asset, targetSize: PHImageManagerMaximumSize) {
                    processedImages.append((image: image, index: index))
                } else {
                    AppLog.error("Failed to load image from asset at index \(index)", category: .batch)
                }
            }
            
            // Hand off to background manager
            await startBackgroundExtractionWithProcessedImages(processedImages)
        }
    }
    
    private func startBackgroundExtractionWithProcessedImages(_ processedImages: [(image: UIImage, index: Int)]) async {
        AppLog.info("Handing off \(processedImages.count) images to background extraction", category: .batch)
        
        // Start background task to allow continuation when app is backgrounded
        // This MUST be called on main thread since it's a UI operation
        await MainActor.run {
            backgroundManager.beginBackgroundTask(name: "Batch Recipe Extraction")
        }
        
        // Convert images to Data and queue them for background processing
        var imageDataQueue: [(data: Data, index: Int)] = []
        for (image, index) in processedImages {
            if let imageData = imagePreprocessor.reduceImageSize(image, maxSizeBytes: 20_000) {
                imageDataQueue.append((data: imageData, index: index))
            }
        }
        
        // Queue for background processing (in case app is terminated)
        backgroundManager.queueExtractions(images: imageDataQueue)
        
        // Process images in foreground/background hybrid mode
        for (image, index) in processedImages {
            // Check if stopped
            guard isExtracting else {
                AppLog.info("Background extraction stopped", category: .batch)
                await MainActor.run {
                    backgroundManager.endBackgroundTask()
                }
                break
            }
            
            // Wait while paused
            while isPaused && isExtracting {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
            
            guard isExtracting else { 
                await MainActor.run {
                    backgroundManager.endBackgroundTask()
                }
                break 
            }
            
            currentStatus = "Processing image \(index + 1) of \(totalToExtract)..."
            currentImage = image
            
            // Extract recipe from image
            await extractRecipeFromImage(image, imageIndex: index)
            
            currentProgress += 1
            // Advance whichever remaining queue is active
            if !remainingAssets.isEmpty {
                remainingAssets.removeFirst()
            } else if !remainingImages.isEmpty {
                remainingImages.removeFirst()
            }
            
            // Log progress
            if currentProgress % 5 == 0 || currentProgress == totalToExtract {
                AppLog.info("Background extraction progress: \(currentProgress)/\(totalToExtract)", category: .batch)
            }
        }
        
        // Extraction complete
        currentStatus = "Complete! Extracted \(successCount) recipes."
        isExtracting = false
        currentBatch = []
        
        // End background task on main thread
        await MainActor.run {
            backgroundManager.endBackgroundTask()
        }
        backgroundManager.clearQueue()
        
        AppLog.info("Background extraction complete: \(successCount) success, \(failureCount) failures", category: .batch)
    }
    
    /// Returns whether background extraction is currently active
    var canDismissView: Bool {
        // Can always dismiss if using background extraction
        // Otherwise, only if not extracting or not waiting for crop
        return isUsingBackgroundExtraction || !isExtracting || !isWaitingForCrop
    }
    
    /// Prepares for view dismissal during background extraction
    func prepareForBackgroundDismissal() {
        if isUsingBackgroundExtraction && isExtracting {
            AppLog.info("View dismissing, extraction will continue in background", category: .batch)
            // Extraction will continue in the background
        }
    }
}

