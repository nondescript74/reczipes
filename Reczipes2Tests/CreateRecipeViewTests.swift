import Testing
import SwiftUI
import SwiftData
@testable import Reczipes2

@Suite("CreateRecipeView Tests")
@MainActor
struct CreateRecipeViewTests {
    
    // MARK: - Test Data Helpers
    
    private func createTestContainer() -> ModelContainer {
        let schema = Schema([RecipeX.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
    
    // MARK: - Ingredient Section Tests
    
    @Test("Adding multiple ingredients should not crash")
    func testAddingMultipleIngredients() async throws {
        var ingredientSections = [
            IngredientSection(
                title: nil,
                ingredients: [Ingredient(quantity: nil, unit: nil, name: "", preparation: nil)],
                transitionNote: nil
            )
        ]
        
        let sectionID = ingredientSections[0].id
        
        // Add 10 ingredients to stress test
        for i in 1...10 {
            guard let index = ingredientSections.firstIndex(where: { $0.id == sectionID }) else {
                throw TestError.sectionNotFound
            }
            ingredientSections[index].ingredients.append(
                Ingredient(quantity: "\(i)", unit: "cup", name: "Ingredient \(i)", preparation: nil)
            )
        }
        
        // Verify we have 11 ingredients (1 initial + 10 added)
        #expect(ingredientSections[0].ingredients.count == 11)
    }
    
    @Test("Deleting ingredients should maintain stable indices")
    func testDeletingIngredients() async throws {
        var ingredientSections = [
            IngredientSection(
                title: nil,
                ingredients: [
                    Ingredient(quantity: "1", unit: "cup", name: "Flour", preparation: nil),
                    Ingredient(quantity: "2", unit: "cups", name: "Sugar", preparation: nil),
                    Ingredient(quantity: "3", unit: "tbsp", name: "Butter", preparation: nil)
                ],
                transitionNote: nil
            )
        ]
        
        let sectionID = ingredientSections[0].id
        let ingredientToDelete = ingredientSections[0].ingredients[1] // Sugar
        
        // Delete the middle ingredient
        guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }) else {
            throw TestError.sectionNotFound
        }
        ingredientSections[sectionIndex].ingredients.removeAll(where: { $0.id == ingredientToDelete.id })
        
        // Verify we have 2 ingredients left
        #expect(ingredientSections[0].ingredients.count == 2)
        
        // Verify the correct ingredient was deleted
        #expect(ingredientSections[0].ingredients[0].name == "Flour")
        #expect(ingredientSections[0].ingredients[1].name == "Butter")
    }
    
    @Test("Adding ingredient after deletion should work")
    func testAddingAfterDeletion() async throws {
        var ingredientSections = [
            IngredientSection(
                title: nil,
                ingredients: [
                    Ingredient(quantity: "1", unit: "cup", name: "Flour", preparation: nil),
                    Ingredient(quantity: "2", unit: "cups", name: "Sugar", preparation: nil)
                ],
                transitionNote: nil
            )
        ]
        
        let sectionID = ingredientSections[0].id
        let ingredientToDelete = ingredientSections[0].ingredients[0]
        
        // Delete first ingredient
        guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }) else {
            throw TestError.sectionNotFound
        }
        ingredientSections[sectionIndex].ingredients.removeAll(where: { $0.id == ingredientToDelete.id })
        
        // Add new ingredient
        ingredientSections[sectionIndex].ingredients.append(
            Ingredient(quantity: "3", unit: "tbsp", name: "Butter", preparation: nil)
        )
        
