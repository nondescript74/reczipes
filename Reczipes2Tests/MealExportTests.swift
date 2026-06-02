//
//  MealExportTests.swift
//  Reczipes2Tests
//
//  Tests for the meal export pipeline: v2 schema decode, courseDetails
//  priority, round-trip fidelity, and stale-recipeID downgrade.
//

import Testing
import Foundation
import SwiftData
@testable import Reczipes2

@MainActor
private func makeMealExportContainer() -> ModelContainer {
    let schema = Schema([Meal.self, RecipeX.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try! ModelContainer(for: schema, configurations: [configuration])
}

// MARK: - v2 Schema Decoding

@Suite("MealExport v2 Decoding Tests")
@MainActor
struct MealExportV2DecodingTests {

    @Test("Package decodes with courseDetails field")
    func decodeV2WithCourseDetails() throws {
        let json = """
        {
          "version": 2,
          "meals": [
            {
              "name": "Italian Dinner",
              "courseDetails": [
                {
                  "name": "Spaghetti",
                  "recipeID": "11111111-1111-1111-1111-111111111111",
                  "recipeTitle": "Classic Spaghetti"
                },
                {
                  "name": "Garlic Bread",
                  "searchQuery": "garlic bread recipe"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let package = try JSONDecoder().decode(MealImportPackage.self, from: json)
        #expect(package.version == 2)

        let entry = try #require(package.meals.first)
        let details = try #require(entry.courseDetails)
        #expect(details.count == 2)
        #expect(details[0].name == "Spaghetti")
        #expect(details[0].recipeID == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(details[0].recipeTitle == "Classic Spaghetti")
        #expect(details[0].searchQuery == nil)
        #expect(details[1].name == "Garlic Bread")
        #expect(details[1].recipeID == nil)
        #expect(details[1].searchQuery == "garlic bread recipe")
    }

    @Test("v1 package without courseDetails still decodes")
    func decodeV1Compat() throws {
        let json = """
        {"version": 1, "meals": [{"name": "Pizza", "courses": ["Pizza"]}]}
        """.data(using: .utf8)!

        let package = try JSONDecoder().decode(MealImportPackage.self, from: json)
        let entry = try #require(package.meals.first)
        #expect(entry.courses == ["Pizza"])
        #expect(entry.courseDetails == nil)
    }
}

// MARK: - Import Priority

@Suite("MealExport courseDetails Priority Tests")
@MainActor
struct MealExportImportPriorityTests {

    @Test("Importer uses courseDetails when present and ignores courses[String]")
    func courseDetailsTakesPriority() async throws {
        let container = makeMealExportContainer()
        let context = container.mainContext

        // Recipe that exists in the store — courseDetails references it
        // by ID, so the linkage should be preserved without any title
        // matching against the (wrong) `courses` field.
        let existingRecipe = RecipeX(title: "Real Recipe")
        context.insert(existingRecipe)
        try context.save()
        let recipeID = try #require(existingRecipe.id)

        let entry = MealImportEntry(
            name: "Dinner",
            courses: ["This name doesnt match any recipe"],
            courseDetails: [
                MealCourseExport(
                    name: "Main",
                    recipeID: recipeID,
                    recipeTitle: "Real Recipe"
                )
            ]
        )
        let package = MealImportPackage(version: 2, source: "Test", description: nil, meals: [entry])

        let result = try MealImportManager.importPackage(
            package,
            into: context,
            existingMeals: [],
            existingRecipes: [existingRecipe]
        )

        #expect(result.importedCount == 1)
        #expect(result.linkedCourseCount == 1)
        #expect(result.unlinkedCourseCount == 0)

        let stored = try #require(try context.fetch(FetchDescriptor<Meal>()).first)
        #expect(stored.courses.count == 1)
        let course = try #require(stored.courses.first)
        #expect(course.name == "Main")
        #expect(course.recipeID == recipeID)
        #expect(course.recipeTitle == "Real Recipe")
    }

    @Test("Stale recipeID falls back to title match")
    func staleRecipeIDFallsBackToTitleMatch() async throws {
        let container = makeMealExportContainer()
        let context = container.mainContext

        // Recipe exists with the expected title, but the recipeID in
        // courseDetails points to a different UUID (e.g., the original
        // recipe was deleted and re-extracted from a backup).
        let existingRecipe = RecipeX(title: "Mystery Stew")
        context.insert(existingRecipe)
        try context.save()
        let liveID = try #require(existingRecipe.id)

        let staleID = UUID()
        #expect(staleID != liveID)

        let entry = MealImportEntry(
            name: "Dinner",
            courseDetails: [
                MealCourseExport(
                    name: "Stew",
                    recipeID: staleID,                  // dangling
                    recipeTitle: "Mystery Stew"         // matches live recipe
                )
            ]
        )
        let package = MealImportPackage(version: 2, source: "Test", description: nil, meals: [entry])

        let result = try MealImportManager.importPackage(
            package,
            into: context,
            existingMeals: [],
            existingRecipes: [existingRecipe]
        )

        #expect(result.linkedCourseCount == 1)
        let stored = try #require(try context.fetch(FetchDescriptor<Meal>()).first)
        let course = try #require(stored.courses.first)
        #expect(course.recipeID == liveID)
        #expect(course.recipeTitle == "Mystery Stew")
    }

    @Test("Stale recipeID with no title match becomes placeholder")
    func staleRecipeIDDowngradesToPlaceholder() async throws {
        let container = makeMealExportContainer()
        let context = container.mainContext

        // No matching recipe in the store at all.
        let entry = MealImportEntry(
            name: "Dinner",
            courseDetails: [
                MealCourseExport(
                    name: "Main",
                    recipeID: UUID(),
                    recipeTitle: "Long Gone Recipe"
                )
            ]
        )
        let package = MealImportPackage(version: 2, source: "Test", description: nil, meals: [entry])

        let result = try MealImportManager.importPackage(
            package,
            into: context,
            existingMeals: [],
            existingRecipes: []
        )

        #expect(result.linkedCourseCount == 0)
        #expect(result.unlinkedCourseCount == 1)

        let stored = try #require(try context.fetch(FetchDescriptor<Meal>()).first)
        let course = try #require(stored.courses.first)
        #expect(course.recipeID == nil)
        // Search query falls back to the recipeTitle hint so the user
        // can still find the lost recipe via web search.
        #expect(course.searchQuery == "Long Gone Recipe")
    }
}

// MARK: - Round-Trip

@Suite("MealExport Round-Trip Tests")
@MainActor
struct MealExportRoundTripTests {

    @Test("Export then re-import preserves meal + course linkage")
    func roundTripPreservesLinkage() async throws {
        let sourceContainer = makeMealExportContainer()
        let sourceContext = sourceContainer.mainContext

        // Build a small library with one recipe and one meal that
        // links to it.
        let recipe = RecipeX(title: "Margherita Pizza")
        sourceContext.insert(recipe)
        try sourceContext.save()
        let recipeID = try #require(recipe.id)

        let originalMeal = Meal(
            name: "Pizza Night",
            mealDescription: "Italian — Friday classic",
            courses: [
                MealCourse(name: "Main", recipeID: recipeID, recipeTitle: "Margherita Pizza"),
                MealCourse(name: "Side salad", searchQuery: "side salad")
            ],
            notes: "Open the Chianti."
        )
        sourceContext.insert(originalMeal)
        try sourceContext.save()

        // Export
        let allMeals = try sourceContext.fetch(FetchDescriptor<Meal>())
        let package = MealExportManager.makePackage(from: allMeals)
        #expect(package.version == 2)
        #expect(package.meals.count == 1)

        let exportedEntry = try #require(package.meals.first)
        #expect(exportedEntry.name == "Pizza Night")
        #expect(exportedEntry.notes == "Open the Chianti.")
        #expect(exportedEntry.cuisine == "Italian")
        #expect(exportedEntry.description == "Friday classic")
        let exportedDetails = try #require(exportedEntry.courseDetails)
        #expect(exportedDetails.count == 2)
        #expect(exportedDetails[0].recipeID == recipeID)
        #expect(exportedDetails[1].searchQuery == "side salad")

        // Encode → decode (simulates write/read)
        let data = try MealExportManager.encodePackage(package)
        let decoded = try JSONDecoder().decode(MealImportPackage.self, from: data)
        #expect(decoded.version == 2)

        // Re-import into a fresh store that still has the same recipe
        // (so the courseDetails recipeID can resolve).
        let targetContainer = makeMealExportContainer()
        let targetContext = targetContainer.mainContext
        let targetRecipe = RecipeX(title: "Margherita Pizza")
        // Manually assign the same id so courseDetails reattaches.
        targetRecipe.id = recipeID
        targetContext.insert(targetRecipe)
        try targetContext.save()

        let result = try MealImportManager.importPackage(
            decoded,
            into: targetContext,
            existingMeals: [],
            existingRecipes: [targetRecipe]
        )

        #expect(result.importedCount == 1)
        #expect(result.linkedCourseCount == 1)
        #expect(result.unlinkedCourseCount == 1)

        let restored = try #require(try targetContext.fetch(FetchDescriptor<Meal>()).first)
        #expect(restored.name == "Pizza Night")
        #expect(restored.notes == "Open the Chianti.")
        #expect(restored.courses.count == 2)

        let linked = try #require(restored.courses.first { $0.recipeID != nil })
        #expect(linked.name == "Main")
        #expect(linked.recipeID == recipeID)
        #expect(linked.recipeTitle == "Margherita Pizza")

        let placeholder = try #require(restored.courses.first { $0.recipeID == nil })
        #expect(placeholder.name == "Side salad")
        #expect(placeholder.searchQuery == "side salad")
    }

    @Test("writeExport produces a file ShareLink can read")
    func writeExportProducesReadableFile() async throws {
        let container = makeMealExportContainer()
        let context = container.mainContext

        let meal = Meal(name: "Quick Lunch", courses: [MealCourse(name: "Sandwich")])
        context.insert(meal)
        try context.save()

        let meals = try context.fetch(FetchDescriptor<Meal>())
        let result = try MealExportManager.writeExport(for: meals)

        #expect(result.mealCount == 1)
        #expect(result.courseCount == 1)
        #expect(result.url.lastPathComponent.hasPrefix("meal_plans_"))
        #expect(result.url.pathExtension == "json")

        let data = try Data(contentsOf: result.url)
        let decoded = try JSONDecoder().decode(MealImportPackage.self, from: data)
        #expect(decoded.version == 2)
        #expect(decoded.meals.first?.name == "Quick Lunch")

        // Clean up — temp files accumulate otherwise.
        try? FileManager.default.removeItem(at: result.url)
    }

    @Test("writeExport throws nothingToExport on empty library")
    func writeExportEmptyLibrary() async throws {
        #expect(throws: MealExportError.self) {
            try MealExportManager.writeExport(for: [])
        }
    }
}
