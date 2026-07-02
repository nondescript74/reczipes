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

enum URLExtractionProviderPreference: String, CaseIterable, Identifiable {
    case recipeAPIFirstThenClaude
    case recipeAPIOnly
    case claudeOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recipeAPIFirstThenClaude:
            return "Auto (Recipe API -> Claude)"
        case .recipeAPIOnly:
            return "Recipe API Only"
        case .claudeOnly:
            return "Claude Only"
        }
    }
}

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
    @Published var urlProviderPreference: URLExtractionProviderPreference = .recipeAPIFirstThenClaude
    
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
    
    /// Extract recipe from a web URL using selected provider strategy
    func extractRecipe(
        from url: String,
        providerPreference: URLExtractionProviderPreference = .recipeAPIFirstThenClaude
    ) async {
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
            let (recipe, imageURLs) = try await extractRecipeFromURLUsingSelectedProvider(
                url: url,
                providerPreference: providerPreference
            )
            
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
        } catch let error as RecipeAPIError {
            await MainActor.run {
                self.errorMessage = error.errorDescription
                AppLog.error("Recipe API error during URL extraction: \(error.errorDescription ?? "unknown")", category: .extraction)
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

    private func extractRecipeFromURLUsingSelectedProvider(
        url: String,
        providerPreference: URLExtractionProviderPreference
    ) async throws -> (RecipeX, [String]) {
        switch providerPreference {
        case .claudeOnly:
            return try await extractRecipeWithClaude(from: url)

        case .recipeAPIOnly:
            return try await extractRecipeWithRecipeAPI(from: url)

        case .recipeAPIFirstThenClaude:
            do {
                return try await extractRecipeWithRecipeAPI(from: url)
            } catch {
                AppLog.warning("Recipe API URL extraction failed, falling back to Claude: \(error.localizedDescription)", category: .extraction)
                return try await extractRecipeWithClaude(from: url)
            }
        }
    }

    private func extractRecipeWithClaude(from url: String) async throws -> (RecipeX, [String]) {
        let htmlContent = try await webExtractor.fetchWebContent(from: url)
        let imageURLs = webExtractor.extractImageURLs(from: htmlContent)

        let cleanedContent = webExtractor.cleanHTML(htmlContent)
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
        let recipe = try await apiClient.extractRecipe(from: contentToSend)
        applySourceURL(url, to: recipe)
        return (recipe, imageURLs)
    }

    private func extractRecipeWithRecipeAPI(from url: String) async throws -> (RecipeX, [String]) {
        guard let recipeAPIKey = APIKeyHelper.getRecipeAPIKey(), !recipeAPIKey.isEmpty else {
            throw RecipeAPIError.missingAPIKey
        }

        let client = RecipeAPIClient(apiKey: recipeAPIKey)
        let query = buildSearchQuery(from: url)
        AppLog.info("Calling Recipe API search for URL extraction query: \(query)", category: .extraction)

        let searchResults = try await client.searchRecipes(query: query, perPage: 8)
        guard let bestMatch = bestMatchFromRecipeAPI(searchResults, query: query) else {
            throw RecipeAPIError.requestFailed(code: 404, message: "No matching recipe found from Recipe API search.")
        }

        let detail = try await client.fetchRecipeDetails(id: bestMatch.id)
        let recipe = try buildRecipeXFromRecipeAPIDetail(detail, originalURL: url)
        let imageURLs = await fetchImageURLsIfAvailable(for: url)
        return (recipe, imageURLs)
    }

    private func buildSearchQuery(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return urlString }
        let rawSlug = url.deletingPathExtension().lastPathComponent
        let cleanedSlug = rawSlug.replacingOccurrences(of: #"-\d+$"#, with: "", options: .regularExpression)
        let candidate = cleanedSlug.removingPercentEncoding ?? cleanedSlug
        let terms = candidate
            .split(separator: "-")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count > 2 }

        if terms.isEmpty {
            return urlString
        }
        return terms.joined(separator: " ")
    }

    private func bestMatchFromRecipeAPI(
        _ items: [RecipeAPISearchItem],
        query: String
    ) -> RecipeAPISearchItem? {
        guard !items.isEmpty else { return nil }
        let queryTokens = tokenize(query)
        return items.max { lhs, rhs in
            scoreMatch(lhs.name, queryTokens: queryTokens) < scoreMatch(rhs.name, queryTokens: queryTokens)
        }
    }

    private func tokenize(_ input: String) -> Set<String> {
        let separators = CharacterSet.alphanumerics.inverted
        let tokens = input.lowercased()
            .components(separatedBy: separators)
            .filter { $0.count > 2 }
        return Set(tokens)
    }

    private func scoreMatch(_ name: String, queryTokens: Set<String>) -> Int {
        let nameTokens = tokenize(name)
        let overlap = nameTokens.intersection(queryTokens).count
        return overlap * 10 + nameTokens.count
    }

    private func buildRecipeXFromRecipeAPIDetail(
        _ detail: RecipeAPIDetailRecipe,
        originalURL: String
    ) throws -> RecipeX {
        let ingredientSections = (detail.ingredients ?? []).map { group in
            IngredientSection(
                title: group.groupName,
                ingredients: group.items.map { item in
                    Ingredient(
                        quantity: formatQuantity(item.quantity),
                        unit: item.unit,
                        name: item.name,
                        preparation: item.preparation
                    )
                }
            )
        }

        let instructionSections = buildInstructionSections(from: detail.instructions ?? [])

        let ingredientsData = try JSONEncoder().encode(ingredientSections)
        let instructionsData = try JSONEncoder().encode(instructionSections)

        let recipe = RecipeX(
            title: detail.name,
            headerNotes: detail.description,
            recipeYield: detail.meta?.yields,
            reference: "Original Source: \(originalURL)\n\nProvider: recipe-api.com",
            ingredientSectionsData: ingredientsData,
            instructionSectionsData: instructionsData,
            extractionSource: "url-recipe-api",
            cuisine: detail.cuisine
        )

        recipe.difficultyLevel = mapDifficulty(detail.difficulty)
        return recipe
    }

    private func buildInstructionSections(from steps: [RecipeAPIInstructionStep]) -> [InstructionSection] {
        var grouped: [String: [RecipeAPIInstructionStep]] = [:]
        var orderedPhases: [String] = []

        for step in steps {
            let phase = (step.phase?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? step.phase!.trimmingCharacters(in: .whitespacesAndNewlines)
                : "Instructions"
            if grouped[phase] == nil {
                grouped[phase] = []
                orderedPhases.append(phase)
            }
            grouped[phase]?.append(step)
        }

        return orderedPhases.map { phase in
            let sortedSteps = (grouped[phase] ?? []).sorted {
                ($0.stepNumber ?? Int.max) < ($1.stepNumber ?? Int.max)
            }
            let mappedSteps = sortedSteps.enumerated().map { index, step in
                InstructionStep(
                    stepNumber: step.stepNumber ?? (index + 1),
                    text: step.text
                )
            }
            return InstructionSection(title: phase == "Instructions" ? nil : phase, steps: mappedSteps)
        }
    }

    private func formatQuantity(_ quantity: Double?) -> String? {
        guard let quantity else { return nil }
        if quantity.rounded() == quantity {
            return String(Int(quantity))
        }
        return String(format: "%.2f", quantity).replacingOccurrences(of: #"(\.\d*?[1-9])0+$|\.0+$"#, with: "$1", options: .regularExpression)
    }

    private func mapDifficulty(_ difficulty: String?) -> Int? {
        guard let value = difficulty?.lowercased() else { return nil }
        if value.contains("easy") { return 1 }
        if value.contains("medium") { return 2 }
        if value.contains("hard") { return 3 }
        return nil
    }

    private func applySourceURL(_ url: String, to recipe: RecipeX) {
        if let existingReference = recipe.reference, !existingReference.isEmpty {
            if !existingReference.contains(url) {
                recipe.reference = existingReference + "\n\nOriginal Source: " + url
            }
        } else {
            recipe.reference = "Original Source: " + url
        }
    }

    private func fetchImageURLsIfAvailable(for url: String) async -> [String] {
        guard let html = try? await webExtractor.fetchWebContent(from: url) else { return [] }
        return webExtractor.extractImageURLs(from: html)
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
