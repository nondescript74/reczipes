//
//  RecipeExtractorTests.swift
//  Reczipes2Tests
//
//  Testing utilities and examples for recipe extraction
//

import Testing
import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import Reczipes2

@Suite("Recipe Extractor Tests")
struct RecipeExtractorTests {
    
    // MARK: - Image Preprocessing Tests
    
    @Test("Image preprocessing returns valid data")
    func testImagePreprocessing() async throws {
        // Generate a test image instead of loading from assets
        guard let testImage = TestImageGenerator.generateTestRecipeImage() else {
            throw TestSkipError()
        }
        
        let imagePreprocessor = ImagePreprocessor()
        
        // Test preprocessing
        let processedData = imagePreprocessor.preprocessForOCR(testImage)
        #expect(processedData != nil, "Preprocessing should return data")
        
        // Verify processed image can be decoded
        if let processedData = processedData {
            let processedImage = PlatformImage(data: processedData)
            #expect(processedImage != nil, "Processed data should create valid image")
        }
    }
    
    @Test("Lightweight preprocessing returns valid data")
    func testLightweightPreprocessing() async throws {
        guard let testImage = TestImageGenerator.generateTestRecipeImage() else {
            throw TestSkipError()
        }
        
        let imagePreprocessor = ImagePreprocessor()
        let processedData = imagePreprocessor.preprocessLightweight(testImage)
        #expect(processedData != nil, "Lightweight preprocessing should return data")
    }
    
    // MARK: - Recipe Model Tests
    
    @Test("Recipe model ingredient initialization")
    @MainActor
    func testRecipeModelInitialization() async throws {
        let ingredient = Ingredient(
            quantity: "1",
            unit: "cup",
            name: "flour",
            preparation: "sifted"
        )
        
        #expect(ingredient.quantity == "1")
        #expect(ingredient.unit == "cup")
        #expect(ingredient.name == "flour")
        #expect(ingredient.preparation == "sifted")
    }
    
    @Test("Recipe with multiple sections")
    @MainActor
    func testRecipeWithMultipleSections() async throws {
        let ingredientSections = [
            IngredientSection(
                title: "For the dough",
                ingredients: [
                    Ingredient(quantity: "2", unit: "cups", name: "flour")
                ]
            ),
            IngredientSection(
                title: "For the filling",
                ingredients: [
                    Ingredient(quantity: "1", unit: "cup", name: "sugar")
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
        
        let recipe = RecipeX(
            title: "Test Recipe",
            recipeYield: "4 servings",
            ingredientSectionsData: try JSONEncoder().encode(ingredientSections),
            instructionSectionsData: try JSONEncoder().encode(instructionSections)
        )
        
        #expect(recipe.ingredientSections.count == 2)
        #expect(recipe.instructionSections.count == 1)
    }
    
    // MARK: - JSON Parsing Tests
    
    @Test("Recipe response JSON parsing")
    @MainActor
    func testRecipeResponseParsing() async throws {
        let json = """
        {
            "title": "Test Recipe",
            "yield": "4 servings",
            "ingredientSections": [{
                "ingredients": [{
                    "name": "flour",
                    "quantity": "1",
                    "unit": "cup"
                }]
            }],
            "instructionSections": [{
                "steps": [{
                    "stepNumber": 1,
                    "text": "Mix well"
                }]
            }]
        }
        """
        
        let jsonData = json.data(using: .utf8)!
        
        let recipeResponse = try JSONDecoder().decode(RecipeResponse.self, from: jsonData)
        
        #expect(recipeResponse.title == "Test Recipe")
        #expect(recipeResponse.yield == "4 servings")
        #expect(recipeResponse.ingredientSections.count == 1)
        #expect(recipeResponse.instructionSections.count == 1)
        
        // Test conversion to RecipeX
        let recipe = recipeResponse.toRecipeX()
        
        #expect(recipe.title == "Test Recipe")
        #expect(recipe.recipeYield == "4 servings")
        #expect(recipe.ingredientSections.count == 1)
        #expect(recipe.instructionSections.count == 1)
    }
    
    // MARK: - Keychain Tests
    
    @Test("Keychain storage and retrieval")
    func testKeychainStorage() async {
        let testKey = "test_api_key_\(UUID().uuidString)"
        let testValue = "sk-ant-test-key-123"
        
        // Test save
        let saveSuccess = await KeychainManager.shared.save(key: testKey, value: testValue)
        #expect(saveSuccess, "Should save to keychain")
        
        // Test retrieve
        let retrieved = await KeychainManager.shared.get(key: testKey)
        #expect(retrieved == testValue, "Should retrieve correct value")
        
        // Test delete
        let deleteSuccess = await KeychainManager.shared.delete(key: testKey)
        #expect(deleteSuccess, "Should delete from keychain")
        
        // Verify deleted
        let afterDelete = await KeychainManager.shared.get(key: testKey)
        #expect(afterDelete == nil, "Should be nil after deletion")
    }
}

// MARK: - Test Skip Error

struct TestSkipError: Error {
    let reason: String
    
    init(reason: String = "Test skipped") {
        self.reason = reason
    }
}


// MARK: - Debugging Utilities

extension RecipeExtractorViewModel {
    
    /// Debug helper to print extraction details
    @MainActor
    func debugPrint() {
        print("=== Recipe Extractor Debug Info ===")
        print("Is Loading: \(isLoading)")
        print("Use Preprocessing: \(usePreprocessing)")
        print("Error Message: \(errorMessage ?? "none")")
        print("Has Selected Image: \(selectedImage != nil)")
        print("Has Processed Image: \(processedImage != nil)")
        print("Has Extracted Recipe: \(extractedRecipe != nil)")
        
        if let recipe = extractedRecipe {
            print("\n=== Extracted Recipe ===")
            print("Title: \(String(describing: recipe.title))")
            print("Yield: \(recipe.yield ?? "none")")
            print("Ingredient Sections: \(recipe.ingredientSections.count)")
            print("Instruction Sections: \(recipe.instructionSections.count)")
            print("Notes: \(recipe.notes.count)")
        }
        print("==================================")
    }
}




// MARK: - Test Image Generation

class TestImageGenerator {
    
    /// Generate a simple test image with text
    static func generateTestRecipeImage() -> PlatformImage? {
        let size = CGSize(width: 400, height: 600)
        
        return TestImageRenderer.image(size: size) { context in
            // Background
            TestColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Title
            let title = "Test Recipe"
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: TestFont.boldSystemFont(ofSize: 24),
                .foregroundColor: TestColor.black
            ]
            title.draw(at: CGPoint(x: 20, y: 20), withAttributes: titleAttributes)
            
            // Ingredients
            let ingredients = "Ingredients:\n• 1 cup flour\n• 2 eggs\n• 1 tsp salt"
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: TestFont.systemFont(ofSize: 16),
                .foregroundColor: TestColor.black
            ]
            ingredients.draw(at: CGPoint(x: 20, y: 60), withAttributes: bodyAttributes)
            
            // Instructions
            let instructions = "Instructions:\n1. Mix ingredients\n2. Bake at 350°F"
            instructions.draw(at: CGPoint(x: 20, y: 160), withAttributes: bodyAttributes)
        }
    }
}

// MARK: - Performance Testing

@Suite("Recipe Extractor Performance Tests")
struct RecipeExtractorPerformanceTests {
    
