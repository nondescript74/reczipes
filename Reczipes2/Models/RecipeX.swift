//
//  RecipeX.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/26/26.
//
//  UNIFIED RECIPE MODEL - CloudKit Compatible
//  Combines Recipe, SharedRecipe, and RecipeModel into a single model
//  with automatic iCloud sharing built-in.

import Foundation
import SwiftData
import CloudKit
import CryptoKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import SwiftUI

/// Unified recipe model with automatic iCloud sharing
/// 
/// DESIGN PHILOSOPHY:
/// - Local-first: All recipes are stored locally in SwiftData
/// - Auto-sync: Recipes automatically sync to iCloud Public Database
/// - Always shared: No concept of "not sharing" - all recipes are public
/// - Simple: One model, one source of truth
///
/// SYNC STRATEGY:
/// - User creates/edits recipe → Saved to SwiftData
/// - Background sync service uploads to CloudKit Public DB
/// - Other users can discover recipes via CloudKit queries
/// - Recipes sync across user's devices via iCloud (CloudKit Private DB)
///
/// CLOUDKIT COMPATIBILITY:
/// - All properties are optional or have default values
/// - No @Attribute(.unique) constraints (CloudKit doesn't support this)
/// - Uses standard Swift/CloudKit types only
@Model
final class RecipeX {
    
    // MARK: - Core Identity
    
    /// Unique identifier (stable across all sync operations)
    var id: UUID?
    
    /// Recipe title
    var title: String?
    
    // MARK: - Recipe Content
    
    /// Optional header notes (introduction, story, context)
    var headerNotes: String?
    
    /// Yield/servings (e.g., "Serves 4", "Makes 12 cookies")
    var recipeYield: String?
    
    /// Reference/source (e.g., "Grandma's cookbook", "NYT Cooking")
    var reference: String?
    
    /// Ingredient sections stored as JSON
    /// Encodes [IngredientSection] for structured ingredient lists
    var ingredientSectionsData: Data?
    
    /// Instruction sections stored as JSON
    /// Encodes [InstructionSection] for step-by-step instructions
    var instructionSectionsData: Data?
    
    /// Recipe notes stored as JSON
    /// Encodes [RecipeNote] for tips, substitutions, warnings, etc.
    var notesData: Data?
    
    // MARK: - Images
    
    /// Main recipe image data (stored in SwiftData for CloudKit sync)
    @Attribute(.externalStorage) var imageData: Data?
    
    /// Additional images stored as JSON array
    /// Each image is stored as {"data": Data, "name": String}
    @Attribute(.externalStorage) var additionalImagesData: Data?
    
    /// Legacy: File name of main image (for backward compatibility)
    var imageName: String?
    
    /// Legacy: File names of additional images (for backward compatibility)
    var additionalImageNames: [String]?
    
    // MARK: - Timestamps
    
    /// When the recipe was added to this user's library
    var dateAdded: Date?
    
    /// When the recipe was first created (may differ from dateAdded if imported)
    var dateCreated: Date?
    
    /// Last modification timestamp (for conflict resolution)
    var lastModified: Date?
    
    // MARK: - Versioning & Change Detection
    
    /// Version number (increments on each edit)
    var version: Int?
    
    /// Hash of ingredients (for efficient change detection)
    var ingredientsHash: String?
    
    /// Content fingerprint for duplicate detection
    var contentFingerprint: String?
    
    // MARK: - CloudKit Sync
    
    /// CloudKit record ID in Public Database (nil if not yet uploaded)
    var cloudRecordID: String?
    
    /// When the recipe was last successfully synced to CloudKit
    var lastSyncedToCloud: Date?
    
    /// Whether the recipe needs to be uploaded/updated in CloudKit
    var needsCloudSync: Bool?
    
    /// Number of sync retry attempts (for error handling)
    var syncRetryCount: Int?
    
    /// Last sync error message (for debugging)
    var lastSyncError: String?
    
    // MARK: - User Attribution
    
    /// CloudKit user ID who created this recipe
    var ownerUserID: String?
    
