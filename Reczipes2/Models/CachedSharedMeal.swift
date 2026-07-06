//
//  CachedSharedMeal.swift
//  Reczipes2
//
//  Temporary cache of community meals for viewing.
//  Auto-cleaned after 30 days of no access.

import Foundation
import SwiftData

/// Temporary cache of a community-shared meal for viewing.
/// Mirrors the pattern of CachedSharedRecipe.
@Model
final class CachedSharedMeal {
    var id: UUID = UUID()          // CloudKit meal ID
    var name: String = ""
    var mealDescription: String?
    var coursesData: Data?         // JSON-encoded [MealCourse]
    var notes: String?

    // Sharing metadata
    var sharedByUserID: String = ""
    var sharedByUserName: String?
    var sharedDate: Date = Date()
    var cachedDate: Date = Date()
    var lastAccessedDate: Date = Date()
    var isTemporaryCache: Bool = true

    @MainActor
    init(from cloudMeal: CloudKitMeal) {
        self.id = cloudMeal.id
        self.name = cloudMeal.name
        self.mealDescription = cloudMeal.mealDescription
        self.coursesData = try? JSONEncoder().encode(cloudMeal.courses)
        self.notes = cloudMeal.notes
        self.sharedByUserID = cloudMeal.sharedByUserID ?? ""
        self.sharedByUserName = cloudMeal.sharedByUserName
        self.sharedDate = cloudMeal.sharedDate
        self.cachedDate = Date()
        self.lastAccessedDate = Date()
    }
}
