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

    /// Keys to encode/decode — excludes imageData so it doesn't break the JSON round-trip.
    enum CodingKeys: String, CodingKey {
        case id, title, headerNotes, yield
        case ingredientSections, instructionSections
        case notes, reference, imageName, additionalImageNames
        case sharedByUserID, sharedByUserName, sharedDate
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
            return "You must be signed in to iCloud to share content."
        case .cloudKitUnavailable(let message):
            return message ?? "CloudKit is not available. Check your iCloud settings."
        case .recipeNotFound:
            return "The recipe you're trying to share was not found."
        case .bookNotFound:
            return "The recipe book you're trying to share was not found."
        case .uploadFailed(let error):
            return "Failed to upload: \(error.localizedDescription)"
        case .downloadFailed(let error):
            return "Failed to download: \(error.localizedDescription)"
        case .invalidData:
            return "The shared content contains invalid data."
        case .imageUploadFailed(let error):
            return "Failed to upload image: \(error.localizedDescription)"
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

/// Data for CloudKit Recipe Manager View
struct CloudKitRecipeManagerData {
    let recipes: [CloudKitRecipeStatus]
    
    var trackedRecipes: [CloudKitRecipeStatus] {
        recipes.filter { $0.isTracked }
    }
    
    var orphanedRecipes: [CloudKitRecipeStatus] {
        recipes.filter { $0.isOrphaned }
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

