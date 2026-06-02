//
//  RecipeBookImportService.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 01/02/26.
//

import Foundation
import SwiftData

// MARK: - Import Service

/// Service for importing recipe books shared from other users
@MainActor
class RecipeBookImportService {
    
    static let shared = RecipeBookImportService()
    
    private init() {}
    
    // MARK: - Import Types
    
    /// Export/Import package structure
    struct BookExportPackage: Codable {
        let version: String
        let book: ExportableBook
        let recipes: [ExportableRecipe]
        let imageManifest: [ImageManifestEntry]
        
        var summary: String {
            "\(recipes.count) recipes, \(imageManifest.count) images"
        }
    }
    
    /// Exportable book data
    struct ExportableBook: Codable {
        let id: UUID
        let name: String
        let bookDescription: String?
        let coverImageName: String?
        let dateCreated: Date
        let dateModified: Date
        let recipeIDs: [UUID]
        let color: String?
    }
    
    /// Exportable recipe data
    struct ExportableRecipe: Codable {
        let id: UUID
        let title: String
        let headerNotes: String?
        let yield: String?
        let ingredientSections: [IngredientSection]
        let instructionSections: [InstructionSection]
        let notes: [RecipeNote]
        let reference: String?
        let imageName: String?
        let additionalImageNames: [String]?
        let imageURLs: [String]?
    }
    
    /// Image manifest entry
    struct ImageManifestEntry: Codable {
        let fileName: String
        let type: ImageManifestType
        let associatedID: UUID
    }
    
    /// Image types in manifest
    enum ImageManifestType: String, Codable {
        case bookCover = "book_cover"
        case recipePrimary = "recipe_primary"
        case recipeAdditional = "recipe_additional"
    }
    
    /// Import mode for handling conflicts
    enum BookImportMode {
        case replace
        case keepBoth
        case merge
        
        var description: String {
            switch self {
            case .replace: return "Replace existing book"
            case .keepBoth: return "Keep both versions"
            case .merge: return "Merge recipes into existing book"
            }
        }
    }
    
    /// Result of a book import operation
    struct BookImportResult {
        let book: Book
        let recipesImported: Int
        let recipesUpdated: Int
        let imagesImported: Int
        let wasReplaced: Bool
    }
    
