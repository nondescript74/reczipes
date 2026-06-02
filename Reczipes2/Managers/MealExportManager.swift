//
//  MealExportManager.swift
//  Reczipes2
//
//  Exports the user's meals to a v2 `MealImportPackage` JSON file.
//  Round-trip-friendly: each meal carries full course detail
//  (recipeID, recipeTitle, searchQuery) so a later import can
//  reattach to existing recipes without re-matching by title.
//

import Foundation
import SwiftData

enum MealExportError: LocalizedError {
    case nothingToExport
    case encodingFailed(underlying: Error)
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .nothingToExport:
            return "There are no meals to export."
        case .encodingFailed(let error):
            return "Could not encode meals to JSON: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Could not write the export file: \(error.localizedDescription)"
        }
    }
}

/// Summary returned from an export run, used by the UI.
struct MealExportResult {
    var url: URL
    var mealCount: Int
    var courseCount: Int
    var linkedCourseCount: Int

    var summary: String {
        var lines: [String] = []
        lines.append("Exported \(mealCount) meal\(mealCount == 1 ? "" : "s").")
        if courseCount > 0 {
            lines.append("Includes \(courseCount) course\(courseCount == 1 ? "" : "s") (\(linkedCourseCount) linked to recipes).")
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
enum MealExportManager {

    /// Schema version this manager writes. Matches
    /// `MealImportManager.supportedVersion` — exported files are
    /// re-importable by the same app.
    static let exportVersion = 2

    // MARK: - Package builders

    /// Builds a v2 `MealImportPackage` from the user's meals. Includes
    /// full `courseDetails` for every course so a later import can
    /// reattach to live recipes without title matching.
    static func makePackage(from meals: [Meal]) -> MealImportPackage {
        let entries = meals.map(entryFromMeal)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return MealImportPackage(
            version: exportVersion,
            source: "Reczipes meal export",
            description: "Exported \(meals.count) meal\(meals.count == 1 ? "" : "s") on \(timestamp)",
            meals: entries
        )
    }

    private static func entryFromMeal(_ meal: Meal) -> MealImportEntry {
        let exportedCourses = meal.courses.map { course in
            MealCourseExport(
                name: course.name,
                recipeID: course.recipeID,
                recipeTitle: course.recipeTitle,
                searchQuery: course.searchQuery
            )
        }
        // Keep the v1 `courses: [String]` field populated too so older
        // app versions can still partially decode the file (they'll
        // re-match by title and lose linkage state, but at least the
        // meal and its course names load).
        let courseNames = exportedCourses.map(\.name)

        // Split combined "Cuisine — description" back apart on export
        // so the imported v2 entry retains the structured fields.
        let (parsedCuisine, parsedDescription) = splitDescription(meal.mealDescription)

        return MealImportEntry(
            name: meal.name ?? "Untitled Meal",
            description: parsedDescription,
            notes: meal.notes,
            cuisine: parsedCuisine,
            courses: courseNames.isEmpty ? nil : courseNames,
            courseDetails: exportedCourses.isEmpty ? nil : exportedCourses
        )
    }

    // MARK: - JSON encode + write

    /// Encodes a package to pretty-printed UTF-8 JSON data.
    static func encodePackage(_ package: MealImportPackage) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(package)
        } catch {
            throw MealExportError.encodingFailed(underlying: error)
        }
    }

    /// Writes a meals export to the temporary directory and returns
    /// the URL. Use this for ShareLink/share-sheet flows.
    @discardableResult
    static func writeExport(for meals: [Meal]) throws -> MealExportResult {
        guard !meals.isEmpty else {
            throw MealExportError.nothingToExport
        }

        let package = makePackage(from: meals)
        let data = try encodePackage(package)
        let url = try writeToTemporaryFile(data: data)

        let courseCount = meals.reduce(0) { $0 + $1.courses.count }
        let linkedCount = meals.reduce(0) { sum, meal in
            sum + meal.courses.filter { $0.recipeID != nil }.count
        }

        return MealExportResult(
            url: url,
            mealCount: meals.count,
            courseCount: courseCount,
            linkedCourseCount: linkedCount
        )
    }

    private static func writeToTemporaryFile(data: Data) throws -> URL {
        let filename = "meal_plans_\(filenameTimestamp()).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            // Overwrite any prior export at the same path (same second).
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try data.write(to: url, options: .atomic)
        } catch {
            throw MealExportError.writeFailed(underlying: error)
        }
        return url
    }

    private static func filenameTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    // MARK: - Helpers

    /// Inverse of `MealImportManager.combinedDescription`. The importer
    /// joins description and cuisine into `"<cuisine> — <description>"`
    /// when both are present; we split that back apart on export so
    /// round-trips don't drift the structured fields.
    private static func splitDescription(_ combined: String?) -> (cuisine: String?, description: String?) {
        guard let combined,
              let separatorRange = combined.range(of: " — ") else {
            return (nil, combined?.nilIfEmpty)
        }
        let cuisine = String(combined[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespaces).nilIfEmpty
        let description = String(combined[separatorRange.upperBound...]).trimmingCharacters(in: .whitespaces).nilIfEmpty
        return (cuisine, description)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