    /// Display name of the user who created this recipe
    var ownerDisplayName: String?
    
    /// Current user's device identifier (for tracking which device made changes)
    var lastModifiedDeviceID: String?
    
    // MARK: - Metadata
    
    /// Image hash for duplicate detection (SHA256 of main image)
    var imageHash: String?
    
    /// Source of recipe extraction ("camera", "photos", "files", "web", "manual")
    var extractionSource: String?
    
    /// Original filename (if extracted from file)
    var originalFileName: String?
    
    /// Tags for categorization (stored as JSON array)
    var tagsData: Data?
    
    /// Cuisine type (e.g., "Italian", "Mexican", "Thai")
    var cuisine: String?
    
    /// Preparation time in minutes
    var prepTimeMinutes: Int?
    
    /// Cooking time in minutes
    var cookTimeMinutes: Int?
    
    /// Difficulty level (1-5, where 1 is easiest)
    var difficultyLevel: Int?
    
    /// User's personal rating (1-5 stars)
    var personalRating: Int?
    
    /// Number of times this recipe has been cooked by the user
    var timesCooked: Int?
    
    /// Last time the user cooked this recipe
    var lastCookedDate: Date?
    
    // MARK: - Initializer
    
    init(id: UUID? = UUID(),
         title: String? = nil,
         headerNotes: String? = nil,
         recipeYield: String? = nil,
         reference: String? = nil,
         ingredientSectionsData: Data? = nil,
         instructionSectionsData: Data? = nil,
         notesData: Data? = nil,
         imageData: Data? = nil,
         additionalImagesData: Data? = nil,
         imageName: String? = nil,
         additionalImageNames: [String]? = nil,
         dateAdded: Date? = Date(),
         dateCreated: Date? = Date(),
         lastModified: Date? = Date(),
         version: Int? = 1,
         ingredientsHash: String? = nil,
         contentFingerprint: String? = nil,
         cloudRecordID: String? = nil,
         needsCloudSync: Bool? = true,
         ownerUserID: String? = nil,
         ownerDisplayName: String? = nil,
         imageHash: String? = nil,
         extractionSource: String? = nil,
         originalFileName: String? = nil,
         tagsData: Data? = nil,
         cuisine: String? = nil,
         prepTimeMinutes: Int? = nil,
         cookTimeMinutes: Int? = nil,
         difficultyLevel: Int? = nil,
         personalRating: Int? = nil,
         timesCooked: Int? = 0) {
        
        self.id = id
        self.title = title
        self.headerNotes = headerNotes
        self.recipeYield = recipeYield
        self.reference = reference
        self.ingredientSectionsData = ingredientSectionsData
        self.instructionSectionsData = instructionSectionsData
        self.notesData = notesData
        self.imageData = imageData
        self.additionalImagesData = additionalImagesData
        self.imageName = imageName
        self.additionalImageNames = additionalImageNames
        self.dateAdded = dateAdded
        self.dateCreated = dateCreated
        self.lastModified = lastModified
        self.version = version
        self.ingredientsHash = ingredientsHash ?? Self.calculateIngredientsHash(from: ingredientSectionsData)
        self.contentFingerprint = contentFingerprint
        self.cloudRecordID = cloudRecordID
        self.needsCloudSync = needsCloudSync
        self.syncRetryCount = 0
        self.ownerUserID = ownerUserID
        self.ownerDisplayName = ownerDisplayName
        self.imageHash = imageHash ?? Self.calculateImageHash(from: imageData)
        self.extractionSource = extractionSource
        self.originalFileName = originalFileName
        self.tagsData = tagsData
        self.cuisine = cuisine
        self.prepTimeMinutes = prepTimeMinutes
        self.cookTimeMinutes = cookTimeMinutes
        self.difficultyLevel = difficultyLevel
        self.personalRating = personalRating
        self.timesCooked = timesCooked
    }
}

// MARK: - Computed Properties

extension RecipeX {
    
