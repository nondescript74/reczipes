//
//  SharedContentModels.swift
//  Reczipes2
//
//  Created on 1/15/26.
//

import Foundation
import SwiftData
import CloudKit
import SwiftUI

// MARK: - CloudKit Record Type Names

enum CloudKitRecordType {
    static let sharedRecipe = "SharedRecipe"
    static let sharedRecipeBook = "SharedRecipeBook"
    static let sharedImage = "SharedImage"
    static let sharedMeal = "SharedMeal"
}

/// Public record names derived from the item's own id, so publishing is an upsert:
/// two devices, a lost tracking row or a restore all write the same record instead of
/// adding a second public copy. Records published before this rule keep their random
/// names; readers keep the newest record per item id, so both kinds coexist.
enum PublicRecordName {
    static func recipe(_ id: UUID) -> String { "recipe-\(id.uuidString)" }
    static func book(_ id: UUID) -> String { "book-\(id.uuidString)" }
    static func meal(_ id: UUID) -> String { "meal-\(id.uuidString)" }

    static func forType(_ recordType: String, id: UUID) -> String? {
        switch recordType {
        case CloudKitRecordType.sharedRecipe: return recipe(id)
        case CloudKitRecordType.sharedRecipeBook: return book(id)
        case CloudKitRecordType.sharedMeal: return meal(id)
        default: return nil
        }
    }
}

// MARK: - Codable Representations for CloudKit

struct CloudKitRecipe: Codable, Identifiable {
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
    let sharedByUserID: String?
    let sharedByUserName: String?
    let sharedDate: Date

    // ── NEW: downloaded from the mainImage CKAsset, not part of the JSON payload ──
    /// Raw image data downloaded from CloudKit. Not Codable — set after decode.
    var imageData: Data? = nil

    // Deleted by its owner (Δ-163). The public record is kept, marked, never removed:
    // devices that already have the recipe keep it with a "User Deleted" badge, new
    // devices skip it. Inside the JSON, so no CloudKit schema change; older builds ignore it.
    var deletedByOwner: Bool? = nil
    var deletedDate: Date? = nil
    /// Set when the recipe was removed as an exact copy of another (duplicate merge):
    /// receivers drop their copy quietly when this one is still published.
    var replacedByID: UUID? = nil
    /// The owner's Diabetic-Friendly Analysis (the cached `DiabeticInfo` JSON, ISO-8601 dates),
    /// so the web shows what the app shows. A string, not a typed field: a future change to
    /// DiabeticInfo can never make a whole CloudKitRecipe fail to decode. Inside the JSON, so
    /// no CloudKit schema change; older builds ignore it.
    var diabeticInfoJSON: String? = nil
    /// The recipe in each app language other than English (JSON of [code: RecipeTranslation]),
    /// written by RecipeLocalizer, so the web shows each reader their language. A string, like
    /// diabeticInfoJSON. Inside the JSON, so no CloudKit schema change; older builds ignore it.
    var translationsJSON: String? = nil

    /// Keys to encode/decode — excludes imageData so it doesn't break the JSON round-trip.
    enum CodingKeys: String, CodingKey {
        case id, title, headerNotes, yield
        case ingredientSections, instructionSections
        case notes, reference, imageName, additionalImageNames
        case sharedByUserID, sharedByUserName, sharedDate
        case deletedByOwner, deletedDate, replacedByID
        case diabeticInfoJSON
        case translationsJSON
        // imageData intentionally omitted
    }
}

/// CloudKit-friendly representation of a recipe book for sharing
struct CloudKitRecipeBook: Codable, Identifiable {
    let id: UUID
    let name: String
    let bookDescription: String?
    let coverImageName: String?
    let recipeIDs: [UUID]
    let color: String?
    
    // Sharing metadata
    let sharedByUserID: String
    let sharedByUserName: String?
    let sharedDate: Date

