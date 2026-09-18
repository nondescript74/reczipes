//
//  RecipeExportImportBasicTests.swift
//  Reczipes2Tests
//
//  Basic tests for RecipeX
//  Created on 1/5/26.
//  Modified 2/2/26

import Testing
import Foundation
import SwiftData
@testable import Reczipes2

@Suite("Recipe Export/Import Basic Tests", .serialized)
@MainActor
struct RecipeExportImportBasicTests {
    
    // MARK: - Test Data Factories
    
    func createCompleteRecipeX() throws -> RecipeX {
        let ingredientSections = [
            IngredientSection(
                title: "Main Ingredients",
                ingredients: [
                    Ingredient(quantity: "2", unit: "cups", name: "flour", preparation: "sifted", metricQuantity: "480", metricUnit: "mL"),
                    Ingredient(quantity: "1", unit: "tsp", name: "salt")
                ],
                transitionNote: "Mix these first"
            )
        ]
        
        let instructionSections = [
            InstructionSection(
                title: "Preparation",
                steps: [
                    InstructionStep(stepNumber: 1, text: "Preheat oven to 350°F"),
                    InstructionStep(stepNumber: 2, text: "Mix ingredients")
                ]
            )
        ]
        
        let notes = [
            RecipeNote(type: .tip, text: "Works best at room temperature"),
            RecipeNote(type: .warning, text: "Don't overmix")
        ]
        
        let encoder = JSONEncoder()
        let ingredientSectionsData = try encoder.encode(ingredientSections)
        let instructionSectionsData = try encoder.encode(instructionSections)
        let notesData = try encoder.encode(notes)
        
        return RecipeX(
            id: UUID(),
            title: "Complete Test Recipe",
            headerNotes: "A comprehensive test recipe",
            recipeYield: "Serves 4",
            reference: "Test Kitchen",
            ingredientSectionsData: ingredientSectionsData,
            instructionSectionsData: instructionSectionsData,
            notesData: notesData,
            imageName: "test-main.jpg",
            additionalImageNames: ["test-1.jpg", "test-2.jpg"]
        )
    }
    
    func createMinimalRecipeX() throws -> RecipeX {
        let ingredientSections = [
            IngredientSection(
                ingredients: [
                    Ingredient(name: "flour")
                ]
            )
        ]
        
        let instructionSections = [
            InstructionSection(
                steps: [
                    InstructionStep(stepNumber: 1, text: "Mix well")
                ]
            )
        ]
        
        let encoder = JSONEncoder()
        let ingredientSectionsData = try encoder.encode(ingredientSections)
        let instructionSectionsData = try encoder.encode(instructionSections)
        
        return RecipeX(
            title: "Minimal Recipe",
            ingredientSectionsData: ingredientSectionsData,
            instructionSectionsData: instructionSectionsData
        )
    }
    
    // MARK: - Smoke Tests
    
    @Test("Absolute simplest test - should always pass")
    func testBasicAssertion() {
        #expect(1 + 1 == 2)
    }
    
    @Test("Test that creates a simple struct")
    func testSimpleStruct() {
        let uuid = UUID()
        #expect(uuid.uuidString.count > 0)
    }
    
    // MARK: - RecipeX Encoding/Decoding Tests
    
    @Test("RecipeX complete properties verification")
    func testCompleteRecipeXProperties() throws {
        let original = try createCompleteRecipeX()
        
        // Verify all fields
        #expect(original.id != nil)
        #expect(original.title == "Complete Test Recipe")
        #expect(original.headerNotes == "A comprehensive test recipe")
        #expect(original.yield == "Serves 4")
        #expect(original.reference == "Test Kitchen")
        #expect(original.imageName == "test-main.jpg")
        #expect(original.additionalImageNames?.count == 2)
        
        // Verify ingredient sections (decoded from Data)
        let ingredientSections = original.ingredientSections
        #expect(ingredientSections.count == 1)
        #expect(ingredientSections[0].title == "Main Ingredients")
        #expect(ingredientSections[0].ingredients.count == 2)
        #expect(ingredientSections[0].transitionNote == "Mix these first")
        
        // Verify ingredients details
        let firstIngredient = ingredientSections[0].ingredients[0]
        #expect(firstIngredient.name == "flour")
        #expect(firstIngredient.quantity == "2")
        #expect(firstIngredient.unit == "cups")
        #expect(firstIngredient.preparation == "sifted")
        #expect(firstIngredient.metricQuantity == "480")
        #expect(firstIngredient.metricUnit == "mL")
        
        // Verify instruction sections (decoded from Data)
        let instructionSections = original.instructionSections
        #expect(instructionSections.count == 1)
        #expect(instructionSections[0].title == "Preparation")
        #expect(instructionSections[0].steps.count == 2)
        
        // Verify instruction steps
        let firstStep = instructionSections[0].steps[0]
        #expect(firstStep.text == "Preheat oven to 350°F")
        #expect(firstStep.stepNumber == 1)
        
        // Verify notes (decoded from Data)
        let notes = original.notes
        #expect(notes.count == 2)
        #expect(notes[0].type == .tip)
        #expect(notes[0].text == "Works best at room temperature")
    }
    
    @Test("RecipeX minimal properties verification")
    func testMinimalRecipeXProperties() throws {
        let original = try createMinimalRecipeX()
        
        // Verify required fields
        #expect(original.title == "Minimal Recipe")
        #expect(original.ingredientSections.count == 1)
        #expect(original.instructionSections.count == 1)
        
        // Verify optional fields are nil
        #expect(original.headerNotes == nil)
        #expect(original.yield == nil)
        #expect(original.reference == nil)
        #expect(original.imageName == nil)
        #expect(original.additionalImageNames == nil)
    }
    