    /// Safe ID accessor (returns UUID() if nil)
    var safeID: UUID {
        return id ?? UUID()
    }
    
    /// Safe title accessor (returns empty string if nil)
    var safeTitle: String {
        return title ?? ""
    }
    
    /// Total time in minutes (prep + cook)
    var totalTimeMinutes: Int? {
        guard let prep = prepTimeMinutes, let cook = cookTimeMinutes else {
            return prepTimeMinutes ?? cookTimeMinutes
        }
        return prep + cook
    }
    
    /// Safe version access with overflow protection
    var currentVersion: Int {
        guard let version = version, version >= 0 && version < Int.max - 100 else {
            return 1
        }
        return version
    }
    
    /// Modification date with fallback
    var modificationDate: Date {
        return lastModified ?? dateAdded ?? Date()
    }
    
    /// Tags accessor (decode from Data)
    var tags: [String] {
        guard let tagsData = tagsData,
              let decoded = try? JSONDecoder().decode([String].self, from: tagsData) else {
            return []
        }
        return decoded
    }
    
    /// Set tags (encode to Data)
    func setTags(_ tags: [String]) {
        self.tagsData = try? JSONEncoder().encode(tags)
    }
    
    /// All image names (main + additional)
    var allImageNames: [String] {
        var images: [String] = []
        if let mainImage = imageName {
            images.append(mainImage)
        }
        if let additional = additionalImageNames {
            images.append(contentsOf: additional)
        }
        return images
    }
    
    /// Total image count
    var imageCount: Int {
        var count = 0
        if imageData != nil { count += 1 }
        if let additionalData = additionalImagesData,
           let decoded = try? JSONDecoder().decode([[String: Data]].self, from: additionalData) {
            count += decoded.count
        }
        return count
    }
    
    /// Whether recipe has been synced to CloudKit
    var isSyncedToCloud: Bool {
        return cloudRecordID != nil && lastSyncedToCloud != nil
    }
    
    /// Whether recipe was created by the current user
    func isOwnedBy(userID: String) -> Bool {
        return ownerUserID == userID
    }
}

// MARK: - Flat Lists for CookingMode Compatibility

extension RecipeX {
    
    /// Flat array of all ingredients across all sections
    /// Formatted as "quantity unit name" for CookingMode display
    var ingredients: [String] {
        guard let sectionsData = ingredientSectionsData,
              let sections = try? JSONDecoder().decode([IngredientSection].self, from: sectionsData) else {
            return []
        }
        
        return sections.flatMap { section in
            section.ingredients.map { ingredient in
                var parts: [String] = []
                if let quantity = ingredient.quantity?.trimmingCharacters(in: .whitespaces), !quantity.isEmpty {
                    parts.append(quantity)
                }
                if let unit = ingredient.unit?.trimmingCharacters(in: .whitespaces), !unit.isEmpty {
                    parts.append(unit)
                }
                parts.append(ingredient.name)
                return parts.joined(separator: " ")
            }
        }
    }
    
    /// Flat array of all instruction steps across all sections
    var instructions: [String] {
        guard let sectionsData = instructionSectionsData,
              let sections = try? JSONDecoder().decode([InstructionSection].self, from: sectionsData) else {
            return []
        }
        
        return sections.flatMap { section in
            section.steps.map { $0.text }
        }
    }
    
    /// Number of servings extracted from yield string
    var servings: Int? {
        guard let yieldString = recipeYield else { return nil }
        
        let numbers = yieldString.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
        
        return numbers.first
    }
    
    /// Check if recipe has minimum data for CookingMode
    var isValidForCookingMode: Bool {
        return !(title ?? "").isEmpty &&
               !ingredients.isEmpty &&
               !instructions.isEmpty
    }
    
    /// Decoded ingredient sections (for view access)
    var ingredientSections: [IngredientSection] {
        guard let sectionsData = ingredientSectionsData,
              let sections = try? JSONDecoder().decode([IngredientSection].self, from: sectionsData) else {
            return []
        }
        return sections
    }
    