    // Book content (optional; absent in books shared by older builds).
    // Read by the website — contract in Docs/BOOK_CONTENT_AND_DELETE_GUARD.md.
    /// Picture metadata, NO bytes; each image is a SharedBookPicture record (`pictureRecordName`)
    var images: [BookPictureMetadata]? = nil
    /// Contents rows (headings, recipes, pictures)
    var tableOfContents: [BookSection]? = nil
    /// Glossary (entry images stripped)
    var glossary: [BookGlossaryEntry]? = nil

    /// Deleted by its owner (Δ-163): kept public and marked, never removed.
    var deletedByOwner: Bool? = nil
    var deletedDate: Date? = nil

    /// Description in other app languages ("fr"), each tied to the English it was made
    /// from (RecipeLocalizer). The name is never translated. Absent from older builds.
    var translations: [String: BookTranslation]? = nil
}

// MARK: - Sharing Result

enum SharingResult {
    case success(recordID: String)
    case failure(error: Error)
    case partialSuccess(successful: Int, failed: Int)
}

// MARK: - Sharing Error

enum SharingError: LocalizedError, Equatable {
    case notAuthenticated
    case cloudKitUnavailable(message: String? = nil)
    case recipeNotFound
    case bookNotFound
    case uploadFailed(Error)
    case downloadFailed(Error)
    case invalidData
    case imageUploadFailed(Error)
    
