//
//  RecipeBackupManager.swift
//  Reczipes2
//
//  Created by Xcode Assistant on 12/20/25.
//

import Foundation
import SwiftData
import UIKit

enum RecipeBackupError: LocalizedError {
    case noRecipesToBackup
    case fileCreationFailed
    case encodingFailed(Error)
    case decodingFailed(Error)
    case imageLoadFailed(String)
    case invalidBackupFile
    case importFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .noRecipesToBackup:
            return "No recipes available to backup"
        case .fileCreationFailed:
            return "Failed to create backup file"
        case .encodingFailed(let error):
            return "Failed to encode recipes: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode backup file: \(error.localizedDescription)"
        case .imageLoadFailed(let name):
            return "Failed to load image: \(name)"
        case .invalidBackupFile:
            return "Invalid or corrupted backup file"
        case .importFailed(let error):
            return "Failed to import recipes: \(error.localizedDescription)"
        }
    }
}

struct RecipeImportResult {
    let newRecipes: Int
    let updatedRecipes: Int
    let skippedRecipes: Int
    let totalRecipes: Int
    
    var summary: String {
        var parts: [String] = []
        if newRecipes > 0 {
            parts.append("\(newRecipes) new")
        }
        if updatedRecipes > 0 {
            parts.append("\(updatedRecipes) updated")
        }
        if skippedRecipes > 0 {
            parts.append("\(skippedRecipes) skipped")
        }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
}

struct BackupFileInfo: Identifiable {
    let id: String
    let url: URL
    let fileName: String
    let fileSize: Int
    let creationDate: Date
    let modificationDate: Date
    
    init(url: URL, fileName: String, fileSize: Int, creationDate: Date, modificationDate: Date) {
        self.url = url
        self.fileName = fileName
        self.fileSize = fileSize
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.id = url.path // Use the file path as the unique identifier
    }
    
    var displayName: String {
        // Remove "RecipeBackup_" prefix and ".reczipes" extension
        var name = fileName
        if name.hasPrefix("RecipeBackup_") {
            name = String(name.dropFirst("RecipeBackup_".count))
        }
        if name.hasSuffix(".reczipes") {
            name = String(name.dropLast(".reczipes".count))
        }
        
        // Optionally clean up the milliseconds suffix (e.g., "_123") for cleaner display
        // Pattern: ends with underscore and 3 digits
        if let range = name.ranges(of: #/_\d{3}$/#).first {
            name.removeSubrange(range)
        }
        
        return name
    }
    
    var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }
}

@MainActor
class RecipeBackupManager {
    static let shared = RecipeBackupManager()
    
    private init() {}
    
    // MARK: - Export
    