        // Verify we have 2 ingredients
        #expect(ingredientSections[0].ingredients.count == 2)
        #expect(ingredientSections[0].ingredients[0].name == "Sugar")
        #expect(ingredientSections[0].ingredients[1].name == "Butter")
    }
    
    // MARK: - Instruction Section Tests
    
    @Test("Adding multiple instruction steps should not crash")
    func testAddingMultipleSteps() async throws {
        var instructionSections = [
            InstructionSection(
                title: nil,
                steps: [InstructionStep(stepNumber: 1, text: "")]
            )
        ]
        
        let sectionID = instructionSections[0].id
        
        // Add 10 steps to stress test
        for i in 2...11 {
            guard let index = instructionSections.firstIndex(where: { $0.id == sectionID }) else {
                throw TestError.sectionNotFound
            }
            instructionSections[index].steps.append(
                InstructionStep(stepNumber: i, text: "Step \(i)")
            )
        }
        
        // Verify we have 11 steps (1 initial + 10 added)
        #expect(instructionSections[0].steps.count == 11)
    }
    
    @Test("Deleting steps should maintain stable indices")
    func testDeletingSteps() async throws {
        var instructionSections = [
            InstructionSection(
                title: nil,
                steps: [
                    InstructionStep(stepNumber: 1, text: "Preheat oven"),
                    InstructionStep(stepNumber: 2, text: "Mix ingredients"),
                    InstructionStep(stepNumber: 3, text: "Bake for 30 minutes")
                ]
            )
        ]
        
        let sectionID = instructionSections[0].id
        let stepToDelete = instructionSections[0].steps[1] // Mix ingredients
        
        // Delete the middle step
        guard let sectionIndex = instructionSections.firstIndex(where: { $0.id == sectionID }) else {
            throw TestError.sectionNotFound
        }
        instructionSections[sectionIndex].steps.removeAll(where: { $0.id == stepToDelete.id })
        
        // Renumber steps
        for i in instructionSections[sectionIndex].steps.indices {
            instructionSections[sectionIndex].steps[i].stepNumber = i + 1
        }
        
        // Verify we have 2 steps left
        #expect(instructionSections[0].steps.count == 2)
        
        // Verify the correct step was deleted
        #expect(instructionSections[0].steps[0].text == "Preheat oven")
        #expect(instructionSections[0].steps[0].stepNumber == 1)
        #expect(instructionSections[0].steps[1].text == "Bake for 30 minutes")
        #expect(instructionSections[0].steps[1].stepNumber == 2)
    }
    
    @Test("Renumbering steps after deletion should work correctly")
    func testRenumberingSteps() async throws {
        var instructionSections = [
            InstructionSection(
                title: nil,
                steps: [
                    InstructionStep(stepNumber: 1, text: "Step 1"),
                    InstructionStep(stepNumber: 2, text: "Step 2"),
                    InstructionStep(stepNumber: 3, text: "Step 3"),
                    InstructionStep(stepNumber: 4, text: "Step 4")
                ]
            )
        ]
        
        let sectionID = instructionSections[0].id
        let stepToDelete = instructionSections[0].steps[1] // Step 2
        
        // Delete step 2
        guard let sectionIndex = instructionSections.firstIndex(where: { $0.id == sectionID }) else {
            throw TestError.sectionNotFound
        }
        instructionSections[sectionIndex].steps.removeAll(where: { $0.id == stepToDelete.id })
        
        // Renumber steps
        for i in instructionSections[sectionIndex].steps.indices {
            instructionSections[sectionIndex].steps[i].stepNumber = i + 1
        }
        
        // Verify renumbering
        #expect(instructionSections[0].steps.count == 3)
        #expect(instructionSections[0].steps[0].stepNumber == 1)
        #expect(instructionSections[0].steps[1].stepNumber == 2)
        #expect(instructionSections[0].steps[2].stepNumber == 3)
    }
    
    // MARK: - Multiple Section Tests
    
    @Test("Adding multiple ingredient sections should work")
    func testMultipleIngredientSections() async throws {
        var ingredientSections = [
            IngredientSection(
                title: "Dry Ingredients",
                ingredients: [Ingredient(quantity: "1", unit: "cup", name: "Flour", preparation: nil)],
                transitionNote: nil
            )
        ]
        
        // Add second section
        ingredientSections.append(
            IngredientSection(
                title: "Wet Ingredients",
                ingredients: [Ingredient(quantity: "2", unit: "cups", name: "Milk", preparation: nil)],
                transitionNote: nil
            )
        )
        
        #expect(ingredientSections.count == 2)
        #expect(ingredientSections[0].title == "Dry Ingredients")
        #expect(ingredientSections[1].title == "Wet Ingredients")
    }
    
    @Test("Deleting a section should work")
    func testDeletingSection() async throws {
        var ingredientSections = [
            IngredientSection(
                title: "Section 1",
                ingredients: [Ingredient(quantity: "1", unit: "cup", name: "Flour", preparation: nil)],
                transitionNote: nil
            ),
            IngredientSection(
                title: "Section 2",
                ingredients: [Ingredient(quantity: "2", unit: "cups", name: "Sugar", preparation: nil)],
                transitionNote: nil
            )
        ]
        
        let sectionToDelete = ingredientSections[0]
        
        // Delete first section
        ingredientSections.removeAll(where: { $0.id == sectionToDelete.id })
        
        #expect(ingredientSections.count == 1)
        #expect(ingredientSections[0].title == "Section 2")
    }
    
    // MARK: - Notes Tests
    
    @Test("Adding and deleting notes should work")
    func testNotesManagement() async throws {
        var notes: [RecipeNote] = []
        
        // Add notes
        notes.append(RecipeNote(type: .tip, text: "Tip 1"))
        notes.append(RecipeNote(type: .warning, text: "Warning 1"))
        notes.append(RecipeNote(type: .substitution, text: "Substitution 1"))
        
        #expect(notes.count == 3)
        
        // Delete middle note
        let noteToDelete = notes[1]
        notes.removeAll(where: { $0.id == noteToDelete.id })
        
        #expect(notes.count == 2)
        #expect(notes[0].type == .tip)
        #expect(notes[1].type == .substitution)
    }
    
    // MARK: - Validation Tests
    
    @Test("Empty ingredients should be detected")
    func testEmptyIngredientsDetection() async throws {
        let ingredientSections = [
            IngredientSection(
                title: nil,
                ingredients: [
                    Ingredient(quantity: nil, unit: nil, name: "", preparation: nil),
                    Ingredient(quantity: nil, unit: nil, name: "  ", preparation: nil)
                ],
                transitionNote: nil
            )
        ]
        
        let isEmpty = ingredientSections.allSatisfy { section in
            section.ingredients.allSatisfy { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        
        #expect(isEmpty == true)
    }
    
    @Test("Non-empty ingredients should be detected")
    func testNonEmptyIngredientsDetection() async throws {
        let ingredientSections = [
            IngredientSection(
                title: nil,
                ingredients: [
                    Ingredient(quantity: "1", unit: "cup", name: "Flour", preparation: nil)
                ],
                transitionNote: nil
            )
        ]
        
        let isEmpty = ingredientSections.allSatisfy { section in
            section.ingredients.allSatisfy { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        
        #expect(isEmpty == false)
    }
    
    @Test("Empty instructions should be detected")
    func testEmptyInstructionsDetection() async throws {
        let instructionSections = [
            InstructionSection(
                title: nil,
                steps: [
                    InstructionStep(stepNumber: 1, text: ""),
                    InstructionStep(stepNumber: 2, text: "  ")
                ]
            )
        ]
        
        let isEmpty = instructionSections.allSatisfy { section in
            section.steps.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        
        #expect(isEmpty == true)
    }
    
    @Test("Non-empty instructions should be detected")
    func testNonEmptyInstructionsDetection() async throws {
        let instructionSections = [
            InstructionSection(
                title: nil,
                steps: [
                    InstructionStep(stepNumber: 1, text: "Mix ingredients")
                ]
            )
        ]
        
        let isEmpty = instructionSections.allSatisfy { section in
            section.steps.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        
        #expect(isEmpty == false)
    }
    
    // MARK: - UUID Stability Tests
    
    @Test("Ingredient IDs should remain stable after modifications")
    func testIngredientIDStability() async throws {
        var ingredientSections = [
            IngredientSection(
                title: nil,
                ingredients: [
                    Ingredient(quantity: "1", unit: "cup", name: "Flour", preparation: nil),
                    Ingredient(quantity: "2", unit: "cups", name: "Sugar", preparation: nil)
                ],
                transitionNote: nil
            )
        ]
        
        let originalFlourID = ingredientSections[0].ingredients[0].id
        let originalSugarID = ingredientSections[0].ingredients[1].id
        
        // Add another ingredient
        let sectionID = ingredientSections[0].id
        guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }) else {
            throw TestError.sectionNotFound
        }
        ingredientSections[sectionIndex].ingredients.append(
            Ingredient(quantity: "3", unit: "tbsp", name: "Butter", preparation: nil)
        )
        
        // Verify original IDs haven't changed
        #expect(ingredientSections[0].ingredients[0].id == originalFlourID)
        #expect(ingredientSections[0].ingredients[1].id == originalSugarID)
    }
    
    @Test("Step IDs should remain stable after modifications")
    func testStepIDStability() async throws {
        var instructionSections = [
            InstructionSection(
                title: nil,
                steps: [
                    InstructionStep(stepNumber: 1, text: "Step 1"),
                    InstructionStep(stepNumber: 2, text: "Step 2")
                ]
            )
        ]
        
        let originalStep1ID = instructionSections[0].steps[0].id
        let originalStep2ID = instructionSections[0].steps[1].id
        
        // Add another step
        let sectionID = instructionSections[0].id
        guard let sectionIndex = instructionSections.firstIndex(where: { $0.id == sectionID }) else {
            throw TestError.sectionNotFound
        }
        instructionSections[sectionIndex].steps.append(
            InstructionStep(stepNumber: 3, text: "Step 3")
        )
        
        // Verify original IDs haven't changed
        #expect(instructionSections[0].steps[0].id == originalStep1ID)
        #expect(instructionSections[0].steps[1].id == originalStep2ID)
    }
    
    // MARK: - Stress Tests
    
    @Test("Rapid add/delete operations should not crash", .timeLimit(.minutes(1)))
    func testRapidOperations() async throws {
        var ingredientSections = [
            IngredientSection(
                title: nil,
                ingredients: [Ingredient(quantity: nil, unit: nil, name: "", preparation: nil)],
                transitionNote: nil
            )
        ]
        
        let sectionID = ingredientSections[0].id
        
        // Perform 100 rapid add/delete cycles
        for cycle in 0..<100 {
            guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }) else {
                throw TestError.sectionNotFound
            }
            
            // Add 5 ingredients
            for i in 1...5 {
                ingredientSections[sectionIndex].ingredients.append(
                    Ingredient(quantity: "\(i)", unit: "cup", name: "Ingredient \(cycle)-\(i)", preparation: nil)
                )
            }
            
            // Delete 3 random ingredients (but keep at least 1)
            while ingredientSections[sectionIndex].ingredients.count > 2 {
                let randomIndex = Int.random(in: 1..<ingredientSections[sectionIndex].ingredients.count)
                let ingredientToDelete = ingredientSections[sectionIndex].ingredients[randomIndex]
                ingredientSections[sectionIndex].ingredients.removeAll(where: { $0.id == ingredientToDelete.id })
            }
        }
        
        // Should still have at least 1 ingredient
        #expect(ingredientSections[0].ingredients.count >= 1)
    }
    
    // MARK: - Error Types
    
    enum TestError: Error {
        case sectionNotFound
    }
}

// MARK: - Integration Test Suite

@Suite("CreateRecipeView Integration Tests")
@MainActor
struct CreateRecipeViewIntegrationTests {
    
    @Test("Complete recipe creation workflow")
    func testCompleteRecipeCreation() async throws {
        // Simulate a complete recipe creation
        let title = "Chocolate Chip Cookies"
        _ = "Best cookies ever!" // headerNotes
        _ = "24 cookies" // recipeYield
        _ = "Grandma's recipe" // reference
        
        // Ingredients
        let ingredientSections = [
            IngredientSection(
                title: "Dry Ingredients",
                ingredients: [
                    Ingredient(quantity: "2", unit: "cups", name: "All-purpose flour", preparation: nil),
                    Ingredient(quantity: "1", unit: "tsp", name: "Baking soda", preparation: nil)
                ],
                transitionNote: nil
            ),
            IngredientSection(
                title: "Wet Ingredients",
                ingredients: [
                    Ingredient(quantity: "1", unit: "cup", name: "Butter", preparation: "softened"),
                    Ingredient(quantity: "2", unit: "large", name: "Eggs", preparation: nil)
                ],
                transitionNote: nil
            )
        ]
        
        // Instructions
        let instructionSections = [
            InstructionSection(
                title: "Preparation",
                steps: [
                    InstructionStep(stepNumber: 1, text: "Preheat oven to 375°F"),
                    InstructionStep(stepNumber: 2, text: "Mix dry ingredients in a bowl")
                ]
            ),
            InstructionSection(
                title: "Baking",
                steps: [
                    InstructionStep(stepNumber: 1, text: "Cream butter and sugar"),
                    InstructionStep(stepNumber: 2, text: "Add eggs one at a time"),
                    InstructionStep(stepNumber: 3, text: "Bake for 10-12 minutes")
                ]
            )
        ]
        
        // Notes
        let notes = [
            RecipeNote(type: .tip, text: "Don't overbake!"),
            RecipeNote(type: .substitution, text: "Can use margarine instead of butter")
        ]
        
        // Validation
        let titleValid = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        let ingredientsNotEmpty = !ingredientSections.allSatisfy { section in
            section.ingredients.allSatisfy { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        
        let instructionsNotEmpty = !instructionSections.allSatisfy { section in
            section.steps.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        
        #expect(titleValid)
        #expect(ingredientsNotEmpty)
        #expect(instructionsNotEmpty)
        #expect(ingredientSections.count == 2)
        #expect(instructionSections.count == 2)
        #expect(notes.count == 2)
    }
}
