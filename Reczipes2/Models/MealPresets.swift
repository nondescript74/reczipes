//
//  MealPresets.swift
//  Reczipes2
//
//  Built-in preset meals seeded into the user's library on first
//  launch. Presets are inserted with `isPreset = true` and a stable
//  `presetIdentifier` so they aren't re-seeded if the user deletes them.
//

import Foundation
import SwiftData

enum MealPresets {

    /// UserDefaults key that records whether the preset seeding has
    /// run for this install.
    static let didSeedDefaultsKey = "hasSeededMealPresets"

    /// Hardcoded preset list. Each course is a placeholder — the user
    /// links it to a real recipe later (or uses web search to find one).
    static let presets: [PresetMeal] = [
        PresetMeal(
            identifier: "italian-dinner",
            name: "Italian Dinner",
            description: "Classic Italian meal with pasta, bread, and salad.",
            courseNames: ["Spaghetti", "Garlic Bread", "Green Salad"]
        ),
        PresetMeal(
            identifier: "sunday-roast",
            name: "Sunday Roast",
            description: "Traditional roast dinner.",
            courseNames: ["Roast Beef", "Roast Potatoes", "Yorkshire Pudding", "Gravy"]
        ),
        PresetMeal(
            identifier: "taco-night",
            name: "Taco Night",
            description: "Casual Mexican-style dinner.",
            courseNames: ["Beef Tacos", "Spanish Rice", "Refried Beans", "Guacamole"]
        ),
        PresetMeal(
            identifier: "weeknight-stir-fry",
            name: "Weeknight Stir Fry",
            description: "Quick Asian-inspired dinner.",
            courseNames: ["Chicken Stir Fry", "Steamed Rice", "Spring Rolls"]
        ),
        PresetMeal(
            identifier: "thanksgiving",
            name: "Thanksgiving Dinner",
            description: "Holiday spread for the whole table.",
            courseNames: [
                "Roast Turkey",
                "Stuffing",
                "Mashed Potatoes",
                "Cranberry Sauce",
                "Green Bean Casserole",
                "Pumpkin Pie"
            ]
        ),
        PresetMeal(
            identifier: "summer-bbq",
            name: "Summer BBQ",
            description: "Outdoor grilling menu.",
            courseNames: ["Burgers", "Hot Dogs", "Potato Salad", "Coleslaw", "Corn on the Cob"]
        ),
        PresetMeal(
            identifier: "breakfast-classic",
            name: "Classic Breakfast",
            description: "Hearty morning meal.",
            courseNames: ["Scrambled Eggs", "Bacon", "Pancakes", "Hash Browns"]
        ),
        PresetMeal(
            identifier: "sushi-night",
            name: "Sushi Night",
            description: "Japanese-style dinner spread.",
            courseNames: ["Sushi Rolls", "Miso Soup", "Edamame", "Seaweed Salad"]
        )
    ]

    /// Seed the preset meals into the model context if seeding hasn't
    /// already run on this install. Safe to call multiple times — it's
    /// a no-op after the first successful run.
    @MainActor
    static func seedIfNeeded(in modelContext: ModelContext) {
        if UserDefaults.standard.bool(forKey: didSeedDefaultsKey) {
            return
        }

        // Also check whether any presets already exist (defensive in
        // case the defaults flag got cleared but the data is intact).
        let descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate<Meal> { $0.isPreset == true }
        )
        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            UserDefaults.standard.set(true, forKey: didSeedDefaultsKey)
            return
        }

        for preset in presets {
            let courses = preset.courseNames.map { courseName in
                MealCourse(name: courseName)
            }
            let meal = Meal(
                name: preset.name,
                mealDescription: preset.description,
                courses: courses,
                isPreset: true,
                presetIdentifier: preset.identifier
            )
            modelContext.insert(meal)
        }

        do {
            try modelContext.save()
            UserDefaults.standard.set(true, forKey: didSeedDefaultsKey)
        } catch {
            AppLog.error("Failed to seed meal presets: \(error)", category: .storage)
        }
    }
}

struct PresetMeal {
    let identifier: String
    let name: String
    let description: String
    let courseNames: [String]
}