    /// Creates a backup package of all recipes with their images
    func createBackup(from recipes: [RecipeX]) async throws -> URL {
        guard !recipes.isEmpty else {
            throw RecipeBackupError.noRecipesToBackup
        }
        
        AppLog.info("Starting backup of \(recipes.count) recipe(s)", category: .backup)
        
        var recipeBackups: [RecipeBackup] = []
        _ = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        for recipe in recipes {
            
            // Load main image if exists
            var mainImageBackup: RecipeBackup.ImageBackup?
            
            // UPDATED: Priority 1 - Try SwiftData imageData (current system)
            if let imageData = recipe.imageData {
                let fileName = recipe.imageName ?? "image_\(UUID().uuidString).jpg"
                mainImageBackup = RecipeBackup.ImageBackup(fileName: fileName, imageData: imageData)
                AppLog.debug("Loaded main image from SwiftData for '\(String(describing: recipe.title))'", category: .backup)
            }
            
            // Load additional images if exist
            var additionalImageBackups: [RecipeBackup.ImageBackup]?
            
            // UPDATED: Priority 1 - Try SwiftData additionalImagesData (current system)
            if let additionalImagesData = recipe.additionalImagesData,
               let decodedImages = try? JSONDecoder().decode([Data].self, from: additionalImagesData) {
                var imageBackups: [RecipeBackup.ImageBackup] = []
                for (index, imageData) in decodedImages.enumerated() {
                    let fileName = "additional_\(index)_\(UUID().uuidString).jpg"
                    imageBackups.append(RecipeBackup.ImageBackup(fileName: fileName, imageData: imageData))
                    AppLog.debug("Loaded additional image \(index) from SwiftData for '\(String(describing: recipe.title))'", category: .backup)
                }
                if !imageBackups.isEmpty {
                    additionalImageBackups = imageBackups
                }
            }
            
            
            // Convert RecipeX to RecipeData for backup
            let recipeData = RecipeData(from: recipe)
            
            let backup = RecipeBackup(
                recipe: recipeData,
                dateAdded: recipe.dateAdded ?? Date(),
                mainImage: mainImageBackup,
                additionalImages: additionalImageBackups
            )
            
            recipeBackups.append(backup)
        }
        
        let package = RecipeBackupPackage(recipes: recipeBackups)
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData: Data
        do {
            jsonData = try encoder.encode(package)
        } catch {
            AppLog.error("Failed to encode backup: \(error)", category: .backup)
            throw RecipeBackupError.encodingFailed(error)
        }
        
        // Use the helper method to save the backup file
        return try await saveBackupFile(jsonData: jsonData, prefix: "RecipeBackup")
    }
    
    // MARK: - List Backups
    
    /// Lists all available backup files in the Reczipes2 folder
    func listAvailableBackups() throws -> [BackupFileInfo] {
        // Use the same directory resolution logic as createBackup
        let reczipesDirectory = getBackupDirectory()
        
        // Check if directory exists
        guard FileManager.default.fileExists(atPath: reczipesDirectory.path) else {
            return []
        }
        
        // Get all .reczipes files
        let contents = try FileManager.default.contentsOfDirectory(
            at: reczipesDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        
        let backupFiles = contents.filter { $0.pathExtension == "reczipes" }
        
        // Create BackupFileInfo for each file
        var backupInfos: [BackupFileInfo] = []
        
        for fileURL in backupFiles {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
                
                let fileSize = resourceValues.fileSize ?? 0
                let creationDate = resourceValues.creationDate ?? Date()
                let modificationDate = resourceValues.contentModificationDate ?? Date()
                
                let info = BackupFileInfo(
                    url: fileURL,
                    fileName: fileURL.lastPathComponent,
                    fileSize: fileSize,
                    creationDate: creationDate,
                    modificationDate: modificationDate
                )
                
                backupInfos.append(info)
            } catch {
                AppLog.warning("Could not read attributes for backup file: \(fileURL.lastPathComponent)", category: .backup)
            }
        }
        
        // Sort by modification date (most recent first)
        backupInfos.sort { $0.modificationDate > $1.modificationDate }
        
        return backupInfos
    }
    
    // MARK: - Import
    