    /// Decoded instruction sections (for view access)
    var instructionSections: [InstructionSection] {
        guard let sectionsData = instructionSectionsData,
              let sections = try? JSONDecoder().decode([InstructionSection].self, from: sectionsData) else {
            return []
        }
        return sections
    }
    
    /// Decoded notes (for view access)
    var notes: [RecipeNote] {
        guard let notesDataValue = notesData,
              let notes = try? JSONDecoder().decode([RecipeNote].self, from: notesDataValue) else {
            return []
        }
        return notes
    }
    
    /// Alias for recipeYield to match legacy API
    var yield: String? {
        return recipeYield
    }

    // MARK: - Repair Detection

    /// Whether this recipe is missing ingredients or instructions and needs repair
    var needsRepair: Bool {
        let missingIngredients = ingredientSectionsData == nil || ingredientSections.isEmpty
        let missingInstructions = instructionSectionsData == nil || instructionSections.isEmpty
        return missingIngredients || missingInstructions
    }

    /// Whether we have a source (URL or image) to attempt re-extraction
    var canBeRepaired: Bool {
        guard needsRepair else { return false }
        // Can repair if we have a source URL or image data
        if let ref = reference, !ref.isEmpty, URL(string: ref) != nil { return true }
        if imageData != nil { return true }
        return false
    }

    /// Description of what's missing for display purposes
    var missingDataDescription: String {
        var missing: [String] = []
        if ingredientSectionsData == nil || ingredientSections.isEmpty {
            missing.append("ingredients")
        }
        if instructionSectionsData == nil || instructionSections.isEmpty {
            missing.append("instructions")
        }
        return missing.joined(separator: " & ")
    }
}

// MARK: - Image Management

extension RecipeX {
    
    /// Get main image as PlatformImage
    func getMainImage() -> PlatformImage? {
        guard let imageData = imageData else { return nil }
        return PlatformImage(data: imageData)
    }

    /// Get all additional images
    func getAdditionalImages() -> [PlatformImage] {
        guard let additionalImagesData = additionalImagesData,
              let decoded = try? JSONDecoder().decode([[String: Data]].self, from: additionalImagesData) else {
            return []
        }

        return decoded.compactMap { imageDict in
            guard let data = imageDict["data"] else { return nil }
            return PlatformImage(data: data)
        }
    }

    /// Get image by index (0 = main, 1+ = additional)
    func getImage(at index: Int) -> PlatformImage? {
        if index == 0 {
            return getMainImage()
        } else {
            let additionalImages = getAdditionalImages()
            let additionalIndex = index - 1
            guard additionalIndex < additionalImages.count else { return nil }
            return additionalImages[additionalIndex]
        }
    }
    
    /// Get all image data (for export/backup)
    func getAllImageData() -> [Data] {
        var images: [Data] = []
        
        if let imageData = imageData {
            images.append(imageData)
        }
        
        if let additionalImagesData = additionalImagesData,
           let decoded = try? JSONDecoder().decode([[String: Data]].self, from: additionalImagesData) {
            for imageDict in decoded {
                if let data = imageDict["data"] {
                    images.append(data)
                }
            }
        }
        
        return images
    }
    
    /// Set main image
    @MainActor
    func setImage(_ image: PlatformImage, isMainImage: Bool = true) {
        // Try optimized compression first
        var imageData = ImageCompressionUtility.compressImage(image)
        
        // Fallback: use basic JPEG compression if utility fails
        if imageData == nil {
            AppLog.warning("Compression utility failed for '\(safeTitle)', using fallback JPEG compression (original size: \(image.size))", category: .recipe)
            imageData = image.jpegData(compressionQuality: 0.8)
        }
        
        guard let imageData else {
            AppLog.error("Both compression methods failed for recipe '\(safeTitle)' - image size: \(image.size), scale: \(image.scale)", category: .recipe)
            return
        }
        
        AppLog.info("Successfully compressed image for '\(safeTitle)' to \(imageData.count) bytes", category: .recipe)

        if isMainImage {
            self.imageData = imageData
            self.imageName = "recipe_\(safeID.uuidString).jpg"
            self.imageHash = Self.calculateImageHash(from: imageData)
            markAsModified()
        } else {
            addAdditionalImage(imageData)
        }
    }
    
