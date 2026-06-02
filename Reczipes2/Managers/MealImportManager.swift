//
//  MealImportManager.swift
//  Reczipes2
//
//  Imports meal plans from a JSON file (either the bundled file or
//  a user-supplied file) into the SwiftData store. Each imported
//  course is matched against the user's existing RecipeX library by
//  title (case-insensitive); matches become linked courses, misses
//  become placeholder courses with `searchQuery` set so the user
//  can search the web later.
//
//  Duplicate detection: an imported meal is skipped if a meal with
//  the same trimmed, case-insensitive name already exists in the
//  user's library.
//

import Foundation
import SwiftData

enum MealImportError: LocalizedError {
    case bundledFileMissing
    case fileNotReadable
    case invalidJSON(underlying: Error)
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .bundledFileMissing:
            return "The bundled meal plans file was not found."
        case .fileNotReadable:
            return "The selected file could not be read."
        case .invalidJSON(let error):
            return "The file is not a valid meal-plan JSON: \(error.localizedDescription)"
        case .unsupportedVersion(let version):
            return "This meal-plan file uses version \(version), which this app cannot import."
        }
    }
}

@MainActor
enum MealImportManager {

    /// Filename (no extension) of the bundled meal-plans JSON.
    static let bundledResourceName = "meal_plans_import"

    /// Highest schema version this manager knows how to read.
    /// - v1: course list is `[String]` of names, matched to recipes by title.
    /// - v2: adds `courseDetails` carrying full recipe linkage.
    static let supportedVersion = 2

    // MARK: - Loaders

    /// Loads and decodes the bundled JSON shipped with the app.
    static func loadBundledPackage() throws -> MealImportPackage {
        guard let url = Bundle.main.url(
            forResource: bundledResourceName,
            withExtension: "json"
        ) else {
            throw MealImportError.bundledFileMissing
        }
        return try loadPackage(from: url)
    }

    /// Loads and decodes a meal-plan package from a URL.
    static func loadPackage(from url: URL) throws -> MealImportPackage {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MealImportError.fileNotReadable
        }

        let package: MealImportPackage
        do {
            package = try JSONDecoder().decode(MealImportPackage.self, from: data)
        } catch {
            throw MealImportError.invalidJSON(underlying: error)
        }