    /// Imports recipes from a backup file
    func importBackup(
        from url: URL,
        into modelContext: ModelContext,
        existingRecipes: [RecipeX],
        overwriteMode: ImportOverwriteMode
    ) async throws -> RecipeImportResult {
        AppLog.info("Starting import from \(url.lastPathComponent)", category: .backup)
        
        // Read and decode the backup file
        let jsonData: Data
        do {
            jsonData = try Data(contentsOf: url)
        } catch {
            AppLog.error("Failed to read backup file: \(error)", category: .backup)
            throw RecipeBackupError.invalidBackupFile
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64 // Explicitly decode base64 Data
        
        let package: RecipeBackupPackage
        do {
            package = try decoder.decode(RecipeBackupPackage.self, from: jsonData)
        } catch {
            AppLog.error("Failed to decode backup file: \(error)", category: .backup)
            throw RecipeBackupError.decodingFailed(error)
        }
        
        AppLog.info("Backup package version \(package.version), exported \(package.exportDate), contains \(package.recipeCount) recipe(s)", category: .backup)
        
        var newCount = 0
        var updatedCount = 0
        let skippedCount = 0
        
        _ = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        for recipeBackup in package.recipes {
            let recipeData = recipeBackup.recipe
            
            // Convert RecipeData to RecipeX
            let recipe = recipeData.toRecipeX()
            
            // Check if recipe already exists
            let existingRecipe = existingRecipes.first { $0.id == recipe.id }
            
            if let existing = existingRecipe {
                AppLog.info("Overwriting existing recipe '\(recipe.safeTitle)'", category: .backup)
                // Delete the existing recipe (images will be overwritten)
                modelContext.delete(existing)
                updatedCount += 1
            } else {
                newCount += 1
            }
            
            // Restore images from backup
            if let mainImage = recipeBackup.mainImage {
                recipe.imageData = mainImage.imageData
                recipe.imageName = mainImage.fileName
                recipe.imageHash = RecipeX.calculateImageHash(from: mainImage.imageData)
                AppLog.debug("Set main image data for '\(recipe.safeTitle)'", category: .backup)
            }
            
            if let additionalImages = recipeBackup.additionalImages, !additionalImages.isEmpty {
                // Store additional images as JSON array of dictionaries
                var additionalImagesArray: [[String: Data]] = []
                for (index, imageBackup) in additionalImages.enumerated() {
                    let imageName = "additional_\(index)_\(recipe.safeID.uuidString).jpg"
                    additionalImagesArray.append([
                        "data": imageBackup.imageData,
                        "name": Data(imageName.utf8)
                    ])
                }
                recipe.additionalImagesData = try? JSONEncoder().encode(additionalImagesArray)
                AppLog.debug("Set additional images data for '\(recipe.safeTitle)'", category: .backup)
            }
            
            modelContext.insert(recipe)
            AppLog.debug("Imported recipe '\(recipe.safeTitle)'", category: .backup)
        }
        
        // Save the context
        do {
            try modelContext.save()
            AppLog.info("Import completed: \(newCount) new, \(updatedCount) updated, \(skippedCount) skipped", category: .backup)
        } catch {
            AppLog.error("Failed to save imported recipes: \(error)", category: .backup)
            throw RecipeBackupError.importFailed(error)
        }
        
        return RecipeImportResult(
            newRecipes: newCount,
            updatedRecipes: updatedCount,
            skippedRecipes: skippedCount,
            totalRecipes: package.recipeCount
        )
    }
    
    // MARK: - RecipeX Export (NEW UNIFIED MODEL)
    
    /// Creates a backup package of RecipeX models with their images
    func createBackupX(from recipes: [RecipeX]) async throws -> URL {
        guard !recipes.isEmpty else {
            throw RecipeBackupError.noRecipesToBackup
        }
        
        AppLog.info("Starting RecipeX backup of \(recipes.count) recipe(s)", category: .backup)
        
        var recipeBackups: [RecipeBackup] = []
        
        for recipe in recipes {
            // Load main image if exists
            var mainImageBackup: RecipeBackup.ImageBackup?
            if let imageData = recipe.imageData {
                let fileName = recipe.imageName ?? "image_\(recipe.safeID.uuidString).jpg"
                mainImageBackup = RecipeBackup.ImageBackup(fileName: fileName, imageData: imageData)
                AppLog.debug("Loaded main image from SwiftData for '\(recipe.safeTitle)'", category: .backup)
            }
            
            // Load additional images if exist
            var additionalImageBackups: [RecipeBackup.ImageBackup]?
            if let additionalImagesData = recipe.additionalImagesData,
               let imageArray = try? JSONDecoder().decode([[String: Data]].self, from: additionalImagesData) {
                var imageBackups: [RecipeBackup.ImageBackup] = []
                for (index, imageDict) in imageArray.enumerated() {
                    if let imageData = imageDict["data"] {
                        let fileName = "additional_\(index)_\(recipe.safeID.uuidString).jpg"
                        imageBackups.append(RecipeBackup.ImageBackup(fileName: fileName, imageData: imageData))
                        AppLog.debug("Loaded additional image \(index) from SwiftData for '\(recipe.safeTitle)'", category: .backup)
                    }
                }
                if !imageBackups.isEmpty {
                    additionalImageBackups = imageBackups
                }
            }
            
            // Convert RecipeX to RecipeData for backup
            let recipeData = RecipeData(from: recipe)
            
            // DEBUG: Log what's in RecipeData before encoding
            AppLog.debug("RecipeData created for '\(recipe.safeTitle)':", category: .backup)
            AppLog.debug("  - id: \(recipeData.id?.uuidString ?? "nil")", category: .backup)
            AppLog.debug("  - title: \(recipeData.title ?? "nil")", category: .backup)
            AppLog.debug("  - ingredientSectionsData: \(recipeData.ingredientSectionsData != nil ? "\(recipeData.ingredientSectionsData!.count) bytes" : "nil")", category: .backup)
            AppLog.debug("  - instructionSectionsData: \(recipeData.instructionSectionsData != nil ? "\(recipeData.instructionSectionsData!.count) bytes" : "nil")", category: .backup)
            AppLog.debug("  - notesData: \(recipeData.notesData != nil ? "\(recipeData.notesData!.count) bytes" : "nil")", category: .backup)
            
            let backup = RecipeBackup(
                recipe: recipeData,
                dateAdded: recipe.dateAdded ?? Date(),
                mainImage: mainImageBackup,
                additionalImages: additionalImageBackups
            )
            
            // DEBUG: Try to encode just the RecipeData to see if it works
            do {
                let testEncoder = JSONEncoder()
                testEncoder.dataEncodingStrategy = .base64
                let testData = try testEncoder.encode(recipeData)
                AppLog.debug("  - RecipeData encodes successfully: \(testData.count) bytes", category: .backup)
            } catch {
                AppLog.error("  - FAILED to encode RecipeData: \(error)", category: .backup)
            }
            
            recipeBackups.append(backup)
        }
        
        let package = RecipeBackupPackage(recipes: recipeBackups)
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64 // Explicitly encode Data as base64
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData: Data
        do {
            jsonData = try encoder.encode(package)
        } catch {
            AppLog.error("Failed to encode RecipeX backup: \(error)", category: .backup)
            throw RecipeBackupError.encodingFailed(error)
        }
        
        // Save backup file (same logic as Recipe backup)
        return try await saveBackupFile(jsonData: jsonData, prefix: "RecipeXBackup")
    }
    
    // MARK: - RecipeX Import (NEW UNIFIED MODEL)
    
    /// Imports recipes from a backup file as RecipeX models (with CloudKit sync)
    func importBackupX(
        from url: URL,
        into modelContext: ModelContext,
        existingRecipes: [RecipeX],
        overwriteMode: ImportOverwriteMode
    ) async throws -> RecipeImportResult {
        AppLog.info("Starting RecipeX import from \(url.lastPathComponent)", category: .backup)
        
        // Read and decode the backup file
        let jsonData: Data
        do {
            jsonData = try Data(contentsOf: url)
        } catch {
            AppLog.error("Failed to read backup file: \(error)", category: .backup)
            throw RecipeBackupError.invalidBackupFile
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64 // Explicitly decode base64 Data
        
        let package: RecipeBackupPackage
        do {
            package = try decoder.decode(RecipeBackupPackage.self, from: jsonData)
        } catch {
            AppLog.error("Failed to decode backup file: \(error)", category: .backup)
            throw RecipeBackupError.decodingFailed(error)
        }
        
        AppLog.info("Backup package version \(package.version), exported \(package.exportDate), contains \(package.recipeCount) recipe(s)", category: .backup)
        
        var newCount = 0
        var updatedCount = 0
        let skippedCount = 0
        
        for recipeBackup in package.recipes {
            let recipeData = recipeBackup.recipe
            
            // Convert RecipeData to RecipeX - this properly sets ALL properties including ingredientSectionsData, instructionSectionsData, notesData
            let recipe = recipeData.toRecipeX()
            
            // Check if recipe already exists
            let existingRecipe = existingRecipes.first { $0.id == recipe.id }
            
            if let existing = existingRecipe {
                switch overwriteMode {
                    
                default:
                    AppLog.info("Overwriting existing RecipeX '\(recipe.safeTitle)'", category: .backup)
                    modelContext.delete(existing)
                    updatedCount += 1
                    
                }
            } else {
                newCount += 1
            }
            
            // Use the already-converted recipe (it has all the data!)
            // Just update CloudKit and timestamp properties
            
            // Handle ID for overwrite mode
            if existingRecipe != nil {
                recipe.id = UUID() // Generate new ID if overwriting
            }
            
            // Initialize CloudKit sync properties
            recipe.needsCloudSync = true
            recipe.syncRetryCount = 0
            recipe.lastSyncError = nil
            recipe.cloudRecordID = nil
            recipe.lastSyncedToCloud = nil
            
            // Set extraction source
            recipe.extractionSource = "import"
            
            // Set timestamps
            let now = Date()
            recipe.dateAdded = recipeBackup.dateAdded
            recipe.dateCreated = now
            recipe.lastModified = now
            
            // Set initial version
            recipe.version = 1
            
            // Set device identifier
            recipe.lastModifiedDeviceID = UIDevice.current.identifierForVendor?.uuidString
            
            // Restore images to SwiftData (these aren't in RecipeData, they're in RecipeBackup)
            if let mainImage = recipeBackup.mainImage {
                recipe.imageData = mainImage.imageData
                recipe.imageName = mainImage.fileName
                recipe.imageHash = RecipeX.calculateImageHash(from: mainImage.imageData)
                AppLog.debug("Set main image data for RecipeX '\(recipe.safeTitle)'", category: .backup)
            }
            
            if let additionalImages = recipeBackup.additionalImages, !additionalImages.isEmpty {
                // Store additional images as JSON array of dictionaries
                var additionalImagesArray: [[String: Data]] = []
                for (index, imageBackup) in additionalImages.enumerated() {
                    let imageName = "additional_\(index)_\(recipe.safeID.uuidString).jpg"
                    additionalImagesArray.append([
                        "data": imageBackup.imageData,
                        "name": Data(imageName.utf8)
                    ])
                }
                recipe.additionalImagesData = try? JSONEncoder().encode(additionalImagesArray)
                AppLog.debug("Set additional images data for RecipeX '\(recipe.safeTitle)'", category: .backup)
            }
            
            // Calculate content fingerprint for duplicate detection
            recipe.updateContentFingerprint()
            
            modelContext.insert(recipe)
            AppLog.debug("Imported RecipeX '\(recipe.safeTitle)' with CloudKit sync enabled", category: .backup)
        }
        
        // Save the context
        do {
            try modelContext.save()
            AppLog.info("RecipeX import completed: \(newCount) new, \(updatedCount) updated, \(skippedCount) skipped", category: .backup)
        } catch {
            AppLog.error("Failed to save imported RecipeX recipes: \(error)", category: .backup)
            throw RecipeBackupError.importFailed(error)
        }
        
        return RecipeImportResult(
            newRecipes: newCount,
            updatedRecipes: updatedCount,
            skippedRecipes: skippedCount,
            totalRecipes: package.recipeCount
        )
    }
    
    
    
    // MARK: - Helper Methods
    
    /// Gets the backup directory, with fallback logic for test environments
    private func getBackupDirectory() -> URL {
        return getBackupDirectoryShared()
    }
    
    /// Shared method to get the backup directory (accessible to BookBackupManager)
    func getBackupDirectoryShared() -> URL {
        // First, try to verify Documents directory exists and is accessible
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Verify we can actually access the documents directory
        var isDir: ObjCBool = false
        let docsExists = FileManager.default.fileExists(atPath: documentsDirectory.path, isDirectory: &isDir)
        
        if docsExists && isDir.boolValue {
            // Documents exists, use it
            return documentsDirectory.appendingPathComponent("Reczipes2")
        } else {
            // Documents doesn't exist or isn't accessible - use temporary directory
            // This is common in test environments with in-memory containers
            let tmpDirectory = FileManager.default.temporaryDirectory
            return tmpDirectory.appendingPathComponent("Reczipes2")
        }
    }
    
    /// Saves backup data to a file with the given prefix and extension
    private func saveBackupFile(jsonData: Data, prefix: String, fileExtension: String = "reczipes") async throws -> URL {
        // Get backup directory using shared logic
        var reczipesDirectory = getBackupDirectory()
        
        // Try to create the backup directory
        do {
            try FileManager.default.createDirectory(at: reczipesDirectory, withIntermediateDirectories: true, attributes: nil)
            AppLog.debug("Backup directory ready at: \(reczipesDirectory.path)", category: .backup)
        } catch let error as NSError {
            AppLog.error("Failed to create backup directory: \(error) (domain: \(error.domain), code: \(error.code))", category: .backup)
            
            // Final fallback - just use temp directory root
            AppLog.warning("Using fallback: temporary directory root", category: .backup)
            reczipesDirectory = FileManager.default.temporaryDirectory
        }
        
        // Create backup file in Reczipes2 folder
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let currentDate = Date()
        let dateString = dateFormatter.string(from: currentDate)
        
        // Add milliseconds to ensure uniqueness when creating multiple backups quickly
        let milliseconds = Int((currentDate.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)
        let fileName = "\(prefix)_\(dateString)_\(String(format: "%03d", milliseconds)).\(fileExtension)"
        let fileURL = reczipesDirectory.appendingPathComponent(fileName)
        
        do {
            try jsonData.write(to: fileURL)
            AppLog.info("Backup created successfully: \(fileName) (\(jsonData.count) bytes) at \(fileURL.path)", category: .backup)
            return fileURL
        } catch {
            AppLog.error("Failed to write backup file: \(error)", category: .backup)
            throw RecipeBackupError.fileCreationFailed
        }
    }
}

enum ImportOverwriteMode {
    case overwrite     // Replace existing recipes with imported ones
}

// MARK: - Book Backup Support (NEW)

/// Backup package for Book models (unified, CloudKit-compatible)
struct BookBackupPackage: Codable {
    let version: String
    let exportDate: Date
    let books: [BookBackup]
    
    var bookCount: Int { books.count }
    
    init(books: [BookBackup], exportDate: Date = Date()) {
        self.version = "1.0"
        self.books = books
        self.exportDate = exportDate
    }
}

/// Represents a single Book with its metadata
struct BookBackup: Codable {
    let id: UUID
    let name: String
    let bookDescription: String?
    let coverImageFileName: String?
    let coverImageData: Data?
    let dateCreated: Date
    let dateModified: Date?
    let recipeIDs: [UUID]
    let color: String?
    let isShared: Bool
    let cloudRecordID: String?
    
    init(from book: Book) {
        self.id = book.id ?? UUID()
        self.name = book.name ?? "Untitled Book"
        self.bookDescription = book.bookDescription
        self.coverImageFileName = book.coverImageName
        self.coverImageData = book.coverImageData
        self.dateCreated = book.dateCreated ?? Date()
        self.dateModified = book.dateModified
        self.recipeIDs = book.recipeIDs ?? []
        self.color = book.color
        self.isShared = book.isShared ?? false
        self.cloudRecordID = book.cloudRecordID
    }
    
    init(
        id: UUID,
        name: String,
        bookDescription: String?,
        coverImageFileName: String?,
        coverImageData: Data?,
        dateCreated: Date,
        dateModified: Date?,
        recipeIDs: [UUID],
        color: String?,
        isShared: Bool,
        cloudRecordID: String?
    ) {
        self.id = id
        self.name = name
        self.bookDescription = bookDescription
        self.coverImageFileName = coverImageFileName
        self.coverImageData = coverImageData
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.recipeIDs = recipeIDs
        self.color = color
        self.isShared = isShared
        self.cloudRecordID = cloudRecordID
    }
}

/// Book import result information
struct BookImportResult_RBM {
    let newBooks: Int
    let updatedBooks: Int
    let skippedBooks: Int
    let totalBooks: Int
    
    var summary: String {
        var parts: [String] = []
        if newBooks > 0 {
            parts.append("\(newBooks) new")
        }
        if updatedBooks > 0 {
            parts.append("\(updatedBooks) updated")
        }
        if skippedBooks > 0 {
            parts.append("\(skippedBooks) skipped")
        }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
}

@MainActor
class BookBackupManager {
    static let shared = BookBackupManager()
    
    private init() {}
    
    // MARK: - Export
    
    /// Creates a backup package of Book models
    func createBackup(from books: [Book]) async throws -> URL {
        guard !books.isEmpty else {
            throw RecipeBackupError.noRecipesToBackup
        }
        
        AppLog.info("Starting Book backup of \(books.count) book(s)", category: .backup)
        
        var bookBackups: [BookBackup] = []
        
        for book in books {
            let backup = BookBackup(from: book)
            bookBackups.append(backup)
            
            let recipeCount = book.recipeIDs?.count ?? 0
            let imageSizeKB = (book.coverImageData?.count ?? 0) / 1024
            AppLog.debug("Prepared book '\(book.name ?? "Untitled")' with \(recipeCount) recipes, cover image: \(imageSizeKB)KB", category: .backup)
        }
        
        let package = BookBackupPackage(books: bookBackups)
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData: Data
        do {
            jsonData = try encoder.encode(package)
        } catch {
            AppLog.error("Failed to encode Book backup: \(error)", category: .backup)
            throw RecipeBackupError.encodingFailed(error)
        }
        
        // Save to file with .bookbackup extension
        let url = try await saveBookBackupFile(jsonData: jsonData, prefix: "BookBackup")
        AppLog.info("Book backup created successfully: \(url.lastPathComponent) (\(jsonData.count) bytes)", category: .backup)
        
        return url
    }
    
    // MARK: - Import
    
    /// Imports Book models from a backup file
    func importBackup(
        from url: URL,
        into modelContext: ModelContext,
        existingBooks: [Book],
        overwriteMode: ImportOverwriteMode
    ) async throws -> BookImportResult_RBM {
        AppLog.info("Starting Book import from \(url.lastPathComponent)", category: .backup)
        
        // Read and decode the backup file
        let jsonData: Data
        do {
            jsonData = try Data(contentsOf: url)
        } catch {
            AppLog.error("Failed to read backup file: \(error)", category: .backup)
            throw RecipeBackupError.invalidBackupFile
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let package: BookBackupPackage
        do {
            package = try decoder.decode(BookBackupPackage.self, from: jsonData)
        } catch {
            AppLog.error("Failed to decode backup file: \(error)", category: .backup)
            throw RecipeBackupError.decodingFailed(error)
        }
        
        AppLog.info("Backup package version \(package.version), exported \(package.exportDate), contains \(package.bookCount) book(s)", category: .backup)
        
        var newCount = 0
        var updatedCount = 0
        let skippedCount = 0
        
        for bookBackup in package.books {
            // Check if book already exists
            let existingBook = existingBooks.first { $0.id == bookBackup.id }
            
            if let existing = existingBook {
                switch overwriteMode {
                    
                case .overwrite:
                    AppLog.info("Overwriting existing Book '\(bookBackup.name)'", category: .backup)
                    modelContext.delete(existing)
                    updatedCount += 1
                }

            } else {
                newCount += 1
            }
            
            // Create Book instance
            var bookToImport = bookBackup
            
            // Handle keep both mode - create new ID
            if existingBook != nil {
                bookToImport = BookBackup(
                    id: UUID(), // New ID
                    name: bookBackup.name,
                    bookDescription: bookBackup.bookDescription,
                    coverImageFileName: bookBackup.coverImageFileName,
                    coverImageData: bookBackup.coverImageData,
                    dateCreated: Date(), // New creation date
                    dateModified: Date(),
                    recipeIDs: bookBackup.recipeIDs,
                    color: bookBackup.color,
                    isShared: bookBackup.isShared,
                    cloudRecordID: nil // Clear CloudKit record for new copy
                )
            }
            
            // Create new Book from backup
            let newBook = Book(
                id: bookToImport.id,
                name: bookToImport.name,
                bookDescription: bookToImport.bookDescription,
                dateCreated: bookToImport.dateCreated,
                dateModified: bookToImport.dateModified ?? Date(),
                recipeIDs: bookToImport.recipeIDs,
                color: bookToImport.color
            )
            
            // Set cover image data
            if let coverImageData = bookToImport.coverImageData {
                newBook.coverImageData = coverImageData
                newBook.coverImageName = bookToImport.coverImageFileName
                AppLog.debug("Set cover image data (\(coverImageData.count / 1024)KB) for '\(bookToImport.name)'", category: .backup)
            }
            
            // Set CloudKit properties
            newBook.isShared = bookToImport.isShared
            newBook.cloudRecordID = bookToImport.cloudRecordID
            
            // Initialize sync properties for imported books
            newBook.needsCloudSync = true
            newBook.syncRetryCount = 0
            newBook.lastSyncError = nil
            newBook.lastSyncedToCloud = nil
            
            modelContext.insert(newBook)
            AppLog.debug("Imported Book '\(bookToImport.name)' with \(bookToImport.recipeIDs.count) recipes", category: .backup)
        }
        
        // Save the context
        do {
            try modelContext.save()
            AppLog.info("Book import completed: \(newCount) new, \(updatedCount) updated, \(skippedCount) skipped", category: .backup)
        } catch {
            AppLog.error("Failed to save imported Books: \(error)", category: .backup)
            throw RecipeBackupError.importFailed(error)
        }
        
        return BookImportResult_RBM(
            newBooks: newCount,
            updatedBooks: updatedCount,
            skippedBooks: skippedCount,
            totalBooks: package.bookCount
        )
    }
    
    // MARK: - Helper Methods
    
    /// Saves book backup data to a file with .bookbackup extension
    private func saveBookBackupFile(jsonData: Data, prefix: String) async throws -> URL {
        // Get backup directory using shared logic from RecipeBackupManager
        let reczipesDirectory = RecipeBackupManager.shared.getBackupDirectoryShared()
        
        // Try to create the backup directory
        do {
            try FileManager.default.createDirectory(at: reczipesDirectory, withIntermediateDirectories: true, attributes: nil)
            AppLog.debug("Backup directory ready at: \(reczipesDirectory.path)", category: .backup)
        } catch let error as NSError {
            AppLog.error("Failed to create backup directory: \(error) (domain: \(error.domain), code: \(error.code))", category: .backup)
            throw RecipeBackupError.fileCreationFailed
        }
        
        // Create backup file with .bookbackup extension
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let currentDate = Date()
        let dateString = dateFormatter.string(from: currentDate)
        
        // Add milliseconds to ensure uniqueness when creating multiple backups quickly
        let milliseconds = Int((currentDate.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)
        let fileName = "\(prefix)_\(dateString)_\(String(format: "%03d", milliseconds)).bookbackup"
        let fileURL = reczipesDirectory.appendingPathComponent(fileName)
        
        do {
            try jsonData.write(to: fileURL)
            AppLog.info("Book backup created successfully: \(fileName) (\(jsonData.count) bytes) at \(fileURL.path)", category: .backup)
            return fileURL
        } catch {
            AppLog.error("Failed to write backup file: \(error)", category: .backup)
            throw RecipeBackupError.fileCreationFailed
        }
    }
}




