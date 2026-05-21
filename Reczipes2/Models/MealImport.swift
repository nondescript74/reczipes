//
//  MealImport.swift
//  Reczipes2
//
//  Decodable schema for importing meal plans from JSON. Each entry
//  in the package becomes a Meal; its course names are matched
//  against existing recipes by title (case-insensitive) at import
//  time.
//

import Foundation

/// Top-level container for a meal-plan import file.
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

    /// Ordered course names. If empty or missing, the meal is seeded
    /// with a single course matching `name`.
    var courses: [String]?

    /// Courses to actually use, falling back to a single course
    /// derived from the meal name.
    var effectiveCourses: [String] {
        if let courses, !courses.isEmpty {
            return courses
        }
        return [name]
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