    /// Add additional image
    @MainActor
    private func addAdditionalImage(_ imageData: Data) {
        var additionalImages: [[String: Data]] = []
        
        if let existingData = additionalImagesData,
           let existing = try? JSONDecoder().decode([[String: Data]].self, from: existingData) {
            additionalImages = existing
        }
        
        let imageName = "recipe_\(safeID.uuidString)_\(additionalImages.count).jpg"
        additionalImages.append(["data": imageData, "name": Data(imageName.utf8)])
        
        if let encoded = try? JSONEncoder().encode(additionalImages) {
            self.additionalImagesData = encoded
        }
        
        if self.additionalImageNames == nil {
            self.additionalImageNames = []
        }
        self.additionalImageNames?.append(imageName)
        
        markAsModified()
    }
    
    /// Remove additional image by index
    @MainActor
    func removeAdditionalImage(at index: Int) {
        guard let additionalImagesData = additionalImagesData,
              var decoded = try? JSONDecoder().decode([[String: Data]].self, from: additionalImagesData),
              index < decoded.count else {
            return
        }
        
        decoded.remove(at: index)
        
        if decoded.isEmpty {
            self.additionalImagesData = nil
        } else {
            self.additionalImagesData = try? JSONEncoder().encode(decoded)
        }
        
        if var names = additionalImageNames, index < names.count {
            names.remove(at: index)
            self.additionalImageNames = names.isEmpty ? nil : names
        }
        
        markAsModified()
    }
}

// MARK: - Change Tracking

extension RecipeX {
    
    /// Mark recipe as modified (increments version, updates timestamp, triggers sync)
    @MainActor
    func markAsModified() {
        let newVersion = currentVersion.addingReportingOverflow(1)
        if newVersion.overflow {
            self.version = 1
        } else {
            self.version = newVersion.partialValue
        }
        
        self.lastModified = Date()
        self.needsCloudSync = true
        self.syncRetryCount = 0 // Reset retry count on new changes
    }
    
    /// Update ingredients and mark as modified
    @MainActor
    func updateIngredients(_ ingredientsData: Data) {
        self.ingredientSectionsData = ingredientsData
        self.ingredientsHash = Self.calculateIngredientsHash(from: ingredientsData)
        markAsModified()
    }
    
    /// Update instructions and mark as modified
    @MainActor
    func updateInstructions(_ instructionsData: Data) {
        self.instructionSectionsData = instructionsData
        markAsModified()
    }
    
    /// Record successful sync to CloudKit
    @MainActor
    func markAsSynced(recordID: String) {
        self.cloudRecordID = recordID
        self.lastSyncedToCloud = Date()
        self.needsCloudSync = false
        self.syncRetryCount = 0
        self.lastSyncError = nil
    }
    
    /// Record sync failure
    @MainActor
    func markSyncFailed(error: String) {
        self.syncRetryCount = (syncRetryCount ?? 0) + 1
        self.lastSyncError = error
        // Keep needsCloudSync = true to retry later
    }
    
    /// Increment times cooked
    @MainActor
    func recordCookingSession() {
        self.timesCooked = (timesCooked ?? 0) + 1
        self.lastCookedDate = Date()
        // Don't increment version or trigger sync for cooking stats
    }
}

// MARK: - Conversion Methods

// MARK: - Hash Calculation

extension RecipeX {
    
    /// Calculate SHA256 hash of ingredients
    static func calculateIngredientsHash(from ingredientsData: Data?) -> String? {
        guard let data = ingredientsData else { return nil }
        
        let decoder = JSONDecoder()
        guard let sections = try? decoder.decode([IngredientSection].self, from: data) else {
            return nil
        }
        
        let ingredientStrings = sections.flatMap { section in
            section.ingredients.map { ingredient in
                let qty = ingredient.quantity ?? ""
                let unit = ingredient.unit ?? ""
                let name = ingredient.name
                return "\(qty)|\(unit)|\(name)"
            }
        }.sorted()
        
        let combined = ingredientStrings.joined(separator: "||")
        return combined.sha256Hash()
    }
    