        guard package.version <= supportedVersion else {
            throw MealImportError.unsupportedVersion(package.version)
        }
        return package
    }

    // MARK: - Import

    /// Imports a package into the model context. Skips meals whose
    /// names already exist in `existingMeals`. Course names are
    /// matched against `existingRecipes` by title (trimmed,
    /// case-insensitive). Saves at the end.
    @discardableResult
    static func importPackage(
        _ package: MealImportPackage,
        into modelContext: ModelContext,
        existingMeals: [Meal],
        existingRecipes: [RecipeX]
    ) throws -> MealImportResult {
        let existingNames: Set<String> = Set(
            existingMeals.compactMap { meal in
                meal.name.flatMap { normalize($0) }
            }
        )

        // Title -> recipe id lookup. If multiple recipes share a
        // title we keep the first; the user can rebind later.
        var recipeByTitle: [String: RecipeX] = [:]
        // recipeID -> recipe lookup for v2 courseDetails resolution.
        var recipeByID: [UUID: RecipeX] = [:]
        for recipe in existingRecipes {
            if let id = recipe.id {
                recipeByID[id] = recipe
            }
            guard let title = recipe.title, !title.isEmpty else { continue }
            let key = normalize(title)
            if recipeByTitle[key] == nil {
                recipeByTitle[key] = recipe
            }
        }

        var imported = 0
        var skipped = 0
        var linkedCourses = 0
        var unlinkedCourses = 0

        for entry in package.meals {
            let normalizedName = normalize(entry.name)
            guard !normalizedName.isEmpty else { continue }

            if existingNames.contains(normalizedName) {
                skipped += 1
                continue
            }

            let mealCourses: [MealCourse]
            let counts: (linked: Int, unlinked: Int)

            if let details = entry.courseDetails, !details.isEmpty {
                // v2 path: trust the exported course detail. Validate
                // recipeIDs against the live store; downgrade stale
                // links to placeholders so we never produce a dangling
                // reference.
                (mealCourses, counts) = buildCoursesFromDetails(
                    details,
                    recipeByID: recipeByID,
                    recipeByTitle: recipeByTitle
                )
            } else {
                // v1 path: match course names against recipe titles.
                (mealCourses, counts) = buildCoursesFromNames(
                    entry.effectiveCourses,
                    recipeByTitle: recipeByTitle
                )
            }

            linkedCourses += counts.linked
            unlinkedCourses += counts.unlinked

            let descriptionText = combinedDescription(
                description: entry.description,
                cuisine: entry.cuisine
            )

            let meal = Meal(
                name: entry.name.trimmingCharacters(in: .whitespacesAndNewlines),
                mealDescription: descriptionText,
                courses: mealCourses,
                notes: entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                isPreset: false
            )
            modelContext.insert(meal)
            imported += 1
        }

        try modelContext.save()

        return MealImportResult(
            importedCount: imported,
            skippedDuplicateCount: skipped,
            totalProcessed: package.meals.count,
            linkedCourseCount: linkedCourses,
            unlinkedCourseCount: unlinkedCourses
        )
    }

    // MARK: - Course Builders

    /// v1 path — match course-name strings against recipe titles.
    private static func buildCoursesFromNames(
        _ names: [String],
        recipeByTitle: [String: RecipeX]
    ) -> ([MealCourse], (linked: Int, unlinked: Int)) {
        var courses: [MealCourse] = []
        var linked = 0
        var unlinked = 0

        for courseName in names {
            let trimmed = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let match = recipeByTitle[normalize(trimmed)] {
                courses.append(MealCourse(
                    name: trimmed,
                    recipeID: match.id,
                    recipeTitle: match.title
                ))
                linked += 1
            } else {
                courses.append(MealCourse(
                    name: trimmed,
                    searchQuery: trimmed
                ))
                unlinked += 1
            }
        }
        return (courses, (linked, unlinked))
    }

    /// v2 path — trust the exported `MealCourseExport` detail and
    /// reattach to a live recipe by ID. If the recipeID no longer
    /// exists (recipe was deleted between export and import), fall
    /// back to a title match; if that also fails, downgrade to a
    /// placeholder using `recipeTitle` (or the course name) as the
    /// search query.
    private static func buildCoursesFromDetails(
        _ details: [MealCourseExport],
        recipeByID: [UUID: RecipeX],
        recipeByTitle: [String: RecipeX]
    ) -> ([MealCourse], (linked: Int, unlinked: Int)) {
        var courses: [MealCourse] = []
        var linked = 0
        var unlinked = 0

        for detail in details {
            let trimmedName = detail.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }

            // 1. Try the exported recipeID first.
            if let id = detail.recipeID, let recipe = recipeByID[id] {
                courses.append(MealCourse(
                    name: trimmedName,
                    recipeID: recipe.id,
                    recipeTitle: recipe.title
                ))
                linked += 1
                continue
            }

            // 2. Fall back to title match if the recipeID is stale.
            let fallbackTitle = detail.recipeTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? trimmedName
            if !fallbackTitle.isEmpty,
               let match = recipeByTitle[normalize(fallbackTitle)] {
                courses.append(MealCourse(
                    name: trimmedName,
                    recipeID: match.id,
                    recipeTitle: match.title
                ))
                linked += 1
                continue
            }

            // 3. Preserve any explicit search query; otherwise seed
            //    one from the recipeTitle hint or the course name.
            let query = detail.searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? fallbackTitle.nilIfEmpty
                ?? trimmedName
            courses.append(MealCourse(
                name: trimmedName,
                searchQuery: query
            ))
            unlinked += 1
        }
        return (courses, (linked, unlinked))
    }

    // MARK: - Helpers

    /// Folds case + trims whitespace for name comparison.
    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
             .lowercased()
    }

    /// Joins an optional description with a cuisine hint so users see
    /// both on the meal row without crowding the data model.
    private static func combinedDescription(description: String?, cuisine: String?) -> String? {
        let trimmedDesc = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCuisine = cuisine?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (trimmedDesc?.nilIfEmpty, trimmedCuisine?.nilIfEmpty) {
        case (nil, nil):
            return nil
        case (let desc?, nil):
            return desc
        case (nil, let cuisine?):
            return cuisine
        case (let desc?, let cuisine?):
            return "\(cuisine) — \(desc)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
