//
//  BookExportImportTypes.swift
//  Reczipes2
//
//  Shared types for Book export and import operations
//  Created by Zahirudeen Premji on 01/29/26.
//

import Foundation

// MARK: - Export/Import Package

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
    /// Book content — optional with nil defaults so older packages decode and
    /// existing memberwise call sites keep compiling.
    /// Covers + interior pictures (image bytes inline)
    var images: [BookImage]? = nil
    var glossary: [BookGlossaryEntry]? = nil
    /// Contents rows (headings, recipes, pictures)
    var tableOfContents: [BookSection]? = nil
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

// MARK: - Image Manifest

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

// MARK: - Import Types

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

// MARK: - Export Types

/// Configuration for book export
struct BookExportConfiguration {
    let includeImages: Bool
    let includeMetadata: Bool
    let compressionLevel: CompressionLevel
    
    enum CompressionLevel {
        case none
        case fast
        case balanced
        case maximum
    }
    
    static let `default` = BookExportConfiguration(
        includeImages: true,
        includeMetadata: true,
        compressionLevel: .balanced
    )
}

/// Result of a book export operation
struct BookExportResult {
    let fileURL: URL
    let fileSize: Int64
    let recipeCount: Int
    let imageCount: Int
    let exportDate: Date
    
    var fileSizeMB: Double {
        Double(fileSize) / (1024.0 * 1024.0)
    }
}

// MARK: - Package Type

///// UTI type for recipe book packages
//struct RecipeBookPackageType {
//    static let identifier = "com.reczipes.recipebook"
//    static let fileExtension = "recipebook"
//    static let mimeType = "application/x-recipebook"
//    static let version = "2.0"
//}

// MARK: - Legacy Type Aliases (for backward compatibility)

/// Legacy alias for BookExportPackage
typealias RecipeBookExportPackage = BookExportPackage

/// Legacy alias for BookImportMode
typealias RecipeBookImportMode = BookImportMode

///// Legacy alias for BookImportResult
//typealias RecipeBookImportResult = BookImportResult