    /// Errors that can occur during recipe book import
    enum ImportError: LocalizedError {
        case invalidFile
        case decodingFailed(Error)
        case existingBookConflict(String)
        case extractionFailed(Error)
        case imageCopyFailed(Error)
        case saveFailed(Error)
        case unsupportedVersion(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidFile:
                return "The selected file is not a valid recipe book."
            case .decodingFailed(let error):
                return "Could not read recipe book: \(error.localizedDescription)"
            case .existingBookConflict(let name):
                return "A book named '\(name)' already exists. Choose how to handle this conflict."
            case .extractionFailed(let error):
                return "Failed to extract recipe book: \(error.localizedDescription)"
            case .imageCopyFailed(let error):
                return "Failed to import images: \(error.localizedDescription)"
            case .saveFailed(let error):
                return "Failed to save imported book: \(error.localizedDescription)"
            case .unsupportedVersion(let version):
                return "This recipe book version (\(version)) is not supported by this app version."
            }
        }
    }
    
    // MARK: - Public API
    
    /// Previews a recipe book file without importing it
    /// - Parameter url: URL to the .recipebook file
    /// - Returns: Information about the book to be imported
    func previewBook(from url: URL) async throws -> BookExportPackage {
        AppLog.info("Previewing recipe book from: \(url.lastPathComponent)", category: .batch)
        
        // Create temporary extraction directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeBookPreview_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Extract ZIP
        do {
            try RecipeBookExportService.extractZipArchive(from: url, to: tempDir)
        } catch {
            AppLog.error("Failed to extract book for preview: \(error)", category: .batch)
            throw ImportError.extractionFailed(error)
        }
        
        // Read JSON metadata
        let jsonURL = tempDir.appendingPathComponent("book.json")
        
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            AppLog.error("book.json not found in archive", category: .batch)
            throw ImportError.invalidFile
        }
        
        let jsonData = try Data(contentsOf: jsonURL)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let exportPackage = try decoder.decode(BookExportPackage.self, from: jsonData)
            
            // Validate version
            if !isSupportedVersion(exportPackage.version) {
                throw ImportError.unsupportedVersion(exportPackage.version)
            }
            
            AppLog.info("Preview loaded: \(exportPackage.book.name) - \(exportPackage.summary)", category: .batch)
            return exportPackage
        } catch let error as ImportError {
            throw error
        } catch {
            AppLog.error("Failed to decode book metadata: \(error)", category: .batch)
            throw ImportError.decodingFailed(error)
        }
    }
    
    /// Checks if a book with the same ID already exists
    /// - Parameters:
    ///   - bookID: The ID of the book to check
    ///   - modelContext: SwiftData model context
    /// - Returns: The existing book if found, nil otherwise
    func checkForExistingBook(bookID: UUID, modelContext: ModelContext) throws -> Book? {
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate { book in
                book.id == bookID
            }
        )
        
        let existingBooks = try modelContext.fetch(descriptor)
        return existingBooks.first
    }
    
    /// Imports a recipe book with the specified import mode
    /// - Parameters:
    ///   - url: URL to the .recipebook file
    ///   - modelContext: SwiftData model context
    ///   - importMode: How to handle conflicts with existing books
    /// - Returns: Result information about the import
    func importBook(
        from url: URL,
        modelContext: ModelContext,
        importMode: BookImportMode = .keepBoth
    ) async throws -> BookImportResult {
        AppLog.info("Starting import with mode: \(importMode.description)", category: .batch)
        
        // First, preview the book to get its metadata
        let exportPackage = try await previewBook(from: url)
        
        // Check for existing book
        let existingBook = try checkForExistingBook(bookID: exportPackage.book.id, modelContext: modelContext)
        
        var recipesImported = 0
        var recipesUpdated = 0
        var imagesImported = 0
        var wasReplaced = false
        
        // Handle import based on mode
        let importedBook: Book
        
        switch importMode {
        case .replace:
            if let existing = existingBook {
                wasReplaced = true
                // Delete existing book and all its recipes
                modelContext.delete(existing)
                AppLog.info("Deleted existing book: \(existing.name ?? "Untitled")", category: .batch)
            }
            
            // Import as original book
            let result = try await performImport(
                exportPackage: exportPackage,
                url: url,
                modelContext: modelContext,
                createNewID: false
            )
            importedBook = result.book
            recipesImported = result.newRecipes
            recipesUpdated = result.updatedRecipes
            imagesImported = result.images
            
        case .keepBoth:
            // Always create a new book with new IDs
            let result = try await performImport(
                exportPackage: exportPackage,
                url: url,
                modelContext: modelContext,
                createNewID: true
            )
            importedBook = result.book
            recipesImported = result.newRecipes
            imagesImported = result.images
            
        case .merge:
            if let existing = existingBook {
                // Merge recipes into existing book
                let result = try await performMergeImport(
                    exportPackage: exportPackage,
                    url: url,
                    existingBook: existing,
                    modelContext: modelContext
                )
                importedBook = existing
                recipesImported = result.newRecipes
                recipesUpdated = result.updatedRecipes
                imagesImported = result.images
            } else {
                // No existing book, just import normally
                let result = try await performImport(
                    exportPackage: exportPackage,
                    url: url,
                    modelContext: modelContext,
                    createNewID: false
                )
                importedBook = result.book
                recipesImported = result.newRecipes
                imagesImported = result.images
            }
        }
        
        // Save context
        do {
            try modelContext.save()
            AppLog.info("Successfully saved imported book: \(importedBook.name ?? "Untitled")", category: .batch)
        } catch {
            AppLog.error("Failed to save imported book: \(error)", category: .batch)
            throw ImportError.saveFailed(error)
        }
        
        return BookImportResult(
            book: importedBook,
            recipesImported: recipesImported,
            recipesUpdated: recipesUpdated,
            imagesImported: imagesImported,
            wasReplaced: wasReplaced
        )
    }
    
    // MARK: - Private Helpers
    
    private func performImport(
        exportPackage: BookExportPackage,
        url: URL,
        modelContext: ModelContext,
        createNewID: Bool
    ) async throws -> (book: Book, newRecipes: Int, updatedRecipes: Int, images: Int) {
        // Extract to temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeBookImport_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        do {
            try RecipeBookExportService.extractZipArchive(from: url, to: tempDir)
        } catch {
            throw ImportError.extractionFailed(error)
        }
        
        // Load images from archive into memory
        let imageDataMap = try loadImagesFromArchive(from: tempDir, manifest: exportPackage.imageManifest)
        
        // Create or update recipes
        var newRecipes = 0
        var updatedRecipes = 0
        var importedRecipeIDs: [UUID] = []
        var imagesImported = 0
        
        for recipeModel in exportPackage.recipes {
            let result = try await importOrUpdateRecipe(
                recipeModel,
                imageDataMap: imageDataMap,
                modelContext: modelContext,
                createNewID: createNewID
            )
            
            importedRecipeIDs.append(result.recipeID)
            imagesImported += result.imagesAssigned
            
            if result.wasNew {
                newRecipes += 1
            } else {
                updatedRecipes += 1
            }
        }
        
        // Create the book
        let bookID = createNewID ? UUID() : exportPackage.book.id
        let bookName = createNewID ? "\(exportPackage.book.name) (Imported)" : exportPackage.book.name
        
        // Get book cover image data if available
        var coverImageData: Data?
        if let coverImageName = exportPackage.book.coverImageName,
           let imageData = imageDataMap[coverImageName] {
            coverImageData = imageData
        }
        
        let book = Book(
            id: bookID,
            name: bookName,
            bookDescription: exportPackage.book.bookDescription,
            coverImageData: coverImageData,
            coverImageName: exportPackage.book.coverImageName,
            color: exportPackage.book.color,
            recipeIDs: importedRecipeIDs,
            dateCreated: createNewID ? Date() : exportPackage.book.dateCreated,
            dateModified: Date(),
            isImported: true
        )
        
        modelContext.insert(book)
        
        return (book: book, newRecipes: newRecipes, updatedRecipes: updatedRecipes, images: imagesImported)
    }
    
    private func performMergeImport(
        exportPackage: BookExportPackage,
        url: URL,
        existingBook: Book,
        modelContext: ModelContext
    ) async throws -> (newRecipes: Int, updatedRecipes: Int, images: Int) {
        // Extract to temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeBookImport_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        do {
            try RecipeBookExportService.extractZipArchive(from: url, to: tempDir)
        } catch {
            throw ImportError.extractionFailed(error)
        }
        
        // Load images from archive into memory
        let imageDataMap = try loadImagesFromArchive(from: tempDir, manifest: exportPackage.imageManifest)
        
        // Import/update recipes
        var newRecipes = 0
        var updatedRecipes = 0
        var imagesImported = 0
        
        for recipeModel in exportPackage.recipes {
            let result = try await importOrUpdateRecipe(
                recipeModel,
                imageDataMap: imageDataMap,
                modelContext: modelContext,
                createNewID: false
            )
            
            imagesImported += result.imagesAssigned
            
            // Add to book if not already there
            if let recipeIDs = existingBook.recipeIDs, !recipeIDs.contains(result.recipeID) {
                existingBook.addRecipe(result.recipeID)
            } else if existingBook.recipeIDs == nil {
                existingBook.addRecipe(result.recipeID)
            }
            
            if result.wasNew {
                newRecipes += 1
            } else {
                updatedRecipes += 1
            }
        }
        
        existingBook.dateModified = Date()
        
        return (newRecipes: newRecipes, updatedRecipes: updatedRecipes, images: imagesImported)
    }
    
    private func importOrUpdateRecipe(
        _ recipeModel: ExportableRecipe,
        imageDataMap: [String: Data],
        modelContext: ModelContext,
        createNewID: Bool
    ) async throws -> (recipeID: UUID, wasNew: Bool, imagesAssigned: Int) {
        let recipeID = createNewID ? UUID() : recipeModel.id
        
        // Check if recipe exists
        let descriptor = FetchDescriptor<RecipeX>(
            predicate: #Predicate { recipe in
                recipe.id == recipeID
            }
        )
        
        let existingRecipes = try modelContext.fetch(descriptor)
        
        if let existingRecipe = existingRecipes.first, !createNewID {
            // Update existing recipe
            let imagesAssigned = try updateRecipe(existingRecipe, with: recipeModel, imageDataMap: imageDataMap)
            return (recipeID: recipeID, wasNew: false, imagesAssigned: imagesAssigned)
        } else {
            // Create new recipe
            let encoder = JSONEncoder()
            
            let ingredientSectionsData = try encoder.encode(recipeModel.ingredientSections)
            let instructionSectionsData = try encoder.encode(recipeModel.instructionSections)
            let notesData = try encoder.encode(recipeModel.notes)
            
            var imagesAssigned = 0
            
            // Assign main image data
            var mainImageData: Data?
            var mainImageName: String?
            if let imageName = recipeModel.imageName,
               let imageData = imageDataMap[imageName] {
                mainImageData = imageData
                mainImageName = createNewID ? "\(recipeID.uuidString).jpg" : imageName
                imagesAssigned += 1
                AppLog.debug("Assigned main image data (\(imageData.count / 1024)KB) to recipe: \(recipeModel.title)", category: .batch)
            }
            
            // Assign additional images data
            var additionalImagesData: Data?
            var additionalImageNames: [String]?
            if let additionalNames = recipeModel.additionalImageNames, !additionalNames.isEmpty {
                var additionalImages: [[String: Data]] = []
                var newAdditionalNames: [String] = []
                
                for (index, imageName) in additionalNames.enumerated() {
                    if let imageData = imageDataMap[imageName] {
                        let newImageName = createNewID ? "\(recipeID.uuidString)_\(index).jpg" : imageName
                        additionalImages.append(["data": imageData, "name": Data(newImageName.utf8)])
                        newAdditionalNames.append(newImageName)
                        imagesAssigned += 1
                    }
                }
                
                if !additionalImages.isEmpty {
                    additionalImagesData = try? encoder.encode(additionalImages)
                    additionalImageNames = newAdditionalNames
                    AppLog.debug("Assigned \(additionalImages.count) additional images to recipe: \(recipeModel.title)", category: .batch)
                }
            }
            
            let newRecipe = RecipeX(
                id: recipeID,
                title: recipeModel.title,
                headerNotes: recipeModel.headerNotes,
                recipeYield: recipeModel.yield,
                reference: recipeModel.reference,
                ingredientSectionsData: ingredientSectionsData,
                instructionSectionsData: instructionSectionsData,
                notesData: notesData,
                imageData: mainImageData,
                additionalImagesData: additionalImagesData,
                imageName: mainImageName,
                additionalImageNames: additionalImageNames
            )
            
            modelContext.insert(newRecipe)
            
            return (recipeID: recipeID, wasNew: true, imagesAssigned: imagesAssigned)
        }
    }
    
    private func updateRecipe(_ recipe: RecipeX, with model: ExportableRecipe, imageDataMap: [String: Data]) throws -> Int {
        let encoder = JSONEncoder()
        var imagesAssigned = 0
        
        // Update structured data
        if let ingredientSectionsData = try? encoder.encode(model.ingredientSections) {
            recipe.ingredientSectionsData = ingredientSectionsData
        }
        
        if let instructionSectionsData = try? encoder.encode(model.instructionSections) {
            recipe.instructionSectionsData = instructionSectionsData
        }
        
        if let notesData = try? encoder.encode(model.notes) {
            recipe.notesData = notesData
        }
        
        // Update metadata
        recipe.title = model.title
        recipe.headerNotes = model.headerNotes
        recipe.recipeYield = model.yield
        recipe.reference = model.reference
        
        // Update images (both filename and data)
        if let imageName = model.imageName {
            recipe.imageName = imageName
            
            // Also update the image data from the map
            if let imageData = imageDataMap[imageName] {
                recipe.imageData = imageData
                imagesAssigned += 1
                AppLog.debug("Updated main image data (\(imageData.count / 1024)KB) for recipe: \(recipe.title ?? "Untitled")", category: .batch)
            }
        }
        
        if let additionalImages = model.additionalImageNames, !additionalImages.isEmpty {
            recipe.additionalImageNames = additionalImages
            
            // Also update the additional images data from the map
            var additionalImagesData: [[String: Data]] = []
            
            for imageName in additionalImages {
                if let imageData = imageDataMap[imageName] {
                    additionalImagesData.append(["data": imageData, "name": Data(imageName.utf8)])
                    imagesAssigned += 1
                }
            }
            
            if !additionalImagesData.isEmpty {
                if let encoded = try? encoder.encode(additionalImagesData) {
                    recipe.additionalImagesData = encoded
                    AppLog.debug("Updated \(additionalImagesData.count) additional images for recipe: \(recipe.title ?? "Untitled")", category: .batch)
                }
            }
        }
        
        // Update version tracking
        recipe.version = (recipe.version ?? 1) + 1
        recipe.lastModified = Date()
        
        return imagesAssigned
    }
    
    /// Loads images from the export archive into memory as a dictionary
    /// Maps filename -> image Data for assignment to recipes during import
    private func loadImagesFromArchive(from directory: URL, manifest: [ImageManifestEntry]) throws -> [String: Data] {
        var imageDataMap: [String: Data] = [:]
        
        for entry in manifest {
            let sourceURL = directory.appendingPathComponent(entry.fileName)
            
            // Load image data from archive
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                do {
                    let imageData = try Data(contentsOf: sourceURL)
                    imageDataMap[entry.fileName] = imageData
                    AppLog.debug("Loaded image data: \(entry.fileName) (\(imageData.count / 1024)KB)", category: .batch)
                } catch {
                    AppLog.warning("Failed to load image \(entry.fileName): \(error)", category: .batch)
                }
            } else {
                AppLog.warning("Source image not found: \(entry.fileName)", category: .batch)
            }
        }
        
        AppLog.info("Loaded \(imageDataMap.count) images from archive", category: .batch)
        return imageDataMap
    }
    
    private func isSupportedVersion(_ version: String) -> Bool {
        // Support versions 1.0 through 2.x
        let components = version.split(separator: ".").compactMap { Int($0) }
        guard let major = components.first else { return false }
        return major <= 2
    }
}

// MARK: - Legacy Type Aliases

/// Legacy type aliases for backward compatibility with existing code
/// These allow code using the old names to continue working

//typealias RecipeBookExportPackage = RecipeBookImportService.BookExportPackage
//typealias RecipeBookImportMode = RecipeBookImportService.BookImportMode
typealias RecipeBookImportResult = RecipeBookImportService.BookImportResult
typealias RecipeBookImportError = RecipeBookImportService.ImportError

//// Export types at module level for convenience
//typealias BookExportPackage = RecipeBookImportService.BookExportPackage
//typealias ExportableBook = RecipeBookImportService.ExportableBook
//typealias ExportableRecipe = RecipeBookImportService.ExportableRecipe
//typealias ImageManifestEntry = RecipeBookImportService.ImageManifestEntry
//typealias ImageManifestType = RecipeBookImportService.ImageManifestType
//typealias BookImportMode = RecipeBookImportService.BookImportMode
//typealias BookImportResult = RecipeBookImportService.BookImportResult

