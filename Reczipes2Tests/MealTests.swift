//
//  MealTests.swift
//  Reczipes2Tests
//
//  Tests for the Meal tab: Meal/MealCourse models, course
//  encoding round-trip, derived display properties, and the
//  MealPresets first-launch seeding logic.
//

import Testing
import Foundation
import SwiftData
@testable import Reczipes2

// MARK: - Helpers

@MainActor
private func makeMealContainer() -> ModelContainer {
    let schema = Schema([Meal.self, RecipeX.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try! ModelContainer(for: schema, configurations: [configuration])
}

// MARK: - Meal Model

@Suite("Meal Model Tests")
@MainActor
struct MealModelTests {

    @Test("Default initializer assigns id, timestamps, and empty courses")
    func defaultInit() async throws {
        let before = Date()
        let meal = Meal()
        let after = Date()

        #expect(meal.id != nil)
        #expect(meal.name == nil)
        #expect(meal.mealDescription == nil)
        #expect(meal.notes == nil)
        #expect(meal.isPreset == false)
        #expect(meal.presetIdentifier == nil)
        #expect(meal.courses.isEmpty)
        #expect(meal.courseCount == 0)
        #expect(meal.linkedRecipeCount == 0)

        let created = try #require(meal.dateCreated)
        let modified = try #require(meal.dateModified)
        #expect(created >= before && created <= after)
        #expect(modified >= before && modified <= after)
    }

    @Test("Explicit initializer preserves all values")
    func explicitInit() async throws {
        let id = UUID()
        let recipeID = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let modified = Date(timeIntervalSince1970: 1_700_001_000)
        let courses = [
            MealCourse(name: "Main", recipeID: recipeID, recipeTitle: "Lasagna"),
            MealCourse(name: "Salad")
        ]

        let meal = Meal(
            id: id,
            name: "Family Dinner",
            mealDescription: "Tonight's plan",
            courses: courses,
            notes: "Wine pairing",
            isPreset: true,
            presetIdentifier: "family-dinner",
            dateCreated: created,
            dateModified: modified
        )

        #expect(meal.id == id)
        #expect(meal.name == "Family Dinner")
        #expect(meal.mealDescription == "Tonight's plan")
        #expect(meal.notes == "Wine pairing")
        #expect(meal.isPreset == true)
        #expect(meal.presetIdentifier == "family-dinner")
        #expect(meal.dateCreated == created)
        #expect(meal.dateModified == modified)
        #expect(meal.courses.count == 2)
        #expect(meal.courses[0].name == "Main")
        #expect(meal.courses[0].recipeID == recipeID)
        #expect(meal.courses[0].recipeTitle == "Lasagna")
        #expect(meal.courses[1].recipeID == nil)
    }

    @Test("displayName falls back to 'Untitled Meal' when name is nil")
    func displayNameFallback() async throws {
        let meal = Meal(name: nil)
        #expect(meal.displayName == "Untitled Meal")

        let named = Meal(name: "Sunday Roast")
        #expect(named.displayName == "Sunday Roast")
    }

    @Test("displayName preserves whitespace-only names (no implicit trim)")
    func displayNamePreservesWhitespace() async throws {
        let meal = Meal(name: "   ")
        #expect(meal.displayName == "   ")
    }

    @Test("courseCount and linkedRecipeCount reflect course contents")
    func courseCounts() async throws {
        let recipeID = UUID()
        let meal = Meal(courses: [
            MealCourse(name: "Main", recipeID: recipeID, recipeTitle: "Pasta"),
            MealCourse(name: "Side"),
            MealCourse(name: "Salad", recipeID: UUID(), recipeTitle: "Caesar")
        ])

        #expect(meal.courseCount == 3)
        #expect(meal.linkedRecipeCount == 2)
    }

    @Test("courses returns empty array when coursesData is nil")
    func coursesNilDataReturnsEmpty() async throws {
        let meal = Meal()
        meal.coursesData = nil
        #expect(meal.courses.isEmpty)
        #expect(meal.courseCount == 0)
    }

    @Test("courses returns empty array when coursesData is corrupt")
    func coursesCorruptDataReturnsEmpty() async throws {
        let meal = Meal()
        meal.coursesData = Data([0xFF, 0xFE, 0xFD])
        #expect(meal.courses.isEmpty)
    }
}

// MARK: - Course Accessor

@Suite("Meal Course Accessor Tests")
@MainActor
struct MealCourseAccessorTests {

    @Test("setCourses round-trips through coursesData")
    func setCoursesRoundTrip() async throws {
        let meal = Meal(name: "Test")
        let recipeID = UUID()
        let courses = [
            MealCourse(name: "Main", recipeID: recipeID, recipeTitle: "Roast"),
            MealCourse(name: "Bread", searchQuery: "sourdough")
        ]

        meal.setCourses(courses)

        let decoded = meal.courses
        #expect(decoded.count == 2)
        #expect(decoded[0].id == courses[0].id)
        #expect(decoded[0].name == "Main")
        #expect(decoded[0].recipeID == recipeID)
        #expect(decoded[0].recipeTitle == "Roast")
        #expect(decoded[1].name == "Bread")
        #expect(decoded[1].searchQuery == "sourdough")
    }

    @Test("setCourses updates dateModified")
    func setCoursesUpdatesTimestamp() async throws {
        let oldDate = Date(timeIntervalSince1970: 0)
        let meal = Meal(dateModified: oldDate)
        #expect(meal.dateModified == oldDate)

        let before = Date()
        meal.setCourses([MealCourse(name: "Main")])
        let after = Date()

        let modified = try #require(meal.dateModified)
        #expect(modified >= before && modified <= after)
    }

    @Test("setCourses with empty array clears the course list")
    func setCoursesEmpty() async throws {
        let meal = Meal(courses: [MealCourse(name: "Main")])
        #expect(meal.courseCount == 1)

        meal.setCourses([])
        #expect(meal.courseCount == 0)
        #expect(meal.courses.isEmpty)
    }
}

// MARK: - MealCourse

@Suite("MealCourse Tests")
@MainActor
struct MealCourseTests {

    @Test("Default init generates unique IDs")
    func uniqueDefaultIDs() async throws {
        let a = MealCourse(name: "A")
        let b = MealCourse(name: "B")
        #expect(a.id != b.id)
    }

    @Test("Codable round-trip preserves every field")
    func codableRoundTrip() async throws {
        let original = MealCourse(
            id: UUID(),
            name: "Main",
            recipeID: UUID(),
            recipeTitle: "Spaghetti",
            searchQuery: "spaghetti carbonara"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MealCourse.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.recipeID == original.recipeID)
        #expect(decoded.recipeTitle == original.recipeTitle)
        #expect(decoded.searchQuery == original.searchQuery)
    }

    @Test("Codable round-trip handles nil optional fields")
    func codableRoundTripWithNils() async throws {
        let original = MealCourse(name: "Side")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MealCourse.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == "Side")
        #expect(decoded.recipeID == nil)
        #expect(decoded.recipeTitle == nil)
        #expect(decoded.searchQuery == nil)
    }

    @Test("Hashable: distinct instances with same fields differ by id")
    func hashableEquality() async throws {
        let id = UUID()
        let a = MealCourse(id: id, name: "Main")
        let b = MealCourse(id: id, name: "Main")
        let c = MealCourse(name: "Main") // different auto-generated id

        #expect(a == b)
        #expect(a != c)
        var bag: Set<MealCourse> = []
        bag.insert(a)
        bag.insert(b)
        bag.insert(c)
        #expect(bag.count == 2)
    }

    @Test("Encoded array round-trip preserves order")
    func arrayRoundTripOrder() async throws {
        let courses = [
            MealCourse(name: "First"),
            MealCourse(name: "Second"),
            MealCourse(name: "Third")
        ]
        let data = try JSONEncoder().encode(courses)
        let decoded = try JSONDecoder().decode([MealCourse].self, from: data)

        #expect(decoded.map { $0.name } == ["First", "Second", "Third"])
        #expect(decoded.map { $0.id } == courses.map { $0.id })
    }
}

// MARK: - MealPresets

@Suite("MealPresets Tests", .serialized)
@MainActor
struct MealPresetsTests {

    /// Save and restore the UserDefaults seeding flag so tests don't
    /// pollute each other or the host process state.
    private func withCleanSeedFlag(_ body: () throws -> Void) rethrows {
        let key = MealPresets.didSeedDefaultsKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try body()
    }

    @Test("Preset list is non-empty and has unique identifiers")
    func presetListIntegrity() async throws {
        #expect(!MealPresets.presets.isEmpty)

        let identifiers = MealPresets.presets.map(\.identifier)
        #expect(Set(identifiers).count == identifiers.count)

        for preset in MealPresets.presets {
            #expect(!preset.identifier.isEmpty)
            #expect(!preset.name.isEmpty)
            #expect(!preset.courseNames.isEmpty)
            #expect(preset.courseNames.allSatisfy { !$0.isEmpty })
        }
    }

    @Test("seedIfNeeded inserts every preset on first run")
    func seedingInsertsPresets() async throws {
        try withCleanSeedFlag {
            let container = makeMealContainer()
            let context = container.mainContext

            MealPresets.seedIfNeeded(in: context)

            let descriptor = FetchDescriptor<Meal>()
            let stored = try context.fetch(descriptor)

            #expect(stored.count == MealPresets.presets.count)
            #expect(stored.allSatisfy { $0.isPreset == true })

            let storedIdentifiers = Set(stored.compactMap { $0.presetIdentifier })
            let presetIdentifiers = Set(MealPresets.presets.map(\.identifier))
            #expect(storedIdentifiers == presetIdentifiers)

            #expect(UserDefaults.standard.bool(forKey: MealPresets.didSeedDefaultsKey))
        }
    }

    @Test("Seeded meals contain the configured course names")
    func seededCourseNamesMatch() async throws {
        try withCleanSeedFlag {
            let container = makeMealContainer()
            let context = container.mainContext

            MealPresets.seedIfNeeded(in: context)

            let stored = try context.fetch(FetchDescriptor<Meal>())
            let byIdentifier = Dictionary(
                uniqueKeysWithValues: stored.compactMap { meal -> (String, Meal)? in
                    guard let id = meal.presetIdentifier else { return nil }
                    return (id, meal)
                }
            )

            for preset in MealPresets.presets {
                let meal = try #require(byIdentifier[preset.identifier])
                #expect(meal.name == preset.name)
                #expect(meal.mealDescription == preset.description)
                #expect(meal.courses.map(\.name) == preset.courseNames)
                #expect(meal.courses.allSatisfy { $0.recipeID == nil })
            }
        }
    }

    @Test("seedIfNeeded is a no-op once the UserDefaults flag is set")
    func seedingNoOpAfterFlag() async throws {
        try withCleanSeedFlag {
            let container = makeMealContainer()
            let context = container.mainContext

            MealPresets.seedIfNeeded(in: context)
            let firstCount = try context.fetch(FetchDescriptor<Meal>()).count
            #expect(firstCount == MealPresets.presets.count)

            // Second call should not re-seed.
            MealPresets.seedIfNeeded(in: context)
            let secondCount = try context.fetch(FetchDescriptor<Meal>()).count
            #expect(secondCount == firstCount)
        }
    }

    @Test("seedIfNeeded restores flag and skips when presets already exist in store")
    func seedingDefensiveCheckAgainstExistingPresets() async throws {
        try withCleanSeedFlag {
            let container = makeMealContainer()
            let context = container.mainContext

            // Pre-populate one preset-flagged meal but leave the
            // UserDefaults flag clear — simulates a defaults reset
            // with intact data.
            let existing = Meal(
                name: "Custom Preset",
                courses: [MealCourse(name: "Main")],
                isPreset: true,
                presetIdentifier: "custom-preset"
            )
            context.insert(existing)
            try context.save()
            UserDefaults.standard.removeObject(forKey: MealPresets.didSeedDefaultsKey)

            MealPresets.seedIfNeeded(in: context)

            let stored = try context.fetch(FetchDescriptor<Meal>())
            #expect(stored.count == 1)
            #expect(stored.first?.presetIdentifier == "custom-preset")
            #expect(UserDefaults.standard.bool(forKey: MealPresets.didSeedDefaultsKey))
        }
    }

    @Test("seedIfNeeded ignores non-preset meals when checking for existing presets")
    func seedingProceedsWhenOnlyUserMealsExist() async throws {
        try withCleanSeedFlag {
            let container = makeMealContainer()
            let context = container.mainContext

            // A user-authored meal already exists, but no presets.
            let userMeal = Meal(
                name: "My Dinner",
                courses: [MealCourse(name: "Main")],
                isPreset: false
            )
            context.insert(userMeal)
            try context.save()

            MealPresets.seedIfNeeded(in: context)

            let stored = try context.fetch(FetchDescriptor<Meal>())
            #expect(stored.count == MealPresets.presets.count + 1)

            let presetCount = stored.filter { $0.isPreset == true }.count
            #expect(presetCount == MealPresets.presets.count)
        }
    }
}

// MARK: - SwiftData Persistence

@Suite("Meal Persistence Tests")
@MainActor
struct MealPersistenceTests {

    @Test("Inserted meal is retrievable via fetch and survives a save")
    func insertAndFetch() async throws {
        let container = makeMealContainer()
        let context = container.mainContext

        let meal = Meal(
            name: "Pizza Night",
            mealDescription: "Friday tradition",
            courses: [
                MealCourse(name: "Pizza"),
                MealCourse(name: "Salad")
            ]
        )
        context.insert(meal)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Meal>())
        #expect(fetched.count == 1)
        let stored = try #require(fetched.first)
        #expect(stored.name == "Pizza Night")
        #expect(stored.mealDescription == "Friday tradition")
        #expect(stored.courses.map(\.name) == ["Pizza", "Salad"])
    }

    @Test("Deleting a meal removes it from the store")
    func deleteRemovesMeal() async throws {
        let container = makeMealContainer()
        let context = container.mainContext

        let meal = Meal(name: "Temp Meal")
        context.insert(meal)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Meal>()).count == 1)

        context.delete(meal)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Meal>()).isEmpty)
    }

    @Test("Editing courses on a stored meal persists through fetch")
    func editingCoursesPersists() async throws {
        let container = makeMealContainer()
        let context = container.mainContext

        let meal = Meal(
            name: "Brunch",
            courses: [MealCourse(name: "Eggs")]
        )
        context.insert(meal)
        try context.save()

        // Mutate courses and re-save.
        let recipeID = UUID()
        meal.setCourses([
            MealCourse(name: "Eggs", recipeID: recipeID, recipeTitle: "Frittata"),
            MealCourse(name: "Toast")
        ])
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Meal>())
        let stored = try #require(fetched.first)
        #expect(stored.courses.count == 2)
        #expect(stored.courses[0].recipeID == recipeID)
        #expect(stored.courses[0].recipeTitle == "Frittata")
        #expect(stored.courses[1].name == "Toast")
        #expect(stored.courses[1].recipeID == nil)
    }

    @Test("Preset predicate matches only meals flagged as preset")
    func presetPredicateFiltersCorrectly() async throws {
        let container = makeMealContainer()
        let context = container.mainContext

        context.insert(Meal(name: "User Meal", isPreset: false))
        context.insert(Meal(name: "Preset Meal A", isPreset: true, presetIdentifier: "a"))
        context.insert(Meal(name: "Preset Meal B", isPreset: true, presetIdentifier: "b"))
        try context.save()

        let descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate<Meal> { $0.isPreset == true }
        )
        let presets = try context.fetch(descriptor)
        #expect(presets.count == 2)
        #expect(Set(presets.compactMap { $0.presetIdentifier }) == ["a", "b"])
    }
}