    @Test("RecipeX handles empty section arrays")
    func testRecipeXWithEmptyArrays() throws {
        let encoder = JSONEncoder()
        let emptyIngredientsData = try encoder.encode([IngredientSection]())
        let emptyInstructionsData = try encoder.encode([InstructionSection]())
        let emptyNotesData = try encoder.encode([RecipeNote]())
        
        let model = RecipeX(
            title: "Empty Recipe",
            ingredientSectionsData: emptyIngredientsData,
            instructionSectionsData: emptyInstructionsData,
            notesData: emptyNotesData
        )
        
        #expect(model.ingredientSections.isEmpty)
        #expect(model.instructionSections.isEmpty)
        #expect(model.notes.isEmpty)
    }
    
    // MARK: - Component Tests
    
    @Test("Ingredient preserves all metric and imperial data")
    func testIngredientMetricAndImperialUnits() throws {
        let ingredient = Ingredient(
            quantity: "1",
            unit: "cup",
            name: "flour",
            preparation: "sifted",
            metricQuantity: "240",
            metricUnit: "mL"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(ingredient)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Ingredient.self, from: data)
        
        #expect(decoded.quantity == "1")
        #expect(decoded.unit == "cup")
        #expect(decoded.metricQuantity == "240")
        #expect(decoded.metricUnit == "mL")
        #expect(decoded.preparation == "sifted")
    }
    
    @Test("RecipeNote all types encode correctly")
    func testRecipeNoteTypes() throws {
        let notes = [
            RecipeNote(type: .tip, text: "A helpful tip"),
            RecipeNote(type: .substitution, text: "Use X instead of Y"),
            RecipeNote(type: .warning, text: "Be careful!"),
            RecipeNote(type: .timing, text: "This takes 30 minutes"),
            RecipeNote(type: .general, text: "General information")
        ]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(notes)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode([RecipeNote].self, from: data)
        
        #expect(decoded.count == 5)
        #expect(decoded[0].type == .tip)
        #expect(decoded[1].type == .substitution)
        #expect(decoded[2].type == .warning)
        #expect(decoded[3].type == .timing)
        #expect(decoded[4].type == .general)
    }
    
    @Test("RecipeX computed properties work correctly")
    func testRecipeComputedProperties() throws {
        let ingredientSections = [
            IngredientSection(
                ingredients: [
                    Ingredient(name: "flour"),
                    Ingredient(name: "sugar")
                ]
            )
        ]
        
        let instructionSections = [
            InstructionSection(
                steps: [
                    InstructionStep(stepNumber: 1, text: "Mix ingredients")
                ]
            )
        ]
        
        let encoder = JSONEncoder()
        let ingredientSectionsData = try encoder.encode(ingredientSections)
        let instructionSectionsData = try encoder.encode(instructionSections)
        
        let model = RecipeX(
            title: "Test Recipe",
            ingredientSectionsData: ingredientSectionsData,
            instructionSectionsData: instructionSectionsData,
            imageName: "main.jpg",
            additionalImageNames: ["photo1.jpg", "photo2.jpg"]
        )
        
        // Create in-memory ModelContainer for this test
        let schema = Schema([RecipeX.self, Book.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        context.insert(model)
        
        // Test allImageNames computed property
        #expect(model.allImageNames.count == 3)
        #expect(model.allImageNames.contains("main.jpg"))
        #expect(model.allImageNames.contains("photo1.jpg"))
        
        // Test imageCount computed property — imageName is set, so count is 1
        #expect(model.imageCount == 1)
        
        // Test currentVersion computed property
        #expect(model.currentVersion >= 1)
        
        // Test modificationDate computed property
        #expect(model.modificationDate <= Date())
        
        // Test decoded sections
        #expect(model.ingredientSections.count == 1)
        #expect(model.ingredientSections[0].ingredients.count == 2)
        #expect(model.instructionSections.count == 1)
        #expect(model.instructionSections[0].steps.count == 1)
    }
    
    // MARK: - Backward Compatibility Tests
    
    @Test("RecipeX can be created with minimal data")
    func testMinimalRecipeXCreation() throws {
        // Simulate creating a RecipeX with just title and sections
        let ingredientSections = [
            IngredientSection(
                id: UUID(uuidString: "87654321-4321-4321-4321-210987654321")!,
                ingredients: [
                    Ingredient(
                        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                        name: "flour"
                    )
                ]
            )
        ]
        
        let instructionSections = [
            InstructionSection(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                steps: [
                    InstructionStep(
                        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                        stepNumber: 1,
                        text: "Mix well"
                    )
                ]
            )
        ]
        
        let encoder = JSONEncoder()
        let ingredientSectionsData = try encoder.encode(ingredientSections)
        let instructionSectionsData = try encoder.encode(instructionSections)
        let emptyNotesData = try encoder.encode([RecipeNote]())
        
        let model = RecipeX(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
            title: "Old Recipe",
            ingredientSectionsData: ingredientSectionsData,
            instructionSectionsData: instructionSectionsData,
            notesData: emptyNotesData
        )
        
        #expect(model.title == "Old Recipe")
        #expect(model.additionalImageNames == nil)
        #expect(model.ingredientSections.count == 1)
        #expect(model.instructionSections.count == 1)
        #expect(model.notes.isEmpty)
        
        // Verify IDs are preserved
        #expect(model.id?.uuidString == "12345678-1234-1234-1234-123456789012")
        #expect(model.ingredientSections[0].id.uuidString == "87654321-4321-4321-4321-210987654321")
        #expect(model.ingredientSections[0].ingredients[0].id.uuidString == "11111111-1111-1111-1111-111111111111")
    }
}
