//
//  RecipeExtractorViewModel.swift
//  Reczipes2
//
//  Created for Claude-powered recipe extraction
//

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif
import Combine

@MainActor
class RecipeExtractorViewModel: ObservableObject {
    @Published var extractedRecipe: RecipeX?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedImage: UIImage?
    @Published var processedImage: UIImage?
    @Published var usePreprocessing = true
    @Published var recipeURL: String = ""
    @Published var extractedImageURLs: [String] = [] // Image URLs from web extraction
    
    private let apiClient: ClaudeAPIClient
    private let imagePreprocessor = ImagePreprocessor()
    private let webExtractor = WebRecipeExtractor()
    
    @Published var showingDuplicateResolution = false
    @Published var duplicateMatch: DuplicateMatch?
    
    private var duplicateDetectionService: DuplicateDetectionService?
    private let imageHashService = ImageHashService()
    
    // MARK: - Recipe Enhancement
    
    @Published var showingValidation = false
    @Published var validationResult: RecipeValidationResult?
    @Published var isValidating = false
    @Published var isRecipeSaved = false  // Track if recipe has been auto-saved
    @Published var savedRecipeID: UUID?   // Reference to saved recipe
    
    private var enhancementService: RecipeEnhancementService?
    
    func saveRecipe(modelContext: ModelContext) {
        guard let recipe = extractedRecipe else { return }
        
        // Check for duplicates
        Task {
            let service = DuplicateDetectionService(modelContext: modelContext)
            let duplicates = await service.findSimilarByContent(recipe, threshold: 0.8)
            
            if let firstMatch = duplicates.first {
                // Show duplicate resolution
                duplicateMatch = firstMatch
                showingDuplicateResolution = true
            } else {
                // No duplicates, save normally
                saveRecipeDirectly(recipe, modelContext: modelContext)
            }
        }
    }
    
    private func saveRecipeDirectly(_ recipe: RecipeX, modelContext: ModelContext) {
         
        // Use image URLs from the extractedImageURLs property (set during web extraction)
        // These were never added to notes, so no cleanup is needed
        let imageURLs = self.extractedImageURLs
        
        // Append image URLs to the reference field as clickable links
        if !imageURLs.isEmpty {
            var referenceText = recipe.reference ?? ""
            
            // Add a separator if there's already content in reference
            if !referenceText.isEmpty {
                referenceText += "\n\n"
            }
            
            // Add image URLs section
            referenceText += "Source Images:\n"
            for url in imageURLs {
                referenceText += url + "\n"
            }
            
            recipe.reference = referenceText.trimmingCharacters(in: .whitespacesAndNewlines)
            AppLog.info("Added \(imageURLs.count) image URL(s) to reference field", category: .extraction)
        }
        
        // Set extraction source
        recipe.extractionSource = "camera" // or "photos" or "files"
        
        // Generate and store image hash
        if let image = selectedImage,
           let hash = imageHashService.generateHash(for: image) {
            recipe.imageHash = hash
            
            // Also save the image data directly in RecipeX
            recipe.setImage(image, isMainImage: true)
        }
        
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
        
        // Set device identifier for attribution
        recipe.lastModifiedDeviceID = UIDevice.current.identifierForVendor?.uuidString
        
        // Calculate content fingerprint for duplicate detection
        recipe.updateContentFingerprint()
        
        modelContext.insert(recipe)
        
        do {
            try modelContext.save()
            AppLog.info("Recipe saved successfully: \(recipe.safeTitle) (RecipeX with CloudKit sync)", category: .extraction)
        } catch {
            AppLog.error("Failed to save recipe: \(error)", category: .extraction)
            errorMessage = "Failed to save recipe: \(error.localizedDescription)"
        }
    }
    
    
    func handleReplaceOriginal(modelContext: ModelContext) {
        guard let newRecipe = extractedRecipe,
              let match = duplicateMatch else { return }
        
        let existingRecipe = match.existingRecipe
        let encoder = JSONEncoder()
        
        // Update existing RecipeX with new data
        existingRecipe.title = newRecipe.title
        existingRecipe.headerNotes = newRecipe.headerNotes
        existingRecipe.recipeYield = newRecipe.yield
        existingRecipe.reference = newRecipe.reference
        
        // Encode and update ingredient sections
        if let ingredientsData = try? encoder.encode(newRecipe.ingredientSections) {
            existingRecipe.updateIngredients(ingredientsData)
        }
        
        // Encode and update instruction sections
        if let instructionsData = try? encoder.encode(newRecipe.instructionSections) {
            existingRecipe.updateInstructions(instructionsData)
        }
        
        // Encode and update notes
        if let notesData = try? encoder.encode(newRecipe.notes) {
            existingRecipe.notesData = notesData
        }
        
        // Update the image if available
        if let image = selectedImage {
            existingRecipe.setImage(image, isMainImage: true)
        }
        
        // Mark as modified (this updates version, timestamp, and triggers CloudKit sync)
        existingRecipe.markAsModified()
        
        // Update content fingerprint
        existingRecipe.updateContentFingerprint()
        
        do {
            try modelContext.save()
            AppLog.info("Recipe replaced successfully: \(existingRecipe.safeTitle)", category: .extraction)
        } catch {
            AppLog.error("Failed to replace recipe: \(error)", category: .extraction)
            errorMessage = "Failed to replace recipe: \(error.localizedDescription)"
        }
    }
    