    /// Calculate SHA256 hash of image
    static func calculateImageHash(from imageData: Data?) -> String? {
        guard let data = imageData else { return nil }
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Generate content fingerprint for duplicate detection
    @MainActor func generateContentFingerprint() -> String {
        var components: [String] = []
        
        let normalizedTitle = (title ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        components.append(normalizedTitle)
        
        if let hash = ingredientsHash {
            components.append(hash)
        }
        
        if let instructionsData = instructionSectionsData {
            let instructionsHash = String(describing: instructionsData.hashValue)
            components.append(instructionsHash)
        }
        
        let combined = components.joined(separator: "|")
        return combined.sha256Hash()
    }
    
    /// Update content fingerprint
    @MainActor
    func updateContentFingerprint() {
        self.contentFingerprint = generateContentFingerprint()
    }
}

// MARK: - Preview Helper

extension RecipeX {
    
    @MainActor
    static var preview: RecipeX {
        let sampleIngredients = [
            IngredientSection(
                title: "Main Ingredients",
                ingredients: [
                    Ingredient(quantity: "2", unit: "cups", name: "flour"),
                    Ingredient(quantity: "1", unit: "tsp", name: "salt"),
                    Ingredient(quantity: "3", unit: "", name: "eggs")
                ]
            )
        ]
        
        let sampleInstructions = [
            InstructionSection(
                title: "Preparation",
                steps: [
                    InstructionStep(stepNumber: 1, text: "Preheat oven to 350°F"),
                    InstructionStep(stepNumber: 2, text: "Mix dry ingredients"),
                    InstructionStep(stepNumber: 3, text: "Add wet ingredients")
                ]
            )
        ]
        
        let sampleNotes = [
            RecipeNote(type: .tip, text: "Room temperature ingredients work best")
        ]
        
        return RecipeX(
            title: "Sample Recipe",
            headerNotes: "A delicious sample recipe",
            recipeYield: "Serves 4",
            reference: "Test Recipe",
            ingredientSectionsData: try? JSONEncoder().encode(sampleIngredients),
            instructionSectionsData: try? JSONEncoder().encode(sampleInstructions),
            notesData: try? JSONEncoder().encode(sampleNotes),
            cuisine: "American",
            prepTimeMinutes: 15,
            cookTimeMinutes: 30,
            difficultyLevel: 2
        )
    }
}

// MARK: - Migration Support

extension RecipeX {
    
    /// Migrate from file-based images to SwiftData imageData
    @MainActor
    func migrateImagesToSwiftData() -> Bool {
        var didMigrate = false
        
        // Migrate main image
        if imageData == nil, let imageName = imageName {
            if let data = loadImageDataFromDocuments(imageName) {
                imageData = data
                imageHash = Self.calculateImageHash(from: data)
                didMigrate = true
            }
        }
        
        // Migrate additional images
        if additionalImagesData == nil, let additionalImageNames = additionalImageNames, !additionalImageNames.isEmpty {
            var migratedImages: [[String: Data]] = []
            
            for imageName in additionalImageNames {
                if let imageData = loadImageDataFromDocuments(imageName) {
                    migratedImages.append(["data": imageData, "name": Data(imageName.utf8)])
                }
            }
            
            if !migratedImages.isEmpty {
                if let encoded = try? JSONEncoder().encode(migratedImages) {
                    additionalImagesData = encoded
                    didMigrate = true
                }
            }
        }
        
        return didMigrate
    }
    
    @MainActor
    private func loadImageDataFromDocuments(_ filename: String) -> Data? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }
}

// MARK: - String Extension

extension String {
    /// Calculate SHA256 hash of string
    nonisolated func sha256Hash() -> String {
        guard let data = self.data(using: .utf8) else { return "" }
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