    @Test("Image preprocessing performance", .timeLimit(.minutes(1)))
    func testImagePreprocessingPerformance() async throws {
        guard let testImage = TestImageGenerator.generateTestRecipeImage() else {
            throw TestSkipError(reason: "Test image not available")
        }
        
        let preprocessor = ImagePreprocessor()
        
        // Run preprocessing and measure time
        let startTime = Date()
        _ = preprocessor.preprocessForOCR(testImage)
        let duration = Date().timeIntervalSince(startTime)
        
        // Verify it completes in reasonable time
        // Note: Simulator performance can be slower, so we use a generous limit
        // On actual devices, this typically completes in < 2 seconds
        #expect(duration < 15.0, "Preprocessing should complete in under 15 seconds (simulator), took \(duration)s")
        
        if duration > 5.0 {
            print("⚠️ Preprocessing took \(String(format: "%.3f", duration))s - slower than ideal (consider testing on device)")
        } else {
            print("✓ Image preprocessing completed in \(String(format: "%.3f", duration))s")
        }
    }
    
    @Test("Recipe JSON parsing performance", .timeLimit(.minutes(1)))
    @MainActor
    func testRecipeJSONParsingPerformance() async throws {
        let json = createLargeRecipeJSON()
        let jsonData = json.data(using: .utf8)!
        
        // Run parsing and measure time
        let startTime = Date()
        _ = try JSONDecoder().decode(RecipeResponse.self, from: jsonData)
        let duration = Date().timeIntervalSince(startTime)
        
        // Verify it completes in reasonable time (< 1 second)
        #expect(duration < 1.0, "JSON parsing should complete in under 1 second, took \(duration)s")
        print("✓ JSON parsing completed in \(String(format: "%.3f", duration))s")
    }
    
    private func createLargeRecipeJSON() -> String {
        // Generate JSON for a recipe with many sections
        return """
        {
            "title": "Complex Recipe",
            "yield": "12 servings",
            "ingredientSections": [\(String(repeating: """
                {"ingredients": [{"quantity": "1", "unit": "cup", "name": "ingredient"}]},
                """, count: 10))
                {"ingredients": [{"quantity": "1", "unit": "cup", "name": "ingredient"}]}
            ],
            "instructionSections": [\(String(repeating: """
                {"steps": [{"stepNumber": 1, "text": "Do something"}]},
                """, count: 10))
                {"steps": [{"stepNumber": 1, "text": "Do something"}]}
            ]
        }
        """
    }
}