    static func == (lhs: SharingError, rhs: SharingError) -> Bool {
        switch (lhs, rhs) {
        case (.notAuthenticated, .notAuthenticated),
             (.recipeNotFound, .recipeNotFound),
             (.bookNotFound, .bookNotFound),
             (.invalidData, .invalidData):
            return true
        case (.cloudKitUnavailable(let lhsMsg), .cloudKitUnavailable(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return String(localized: "You must be signed in to iCloud to share content.", bundle: .appLanguage)
        case .cloudKitUnavailable(let message):
            return message ?? "CloudKit is not available. Check your iCloud settings."
        case .recipeNotFound:
            return String(localized: "The recipe you're trying to share was not found.", bundle: .appLanguage)
        case .bookNotFound:
            return String(localized: "The recipe book you're trying to share was not found.", bundle: .appLanguage)
        case .uploadFailed(let error):
            return String(localized: "Failed to upload: \(error.localizedDescription)", bundle: .appLanguage)
        case .downloadFailed(let error):
            return String(localized: "Failed to download: \(error.localizedDescription)", bundle: .appLanguage)
        case .invalidData:
            return String(localized: "The shared content contains invalid data.", bundle: .appLanguage)
        case .imageUploadFailed(let error):
            return String(localized: "Failed to upload image: \(error.localizedDescription)", bundle: .appLanguage)
        }
    }
    
    var canOpenOnboarding: Bool {
        switch self {
        case .cloudKitUnavailable, .notAuthenticated:
            return true
        default:
            return false
        }
    }
}

// MARK: - CloudKit Manager Data Structures

/// Status of a recipe in CloudKit
struct CloudKitRecipeStatus: Identifiable {
    let id = UUID()
    let recipe: CloudKitRecipe
    let cloudRecordID: String
    let sharedDate: Date
    let localTrackingRecord: SharedRecipe?
    /// The recipe this record publishes is in this device's library.
    var inLocalLibrary: Bool = false
    /// The recipe is in one of the user's books.
    var inBook: Bool = false
    
    var isTracked: Bool {
        localTrackingRecord != nil
    }
    
    var isOrphaned: Bool {
        !isTracked
    }
    
    var statusIcon: String {
        isTracked ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }
    
    var statusColor: Color {
        isTracked ? .green : .orange
    }
    
    var statusDescription: String {
        if isTracked { return "Tracked" }
        if inBook { return "Not tracked — recipe is in a book (re-link, never delete)" }
        if inLocalLibrary { return "Not tracked — recipe is in your library (re-link)" }
        return String(localized: "Orphaned (recipe not on this device)", bundle: .appLanguage)
    }
}

/// Data for CloudKit Recipe Manager View
struct CloudKitRecipeManagerData {
    let recipes: [CloudKitRecipeStatus]
    
    var trackedRecipes: [CloudKitRecipeStatus] {
        recipes.filter { $0.isTracked }
    }
    
    var orphanedRecipes: [CloudKitRecipeStatus] {
        recipes.filter { $0.isOrphaned }
    }
    
    /// Untracked records whose recipe is here or in a book: re-link, never bulk-delete.
    var relinkableOrphans: [CloudKitRecipeStatus] {
        orphanedRecipes.filter { $0.inLocalLibrary || $0.inBook }
    }
    
    /// The only records "Delete All Orphaned" may remove.
    var bulkDeletableOrphans: [CloudKitRecipeStatus] {
        orphanedRecipes.filter { TrackingCleanup.mayBulkDeleteOrphan(inLocalLibrary: $0.inLocalLibrary, inBook: $0.inBook) }
    }
    
    var trackedCount: Int {
        trackedRecipes.count
    }
    
    var orphanedCount: Int {
        orphanedRecipes.count
    }
    
    var totalCount: Int {
        recipes.count
    }
}

/// Status of a recipe book in CloudKit
struct CloudKitRecipeBookStatus: Identifiable {
    let id = UUID()
    let book: CloudKitRecipeBook
    let cloudRecordID: String
    let sharedDate: Date
    let localTrackingRecord: SharedRecipeBook?
    
    var isTracked: Bool {
        localTrackingRecord != nil
    }
    
    var isOrphaned: Bool {
        !isTracked
    }
    
    var statusIcon: String {
        isTracked ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }
    
    var statusColor: Color {
        isTracked ? .green : .orange
    }
    
    var statusDescription: String {
        isTracked ? "Tracked" : "Orphaned (not tracked locally)"
    }
}

// MARK: - CloudKit Meal Types

/// CloudKit-friendly representation of a meal for community sharing
struct CloudKitMeal: Codable, Identifiable {
    let id: UUID
    let name: String
    let mealDescription: String?
    let courses: [MealCourse]
    let notes: String?
    let sharedByUserID: String?
    let sharedByUserName: String?
    let sharedDate: Date

    /// Deleted by its owner (Δ-163): kept public and marked, never removed.
    var deletedByOwner: Bool? = nil
    var deletedDate: Date? = nil
}

/// Status of a meal in CloudKit
struct CloudKitMealStatus: Identifiable {
    let id = UUID()
    let meal: CloudKitMeal
    let cloudRecordID: String
    let sharedDate: Date
    let localTrackingRecord: SharedMeal?

    var isTracked: Bool { localTrackingRecord != nil }
    var isOrphaned: Bool { !isTracked }
}

/// Data for CloudKit Meal Manager View
struct CloudKitMealManagerData {
    let meals: [CloudKitMealStatus]

    var trackedMeals: [CloudKitMealStatus] { meals.filter { $0.isTracked } }
    var orphanedMeals: [CloudKitMealStatus] { meals.filter { $0.isOrphaned } }
    var trackedCount: Int { trackedMeals.count }
    var orphanedCount: Int { orphanedMeals.count }
    var totalCount: Int { meals.count }
}

/// Data for CloudKit Recipe Book Manager View
struct CloudKitRecipeBookManagerData {
    let books: [CloudKitRecipeBookStatus]
    
    var trackedBooks: [CloudKitRecipeBookStatus] {
        books.filter { $0.isTracked }
    }
    
    var orphanedBooks: [CloudKitRecipeBookStatus] {
        books.filter { $0.isOrphaned }
    }
    
    var trackedCount: Int {
        trackedBooks.count
    }
    
    var orphanedCount: Int {
        orphanedBooks.count
    }
    
    var totalCount: Int {
        books.count
    }
}

