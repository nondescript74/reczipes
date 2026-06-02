//
//  MealImport.swift
//  Reczipes2
//
//  Codable schema for importing and exporting meal plans as JSON.
//
//  Schema versioning:
//   - v1: course list is a `[String]` of names. Importer matches each
//         name against existing recipes by title.
//   - v2: adds `courseDetails: [MealCourseExport]` carrying recipeID /
//         recipeTitle / searchQuery for round-trip fidelity. Importer
//         prefers `courseDetails` when present; falls back to `courses`
//         (v1 behavior) otherwise.
//

import Foundation

/// Top-level container for a meal-plan import/export file.
struct MealImportPackage: Codable {
    var version: Int
    var source: String?
    var description: String?
    var meals: [MealImportEntry]
}

/// One meal in an import package.
struct MealImportEntry: Codable {
    /// Display name for the meal (e.g., "Kung pao chicken").
    var name: String

    /// Optional free-form description shown on the meal.
    var description: String?

    /// Optional notes (occasion, drink pairings, reminders).
    var notes: String?

    /// Cuisine hint (e.g., "Chinese", "Italian"). Currently advisory
    /// — preserved on import so we can use it later for categorization.
    var cuisine: String?

    /// v1 schema: ordered course names. If empty or missing AND
    /// `courseDetails` is also missing, the meal is seeded with a
    /// single course matching `name`.
    var courses: [String]?

    /// v2 schema: full course detail (recipeID, recipeTitle,
    /// searchQuery). When present, takes priority over `courses` and
    /// allows the importer to preserve linkage without re-matching
    /// by title.
    var courseDetails: [MealCourseExport]?

    init(
        name: String,
        description: String? = nil,
        notes: String? = nil,
        cuisine: String? = nil,
        courses: [String]? = nil,
        courseDetails: [MealCourseExport]? = nil
    ) {
        self.name = name
        self.description = description
        self.notes = notes
        self.cuisine = cuisine
        self.courses = courses
        self.courseDetails = courseDetails
    }

    /// v1 fallback: ordered course names to use, falling back to a
    /// single course derived from the meal name. Only consulted when
    /// `courseDetails` is nil.
    var effectiveCourses: [String] {
        if let courses, !courses.isEmpty {
            return courses
        }
        return [name]
    }
}

/// v2 schema: full meal-course detail for round-trip export/import.
/// Mirrors the runtime `MealCourse` so we can reconstruct linked
/// recipes without re-matching by title.
struct MealCourseExport: Codable, Hashable {
    /// Display label for the course slot.
    var name: String

    /// Linked recipe ID (when the course was filled with a real recipe).
    var recipeID: UUID?

    /// Cached recipe title at export time. Used for display when the
    /// linked recipe is unloaded, and as a fallback search query if
    /// the recipeID no longer resolves at import time.
    var recipeTitle: String?

    /// Placeholder search query for unlinked courses.
    var searchQuery: String?

    init(
        name: String,
        recipeID: UUID? = nil,
        recipeTitle: String? = nil,
        searchQuery: String? = nil
    ) {
        self.name = name
        self.recipeID = recipeID
        self.recipeTitle = recipeTitle
        self.searchQuery = searchQuery
    }
}

/// Summary returned from an import run, used by the UI.
struct MealImportResult {
    var importedCount: Int
    var skippedDuplicateCount: Int
    var totalProcessed: Int
    var linkedCourseCount: Int
    var unlinkedCourseCount: Int

    /// Human-readable summary for the success alert.
    var summary: String {
        var lines: [String] = []
        lines.append("Imported \(importedCount) meal\(importedCount == 1 ? "" : "s").")
        if skippedDuplicateCount > 0 {
            lines.append("Skipped \(skippedDuplicateCount) duplicate\(skippedDuplicateCount == 1 ? "" : "s").")
        }
        let totalCourses = linkedCourseCount + unlinkedCourseCount
        if totalCourses > 0 {
            lines.append("Linked \(linkedCourseCount) of \(totalCourses) course\(totalCourses == 1 ? "" : "s") to existing recipes.")
        }
        return lines.joined(separator: "\n")
    }
}