    func handleKeepOriginal() {
        // Just dismiss, don't save
        extractedRecipe = nil
    }
    
    init(apiKey: String) {
        self.apiClient = ClaudeAPIClient(apiKey: apiKey)
        self.enhancementService = RecipeEnhancementService(apiKey: apiKey)
    }
    
    /// Extract recipe from a web URL
    func extractRecipe(from url: String) async {
        // Explicitly set loading state on main actor
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            extractedRecipe = nil
            selectedImage = nil // Clear image when extracting from URL
            processedImage = nil
            extractedImageURLs = [] // Clear previous image URLs
        }
        
        AppLog.info("Starting URL extraction from: \(url)", category: .extraction)

        do {
            // Fetch web content
            let htmlContent = try await webExtractor.fetchWebContent(from: url)
            
            // Extract image URLs BEFORE cleaning (to preserve all HTML)
            let imageURLs = webExtractor.extractImageURLs(from: htmlContent)
            AppLog.info("Found \(imageURLs.count) image URL(s) in webpage", category: .extraction)
            
            // Clean the HTML
            let cleanedContent = webExtractor.cleanHTML(htmlContent)
            
            // Limit content size to avoid token limits (approximately 100k characters)
            let contentToSend: String
            if cleanedContent.count > 50_000 {
                AppLog.warning("Content too large (\(cleanedContent.count) chars), truncating to head+tail 50k characters", category: .extraction)
                let headCount = 40_000
                let tailCount = 10_000
                let head = String(cleanedContent.prefix(headCount))
                let tail = String(cleanedContent.suffix(tailCount))
                contentToSend = head + "\n\n=== TRUNCATED TAIL CONTENT ===\n\n" + tail
            } else {
                contentToSend = cleanedContent
            }
            
            AppLog.info("Calling Claude API for URL extraction...", category: .extraction)
            
            // Extract recipe using Claude
            let recipe = try await apiClient.extractRecipe(from: contentToSend)
            
            // Add the source URL to the reference field if not already present
            if let existingReference = recipe.reference, !existingReference.isEmpty {
                if !existingReference.contains(url) {
                    recipe.reference = existingReference + "\n\nOriginal Source: " + url
                }
            } else {
                recipe.reference = "Original Source: " + url
            }
            
            await MainActor.run {
                self.extractedRecipe = recipe
                self.extractedImageURLs = imageURLs // Store image URLs separately for view access
                AppLog.info("URL extraction successful: \(String(describing: recipe.title))", category: .extraction)
                AppLog.info("Extracted \(imageURLs.count) image URL(s) - will be added to reference on save", category: .extraction)
            }
        } catch let error as WebExtractionError {
            await MainActor.run {
                self.errorMessage = error.errorDescription
                AppLog.error("Web extraction error: \(error.errorDescription ?? "unknown")", category: .extraction)
            }
        } catch let error as ClaudeAPIError {
            await MainActor.run {
                self.errorMessage = error.errorDescription
                AppLog.error("Claude API error during URL extraction: \(error.errorDescription ?? "unknown")", category: .extraction)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Unexpected error: \(error.localizedDescription)"
                AppLog.error("Unexpected error during URL extraction: \(error.localizedDescription)", category: .extraction)
            }
        }
        
