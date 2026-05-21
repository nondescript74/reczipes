//
//  Meal.swift
//  Reczipes2
//
//  A meal groups together one or more recipes — e.g., a main course,
//  side dish, and bread served together. Each course slot may either
//  reference an existing RecipeX or hold a placeholder search query
//  the user can resolve via web search.
//

import Foundation
import SwiftData

@Model
final class Meal {

    // MARK: - Identity

    var id: UUID?
    var name: String?
    var mealDescription: String?

    // MARK: - Content

    /// Course slots, encoded as JSON. Each entry is a MealCourse.
    var coursesData: Data?

    /// Free-form notes (occasion, drink pairings, etc.)
    var notes: String?

    // MARK: - Preset Tracking

    /// True when this meal was seeded from the built-in preset list.
    var isPreset: Bool?

    /// Stable identifier for preset meals so we don't reseed duplicates.
    var presetIdentifier: String?

    // MARK: - Timestamps

    var dateCreated: Date?
    var dateModified: Date?

    // MARK: - Init

    init(id: UUID? = UUID(),
         name: String? = nil,
         mealDescription: String? = nil,
         courses: [MealCourse] = [],
         notes: String? = nil,
         isPreset: Bool? = false,
         presetIdentifier: String? = nil,
         dateCreated: Date? = Date(),
         dateModified: Date? = Date()) {
        self.id = id
        self.name = name
        self.mealDescription = mealDescription
        self.coursesData = try? JSONEncoder().encode(courses)
        self.notes = notes
        self.isPreset = isPreset
        self.presetIdentifier = presetIdentifier
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }
}

// MARK: - Course Accessors

extension Meal {

    var courses: [MealCourse] {
        guard let data = coursesData,
              let decoded = try? JSONDecoder().decode([MealCourse].self, from: data) else {
            return []
        }
        return decoded
    }

    func setCourses(_ courses: [MealCourse]) {
        coursesData = try? JSONEncoder().encode(courses)
        dateModified = Date()
    }

    var displayName: String {
        name ?? "Untitled Meal"
    }

    var courseCount: Int {
        courses.count
    }

    var linkedRecipeCount: Int {
        courses.filter { $0.recipeID != nil }.count
    }
}

// MARK: - MealCourse

/// A single slot in a meal — e.g., "Main", "Side", "Bread".
struct MealCourse: Codable, Identifiable, Hashable {
    var id: UUID = UUID()

    /// Display label for the course slot (e.g., "Main course", "Salad").
    var name: String

    /// Linked recipe in the user's library. Nil when the slot is just a
    /// placeholder waiting to be filled.
    var recipeID: UUID?

    /// Optional cached title of the linked recipe so we can render the
    /// slot even if the recipe is briefly unloaded.
    var recipeTitle: String?

    /// Search query the user entered when they don't yet have a recipe
    /// — used to launch a Google search for suggestions.
    var searchQuery: String?

    init(id: UUID = UUID(),
         name: String,
         recipeID: UUID? = nil,
         recipeTitle: String? = nil,
         searchQuery: String? = nil) {
        self.id = id
        self.name = name
        self.recipeID = recipeID
        self.recipeTitle = recipeTitle
        self.searchQuery = searchQuery
    }
}
