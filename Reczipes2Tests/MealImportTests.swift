//
//  MealImportTests.swift
//  Reczipes2Tests
//
//  Tests for the meal-plan importer: recipe name matching,
//  duplicate suppression, and behavior of the bundled JSON file.
//

import Testing
import Foundation
import SwiftData
@testable import Reczipes2

@MainActor
private func makeMealImportContainer() -> ModelContainer {
    let schema = Schema([Meal.self, RecipeX.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try! ModelContainer(for: schema, configurations: [configuration])
}

private func makePackage(_ entries: [MealImportEntry]) -> MealImportPackage {
    MealImportPackage(version: 1, source: "Test", description: nil, meals: entries)
}

// MARK: - Decoding

@Suite("MealImport Decoding Tests")
@MainActor
struct MealImportDecodingTests {

    @Test("Package decodes with minimal required fields")
    func decodeMinimal() throws {
        let json = """
        {"version": 1, "meals": [{"name": "Pizza"}]}
        """.data(using: .utf8)!

        let package = try JSONDecoder().decode(MealImportPackage.self, from: json)
        #expect(package.version == 1)
        #expect(package.meals.count == 1)
        #expect(package.meals[0].name == "Pizza")
        #expect(package.meals[0].courses == nil)
        #expect(package.meals[0].effectiveCourses == ["Pizza"])
    }

    @Test("effectiveCourses returns explicit list when provided")
    func effectiveCoursesExplicit() throws {
        let entry = MealImportEntry(
            name: "Italian Dinner",
            description: nil,
            notes: nil,
            cuisine: "Italian",
            courses: ["Spaghetti", "Garlic Bread"]
        )
        #expect(entry.effectiveCourses == ["Spaghetti", "Garlic Bread"])
    }

    @Test("effectiveCourses falls back to name when courses is empty")
    func effectiveCoursesEmpty() throws {
        let entry = MealImportEntry(
            name: "Steak",
            description: nil,
            notes: nil,
            cuisine: nil,
            courses: []
        )
        #expect(entry.effectiveCourses == ["Steak"])
    }
}

// MARK: - Import Logic

@Suite("MealImport Logic Tests")
@MainActor
struct MealImportLogicTests {

    @Test("Importing into an empty store inserts every entry as a non-preset meal")
    func importIntoEmptyStore() async throws {
        let container = makeMealImportContainer()
        let context = container.mainContext

        let package = makePackage([
            MealImportEntry(name: "Pizza", description: nil, notes: nil, cuisine: "Italian",
                            courses: ["Pizza", "Side salad"]),
            MealImportEntry(name: "Steak", description: nil, notes: nil, cuisine: nil,
                            courses: ["Steak"])
        ])

        let result = try MealImportManager.importPackage(
            package,
            into: context,
            existingMeals: [],
            existingRecipes: []
        )

        #expect(result.importedCount == 2)
        #expect(result.skippedDuplicateCount == 0)
        #expect(result.linkedCourseCount == 0)
        #expect(result.unlinkedCourseCount == 3)

        let stored = try context.fetch(FetchDescriptor<Meal>())
        #expect(stored.count == 2)
        #expect(stored.allSatisfy { $0.isPreset == false })

        let pizza = try #require(stored.first { $0.name == "Pizza" })
        #expect(pizza.mealDescription == "Italian")
        #expect(pizza.courses.map(\.name) == ["Pizza", "Side salad"])
        #expect(pizza.courses.allSatisfy { $0.recipeID == nil })
        #expect(pizza.courses.allSatisfy { ($0.searchQuery?.isEmpty == false) })
    }

    @Test("Course whose name matches an existing recipe gets linked")
    func recipeNameMatchingLinksCourse() async throws {
        let container = makeMealImportContainer()
        let context = container.mainContext

        let existingRecipe = RecipeX(title: "Kung Pao Chicken")
        context.insert(existingRecipe)
        try context.save()

        let package = makePackage([
            MealImportEntry(name: "Kung pao chicken", description: nil, notes: nil, cuisine: "Chinese",
                            courses: ["Kung pao chicken", "Steamed rice"])
        ])

        let result = try MealImportManager.importPackage(
            package,
            into: context,
            existingMeals: [],
            existingRecipes: [existingRecipe]
        )

        #expect(result.importedCount == 1)
        #expect(result.linkedCourseCount == 1)
        #expect(result.unlinkedCourseCount == 1)

        let stored = try #require(try context.fetch(FetchDescriptor<Meal>()).first)
        let linked = try #require(stored.courses.first { $0.recipeID != nil })
        #expect(linked.recipeID == existingRecipe.id)
        #expect(linked.recipeTitle == "Kung Pao Chicken")

        let unlinked = try #require(stored.courses.first { $0.recipeID == nil })
        #expect(unlinked.name == "Steamed rice")
        #expect(unlinked.searchQuery == "Steamed rice")
    }

    @Test("Recipe matching is case- and whitespace-insensitive")
    func recipeMatchingCaseInsensitive() async throws {
        let container = makeMealImportContainer()
        let context = container.mainContext

        let existing = RecipeX(title: "  butter CHICKEN ")
        context.insert(existing)
        try context.save()

        let package = makePackage([
            MealImportEntry(name: "Butter Chicken Dinner", description: nil, notes: nil,
                            cuisine: nil, courses: ["Butter chicken"])
        ])

        let result = try MealImportManager.importPackage(
            package,
            into: context,
            existingMeals: [],
            existingRecipes: [existing]
        )

        #expect(result.linkedCourseCount == 1)
        let stored = try #require(try context.fetch(FetchDescriptor<Meal>()).first)
        #expect(stored.courses.first?.recipeID == existing.id)
    }

    @Test("Meals whose names match an existing meal are skipped")
    func duplicateMealNameSkipped() async throws {
        let container = makeMealImportContainer()
        let context = container.mainContext

        let existingMeal = Meal(name: "Pizza", courses: [MealCourse(name: "Pizza")])
        context.insert(existingMeal)
        try context.save()

        let package = makePackage([
            MealImportEntry(name: "Pizza", description: nil, notes: nil, cuisine: nil,
                            courses: ["Pizza", "Side salad"]),
            MealImportEntry(name: "Steak", description: nil, notes: nil, cuisine: nil,
                            courses: ["Steak"])
        ])

        let result = try MealImportManager.importPackage(
            package,
            into: context,
            existingMeals: [existingMeal],
            existingRecipes: []
        )

        #expect(result.importedCount == 1)
        #expect(result.skippedDuplicateCount == 1)

        let stored = try context.fetch(FetchDescriptor<Meal>())
        #expect(stored.count == 2)
        #expect(Set(stored.compactMap { $0.name }) == ["Pizza", "Steak"])
    }

    @Test("Duplicate detection is case- and whitespace-insensitive")
    func duplicateDetectionCaseInsensitive() async throws {
        let container = makeMealImportContainer()
        let context = container.mainContext

        let existing = Meal(name: "  Kung Pao Chicken  ", courses: [MealCourse(name: "Main")])
        context.insert(existing)
        try context.save()

        let package = makePackage([
            MealImportEntry(name: "kung pao chicken", description: nil, notes: nil,
                            cuisine: nil, courses: nil)
        ])

        let result = try MealImportManager.importPackage(
            package,
            into: context,
            existingMeals: [existing],
            existingRecipes: []
        )

        #expect(result.importedCount == 0)
        #expect(result.skippedDuplicateCount == 1)
    }

    @Test("Imported meal preserves description, notes, and cuisine summary")
    func importedMetadataPreserved() async throws {
        let container = makeMealImportContainer()
        let context = container.mainContext

        let package = makePackage([
            MealImportEntry(
                name: "Fajitas",
                description: "Beef and peppers",
                notes: "For Friday",
                cuisine: "Mexican",
                courses: ["Fajitas", "Tortillas"]
            )
        ])

        _ = try MealImportManager.importPackage(
            package,
            into: context,
            existingMeals: [],
            existingRecipes: []
        )

        let stored = try #require(try context.fetch(FetchDescriptor<Meal>()).first)
        #expect(stored.name == "Fajitas")
        #expect(stored.mealDescription == "Mexican — Beef and peppers")
        #expect(stored.notes == "For Friday")
    }

    @Test("Empty course names are dropped without crashing")
    func emptyCourseNamesDropped() async throws {
        let container = makeMealImportContainer()
        let context = container.mainContext

        let package = makePackage([
            MealImportEntry(name: "Meal", description: nil, notes: nil, cuisine: nil,
                            courses: ["", "   ", "Real course"])
        ])

        _ = try MealImportManager.importPackage(
            package,
            into: context,
            existingMeals: [],
            existingRecipes: []
        )

        let stored = try #require(try context.fetch(FetchDescriptor<Meal>()).first)
        #expect(stored.courses.map(\.name) == ["Real course"])
    }
}

// MARK: - Bundled file

@Suite("Bundled Meal Plans Tests")
@MainActor
struct BundledMealPlansTests {

    @Test("Bundled meal-plan file is present and decodes")
    func bundledFileDecodes() async throws {
        let package = try MealImportManager.loadBundledPackage()
        #expect(package.version == 1)
        #expect(!package.meals.isEmpty)
        // The Reminders source list has 24 items.
        #expect(package.meals.count == 24)
    }

    @Test("Bundled meals all have non-empty names and at least one course")
    func bundledMealsAreWellFormed() async throws {
        let package = try MealImportManager.loadBundledPackage()
        for meal in package.meals {
            #expect(!meal.name.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!meal.effectiveCourses.isEmpty)
            #expect(meal.effectiveCourses.allSatisfy {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            })
        }
    }

    @Test("Importing the bundled file into an empty store inserts every meal")
    func bundledImportEndToEnd() async throws {
        let container = makeMealImportContainer()
        let context = container.mainContext
        let package = try MealImportManager.loadBundledPackage()

        let result = try MealImportManager.importPackage(
            package,
            into: context,
            existingMeals: [],
            existingRecipes: []
        )

        #expect(result.importedCount == package.meals.count)
        #expect(result.skippedDuplicateCount == 0)

        let stored = try context.fetch(FetchDescriptor<Meal>())
        #expect(stored.count == package.meals.count)
    }

    @Test("Re-importing the bundled file is a no-op (all duplicates)")
    func bundledImportIsIdempotent() async throws {
        let container = makeMealImportContainer()
        let context = container.mainContext
        let package = try MealImportManager.loadBundledPackage()

        _ = try MealImportManager.importPackage(
            package,
            into: context,
            existingMeals: [],
            existingRecipes: []
        )
        let firstFetch = try context.fetch(FetchDescriptor<Meal>())

        let secondResult = try MealImportManager.importPackage(
            package,
            into: context,
            existingMeals: firstFetch,
            existingRecipes: []
        )
        #expect(secondResult.importedCount == 0)
        #expect(secondResult.skippedDuplicateCount == package.meals.count)

        let finalFetch = try context.fetch(FetchDescriptor<Meal>())
        #expect(finalFetch.count == package.meals.count)
    }
}