        await MainActor.run {
            isLoading = false
            AppLog.info("URL extraction complete, isLoading set to false", category: .extraction)
        }
    }
    
    /// Extract recipe from the selected image
    func extractRecipe(from image: UIImage) async {
        // Explicitly set loading state on main actor
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            extractedRecipe = nil // Clear any previous recipe
            selectedImage = image
        }
        
        AppLog.info("Starting image extraction, isLoading set to true", category: .extraction)
        
        // Generate processed preview if preprocessing is enabled
        if usePreprocessing {
            if let processedData = imagePreprocessor.preprocessForOCR(image),
               let processedUIImage = UIImage(data: processedData) {
                await MainActor.run {
                    processedImage = processedUIImage
                }
            }
        } else {
            await MainActor.run {
                processedImage = nil
            }
        }
        
        do {
            // Reduce image size to 10-20KB max before sending to Claude
            // Since we're only extracting text, we don't need high resolution
            AppLog.info("Reducing image size before sending to Claude...", category: .extraction)
            guard let imageData = imagePreprocessor.reduceImageSize(image, maxSizeBytes: 20_000) else {
                throw ClaudeAPIError.invalidResponse
            }
            AppLog.info("Image size after reduction: \(imageData.count) bytes (~\(imageData.count / 1024)KB)", category: .extraction)

            AppLog.info("Calling Claude API for image extraction...", category: .extraction)
            let recipe = try await apiClient.extractRecipe(
                from: imageData,
                usePreprocessing: usePreprocessing
            )

            await MainActor.run {
                self.extractedRecipe = recipe
                AppLog.info("Recipe extraction successful", category: .extraction)
            }
        } catch let error as ClaudeAPIError {
            await MainActor.run {
                self.errorMessage = error.errorDescription
                AppLog.error("Claude API error during extraction: \(error.errorDescription ?? "unknown")", category: .extraction)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Unexpected error: \(error.localizedDescription)"
                AppLog.error("Unexpected error during extraction: \(error.localizedDescription)", category: .extraction)
            }
        }
        
        await MainActor.run {
            isLoading = false
            AppLog.info("Image extraction complete, isLoading set to false", category: .extraction)
        }
    }
    
    /// Clear all current data
    func reset() {
        extractedRecipe = nil
        selectedImage = nil
        processedImage = nil
        errorMessage = nil
        isLoading = false
        recipeURL = ""
        extractedImageURLs = []
        validationResult = nil
        showingValidation = false
        isValidating = false
        isRecipeSaved = false
        savedRecipeID = nil
    }
    
    /// Toggle preprocessing and re-extract if image is available
    func togglePreprocessing() async {
        usePreprocessing.toggle()
        
        if let image = selectedImage {
            await extractRecipe(from: image)
        }
    }
    
    // MARK: - Recipe Enhancement Methods
    
    /// Auto-saves the recipe before enhancement to preserve state
    private func autoSaveBeforeEnhancement(modelContext: ModelContext) async {
        guard let recipe = extractedRecipe, !isRecipeSaved else { return }
        
        AppLog.info("Auto-saving recipe before enhancement: \(recipe.safeTitle)", category: .recipe)
        
        // Save recipe directly without duplicate check (user already saw extraction)
        await MainActor.run {
            saveRecipeDirectly(recipe, modelContext: modelContext)
            isRecipeSaved = true
            savedRecipeID = recipe.id
        }
    }
    
    /// Validates the extracted recipe content and shows suggestions
    func validateRecipe(modelContext: ModelContext? = nil) async {
        guard let recipe = extractedRecipe,
              let service = enhancementService else { return }
        
        // Auto-save before validation to preserve state
        if let context = modelContext {
            await autoSaveBeforeEnhancement(modelContext: context)
        }
        
        await MainActor.run {
            isValidating = true
            errorMessage = nil
        }
        
        AppLog.info("Starting recipe validation for: \(recipe.safeTitle)", category: .recipe)
        
        do {
            let result = try await service.validateRecipeContent(recipe)
            
            await MainActor.run {
                self.validationResult = result
                self.showingValidation = true
                AppLog.info("Validation complete. Valid: \(result.isValid)", category: .recipe)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Validation failed: \(error.localizedDescription)"
                AppLog.error("Validation error: \(error.localizedDescription)", category: .recipe)
            }
        }
        
        await MainActor.run {
            isValidating = false
        }
    }
    
    /// Applies validation corrections to the recipe
    func applyValidationCorrections(_ result: RecipeValidationResult) {
        guard let recipe = extractedRecipe,
              let corrections = result.corrections else { return }
        
        AppLog.info("Applying validation corrections to recipe", category: .recipe)
        
        // Apply title correction
        if let newTitle = corrections.title {
            recipe.title = newTitle
        }
        
        // Apply cuisine correction
        if let newCuisine = corrections.cuisine {
            recipe.cuisine = newCuisine
        }
        
        // Apply yield correction
        if let newYield = corrections.recipeYield {
            recipe.recipeYield = newYield
        }
        
        // Apply header notes correction
        if let newHeaderNotes = corrections.headerNotes {
            recipe.headerNotes = newHeaderNotes
        }
        
        // Apply ingredient sections correction
        if let simplifiedIngredients = corrections.ingredientSections {
            // Convert simplified format to full IngredientSection models
            let fullSections = simplifiedIngredients.map { simplified -> IngredientSection in
                let ingredients = simplified.ingredients.map { ingredientString -> Ingredient in
                    // Parse the string (e.g., "1 cup flour" or just "salt")
                    let parts = ingredientString.split(separator: " ", maxSplits: 2)
                    if parts.count >= 3 {
                        return Ingredient(
                            quantity: String(parts[0]),
                            unit: String(parts[1]),
                            name: String(parts[2])
                        )
                    } else if parts.count == 2 {
                        return Ingredient(
                            quantity: String(parts[0]),
                            name: String(parts[1])
                        )
                    } else {
                        return Ingredient(name: ingredientString)
                    }
                }
                return IngredientSection(title: simplified.title, ingredients: ingredients)
            }
            
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(fullSections) {
                recipe.updateIngredients(data)
            }
        }
        
        // Apply instruction sections correction
        if let simplifiedInstructions = corrections.instructionSections {
            // Convert simplified format to full InstructionSection models
            let fullSections = simplifiedInstructions.map { simplified -> InstructionSection in
                let steps = simplified.steps.enumerated().map { index, stepText in
                    InstructionStep(stepNumber: index + 1, text: stepText)
                }
                return InstructionSection(title: simplified.title, steps: steps)
            }
            
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(fullSections) {
                recipe.updateInstructions(data)
            }
        }
        
        // Update content fingerprint after corrections
        recipe.updateContentFingerprint()
        
        AppLog.info("Validation corrections applied successfully", category: .recipe)
    }
    
    
    /// Enhanced extraction workflow for images - includes validation and similar recipe search
    func extractRecipeWithEnhancement(from image: UIImage) async {
        // First, do the normal extraction
        await extractRecipe(from: image)
        
        // If extraction was successful and this is an image-based extraction
        // (which typically has less structured content), offer validation
        guard extractedRecipe != nil, errorMessage == nil else { return }
        
        // Automatically trigger validation for image-based extractions
        await validateRecipe()
    }
}
