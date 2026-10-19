//
//  DiabeticCachePerformanceTests.swift
//  Reczipes2Tests
//
//  Performance tests for diabetic analysis caching
//  Created on 1/3/26.
//

import Testing
import Foundation
import OSLog
import SwiftUI
@testable import Reczipes2

@Suite("Diabetic Cache Performance Tests", .serialized)
struct DiabeticCachePerformanceTests {
    
    private let logger = Logger(subsystem: "com.reczipes.tests", category: "performance")
    
    // MARK: - Hash Performance Tests
    
    @Test("Hash calculation performance - small recipe")
    @MainActor
    func hashPerformanceSmall() async throws {
        logger.info("🧪 Testing hash performance (small recipe)")
        
        let ingredients = [
            IngredientSection(ingredients: [
                Ingredient(quantity: "2", unit: "cups", name: "flour"),
                Ingredient(quantity: "1", unit: "tsp", name: "salt"),
                Ingredient(quantity: "3", unit: "", name: "eggs")
            ])
        ]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(ingredients)
        
        // Warm up
        _ = RecipeX.calculateIngredientsHash(from: data)
        
        // Measure performance
        let iterations = 1000
        let startTime = Date()
        
        for _ in 1...iterations {
            _ = RecipeX.calculateIngredientsHash(from: data)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let avgTime = duration / Double(iterations)
        
        logger.info("⏱️ Average time per hash: \(String(format: "%.6f", avgTime * 1000)) ms")
        logger.info("📊 Total for \(iterations) iterations: \(String(format: "%.3f", duration)) seconds")
        
        // Should be very fast - under 1ms per hash for small recipes
        #expect(avgTime < 0.001, "Hash should be calculated in under 1ms for small recipes")
        
        logger.info("✅ Test passed")
    }
    
    @Test("Hash calculation performance - large recipe")
    @MainActor
    func hashPerformanceLarge() async throws {
        logger.info("🧪 Testing hash performance (large recipe)")
        
        // Create a recipe with 100 ingredients
        let ingredients = [
            IngredientSection(ingredients: (1...100).map { i in
                Ingredient(
                    quantity: "\(i)",
                    unit: "unit\(i)",
                    name: "ingredient_\(i)_with_a_really_long_name_to_test_performance"
                )
            })
        ]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(ingredients)
        
        logger.info("📊 Data size: \(data.count) bytes")
        
        // Warm up
        _ = RecipeX.calculateIngredientsHash(from: data)
        
        // Measure performance
        let iterations = 100
        let startTime = Date()
        
        for _ in 1...iterations {
            _ = RecipeX.calculateIngredientsHash(from: data)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let avgTime = duration / Double(iterations)
        
        logger.info("⏱️ Average time per hash: \(String(format: "%.3f", avgTime * 1000)) ms")
        logger.info("📊 Total for \(iterations) iterations: \(String(format: "%.3f", duration)) seconds")
        
        // Should still be reasonably fast - under 10ms per hash
        #expect(avgTime < 0.01, "Hash should be calculated in under 10ms for large recipes")
        
        logger.info("✅ Test passed")
    }
    
    @Test("Hash calculation consistency under load")
    @MainActor
    func hashConsistencyUnderLoad() async throws {
        logger.info("🧪 Testing hash consistency under concurrent load")
        
        let ingredients = [
            IngredientSection(ingredients: [
                Ingredient(quantity: "2", unit: "cups", name: "flour")
            ])
        ]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(ingredients)
        
        // Calculate reference hash
        guard let referenceHash = RecipeX.calculateIngredientsHash(from: data) else {
            Issue.record("Failed to calculate reference hash")
            return
        }
        logger.info("📊 Reference hash: \(referenceHash)")
        
        // Calculate hash concurrently many times
        let iterations = 100
        let startTime = Date()
        
        await withTaskGroup(of: String?.self) { group in
            for _ in 1...iterations {
                group.addTask {
                    RecipeX.calculateIngredientsHash(from: data)
                }
            }
            
            var allHashes: [String] = []
            for await hash in group {
                if let hash = hash {
                    allHashes.append(hash)
                }
            }
            
            let duration = Date().timeIntervalSince(startTime)
            logger.info("⏱️ \(iterations) concurrent hashes in \(String(format: "%.3f", duration)) seconds")
            
            // All hashes should match reference
            let allMatch = allHashes.allSatisfy { $0 == referenceHash }
            #expect(allMatch, "All concurrent hash calculations should produce identical results")
            
            // Check for any anomalies
            let uniqueHashes = Set(allHashes)
            logger.info("📊 Unique hashes: \(uniqueHashes.count) (should be 1)")
            #expect(uniqueHashes.count == 1, "Should only have one unique hash value")
        }
        
        logger.info("✅ Test passed")
    }
    
    // MARK: - Cache Lookup Performance
    
    @Test("Cache validation performance")
    @MainActor
    func cacheValidationPerformance() async throws {
        logger.info("🧪 Testing cache validation performance")
        
        let recipe = createTestRecipe()
        guard let recipeId = recipe.id else {
            Issue.record("Recipe must have ID")
            return
        }
        
        let encoder = JSONEncoder()
        
        let mockAnalysis = DiabeticInfo(
            id: UUID(),
            recipeId: recipeId,
            lastUpdated: Date(),
            estimatedGlycemicLoad: nil,
            glycemicImpactFactors: [],
            carbCount: CarbInfo(totalCarbs: 50, netCarbs: 45, fiber: 5),
            fiberContent: FiberInfo(total: 5),
            sugarBreakdown: SugarBreakdown(total: 10),
            diabeticGuidance: [],
            portionRecommendations: nil,
            substitutionSuggestions: [],
            sources: [],
            consensusLevel: .strongConsensus
        )
        let analysisData = try encoder.encode(mockAnalysis)
        
        let cached = CachedDiabeticAnalysis(
            recipeId: recipeId,
            analysisData: analysisData,
            cachedAt: Date(),
            recipeVersion: recipe.currentVersion,
            ingredientsHash: recipe.ingredientsHash ?? "",
            recipeLastModified: recipe.modificationDate
        )
        
        // Measure validation performance
        let iterations = 10000
        let startTime = Date()
        
        for _ in 1...iterations {
            _ = cached.isValid(for: recipe)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let avgTime = duration / Double(iterations)
        
        logger.info("⏱️ Average validation time: \(String(format: "%.6f", avgTime * 1000)) ms")
        logger.info("📊 Total for \(iterations) validations: \(String(format: "%.3f", duration)) seconds")
        
        // Should be extremely fast - under 0.1ms
        #expect(avgTime < 0.0001, "Cache validation should be under 0.1ms")
        
        logger.info("✅ Test passed")
    }
    
    @Test("Large cache collection performance")
    @MainActor
    func largeCacheCollectionPerformance() async throws {
        logger.info("🧪 Testing large cache collection performance")
        
        let encoder = JSONEncoder()
        
        // Create 1000 cached entries
        logger.info("📝 Creating 1000 cache entries...")
        let cacheCount = 1000
        var caches: [CachedDiabeticAnalysis] = []
        var recipes: [RecipeX] = []
        
        let createStartTime = Date()
        
        for i in 1...cacheCount {
            let recipe = createTestRecipe(title: "Recipe \(i)")
            guard let recipeId = recipe.id else {
                Issue.record("Recipe must have ID")
                continue
            }
            recipes.append(recipe)
            
            let mockAnalysis = DiabeticInfo(
                id: UUID(),
                recipeId: recipeId,
                lastUpdated: Date(),
                estimatedGlycemicLoad: nil,
                glycemicImpactFactors: [],
                carbCount: CarbInfo(totalCarbs: Double(i), netCarbs: Double(i - 5), fiber: 5),
                fiberContent: FiberInfo(total: 5),
                sugarBreakdown: SugarBreakdown(total: 10),
                diabeticGuidance: [],
                portionRecommendations: nil,
                substitutionSuggestions: [],
                sources: [],
                consensusLevel: .strongConsensus
            )
            let analysisData = try encoder.encode(mockAnalysis)
            
            let cached = CachedDiabeticAnalysis(
                recipeId: recipeId,
                analysisData: analysisData,
                cachedAt: Date(),
                recipeVersion: recipe.currentVersion,
                ingredientsHash: recipe.ingredientsHash ?? "",
                recipeLastModified: recipe.modificationDate
            )
            caches.append(cached)
        }
        
        let createDuration = Date().timeIntervalSince(createStartTime)
        logger.info("⏱️ Created \(cacheCount) entries in \(String(format: "%.3f", createDuration)) seconds")
        
        // Test validation of all entries
        logger.info("🔍 Validating all \(cacheCount) entries...")
        let validateStartTime = Date()
        
        var validCount = 0
        for (cache, recipe) in zip(caches, recipes) {
            if cache.isValid(for: recipe) {
                validCount += 1
            }
        }
        
        let validateDuration = Date().timeIntervalSince(validateStartTime)
        logger.info("⏱️ Validated \(cacheCount) entries in \(String(format: "%.3f", validateDuration)) seconds")
        logger.info("📊 Valid entries: \(validCount)/\(cacheCount)")
        
        #expect(validCount == cacheCount, "All entries should be valid")
        #expect(validateDuration < 1.0, "Should validate 1000 entries in under 1 second")
        
        logger.info("✅ Test passed")
    }
    
    // MARK: - Memory Tests
    
    @Test("Memory efficiency of hash storage")
    @MainActor
    func hashMemoryEfficiency() async throws {
        logger.info("🧪 Testing hash memory efficiency")
        
        let encoder = JSONEncoder()
        
        // Create small ingredient list
        let smallIngredients = [
            IngredientSection(ingredients: [
                Ingredient(quantity: "1", unit: "cup", name: "flour")
            ])
        ]
        let smallData = try encoder.encode(smallIngredients)
        
        // Create medium ingredient list (10 ingredients)
        let mediumIngredients = [
            IngredientSection(ingredients: (1...10).map { i in
                Ingredient(quantity: "\(i)", unit: "cup", name: "ingredient_\(i)")
            })
        ]
        let mediumData = try encoder.encode(mediumIngredients)
        
        // Create large ingredient list (100 ingredients with long names)
        let largeIngredients = [
            IngredientSection(ingredients: (1...100).map { i in
                Ingredient(
                    quantity: "\(i)",
                    unit: "tablespoon",
                    name: "ingredient_\(i)_with_very_long_name_for_testing_memory_efficiency"
                )
            })
        ]
        let largeData = try encoder.encode(largeIngredients)
        
        let smallHash = RecipeX.calculateIngredientsHash(from: smallData) ?? ""
        let mediumHash = RecipeX.calculateIngredientsHash(from: mediumData) ?? ""
        let largeHash = RecipeX.calculateIngredientsHash(from: largeData) ?? ""
        
        logger.info("📊 Small data (\(smallData.count) bytes) -> hash: \(smallHash.count) chars")
        logger.info("📊 Medium data (\(mediumData.count) bytes) -> hash: \(mediumHash.count) chars")
        logger.info("📊 Large data (\(largeData.count) bytes) -> hash: \(largeHash.count) chars")
        
        // All hashes should be same length (64 chars)
        #expect(smallHash.count == 64, "Hash should be 64 chars")
        #expect(mediumHash.count == 64, "Hash should be 64 chars")
        #expect(largeHash.count == 64, "Hash should be 64 chars")
        
        // Memory efficiency: Large data produces 64-char hash (massive reduction)
        let compressionRatio = Double(largeData.count) / Double(largeHash.count)
        logger.info("📊 Compression ratio for large data: \(String(format: "%.0f", compressionRatio)):1")
        
        #expect(compressionRatio > 10, "Hash should provide significant space savings")
        
        logger.info("✅ Test passed")
    }
    
    // MARK: - Concurrent Operations
    
    @Test("Concurrent recipe updates performance")
    @MainActor
    func concurrentUpdatesPerformance() async throws {
        logger.info("🧪 Testing concurrent updates performance")
        
        let recipeCount = 50
        let recipes = (1...recipeCount).map { createTestRecipe(title: "Recipe \($0)") }
        
        logger.info("📝 Created \(recipeCount) recipes")
        
        let startTime = Date()
        
        // Update all recipes concurrently
        await withTaskGroup(of: Void.self) { group in
            for recipe in recipes {
                group.addTask { @MainActor in
                    let ingredients = [
                        IngredientSection(ingredients: [
                            Ingredient(quantity: "5", unit: "cups", name: "updated flour")
                        ])
                    ]
                    
                    if let data = try? JSONEncoder().encode(ingredients) {
                        recipe.updateIngredients(data)
                    }
                }
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        logger.info("⏱️ Updated \(recipeCount) recipes concurrently in \(String(format: "%.3f", duration)) seconds")
        
        // Verify all were updated
        let allUpdated = recipes.allSatisfy { $0.currentVersion > 1 }
        #expect(allUpdated, "All recipes should be updated")
        
        // Should complete quickly
        #expect(duration < 5.0, "Concurrent updates should complete in under 5 seconds")
        
        logger.info("✅ Test passed")
    }
    
    @Test("Cache decode performance")
    @MainActor
    func cacheDecodePerformance() async throws {
        logger.info("🧪 Testing cache decode performance")
        
        let recipe = createTestRecipe()
        guard let recipeId = recipe.id else {
            Issue.record("Recipe must have ID")
            return
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let mockAnalysis = DiabeticInfo(
            id: UUID(),
            recipeId: recipeId,
            lastUpdated: Date(),
            estimatedGlycemicLoad: GlycemicLoad(value: 15.5, explanation: "Moderate"),
            glycemicImpactFactors: [
                GlycemicFactor(ingredient: "flour", glycemicIndex: 70, impact: .high, explanation: "High GI"),
                GlycemicFactor(ingredient: "sugar", glycemicIndex: 65, impact: .high, explanation: "High GI")
            ],
            carbCount: CarbInfo(totalCarbs: 50, netCarbs: 45, fiber: 5),
            fiberContent: FiberInfo(total: 5, soluble: 2, insoluble: 3),
            sugarBreakdown: SugarBreakdown(total: 10, added: 5, natural: 5),
            diabeticGuidance: [
                GuidanceItem(title: "Watch portions", summary: "Moderate carbs", detailedExplanation: "Keep portions controlled", icon: "fork.knife", color: .orange)
            ],
            portionRecommendations: PortionGuidance(recommendedServing: "1/4", servingSize: "125g", explanation: "Small portions"),
            substitutionSuggestions: [
                IngredientSubstitution(originalIngredient: "flour", substitute: "almond flour", reason: "Lower GI")
            ],
            sources: [
                VerifiedSource(title: "ADA", organization: "American Diabetes Association", credibilityScore: .high)
            ],
            consensusLevel: .strongConsensus
        )
        
        let analysisData = try encoder.encode(mockAnalysis)
        logger.info("📊 Analysis data size: \(analysisData.count) bytes")
        
        let cached = CachedDiabeticAnalysis(
            recipeId: recipeId,
            analysisData: analysisData,
            cachedAt: Date(),
            recipeVersion: recipe.currentVersion,
            ingredientsHash: recipe.ingredientsHash ?? "",
            recipeLastModified: recipe.modificationDate
        )
        
        // Warm up
        _ = try cached.decodedAnalysis()
        
        // Measure decode performance
        let iterations = 1000
        let startTime = Date()
        
        for _ in 1...iterations {
            _ = try cached.decodedAnalysis()
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let avgTime = duration / Double(iterations)
        
        logger.info("⏱️ Average decode time: \(String(format: "%.3f", avgTime * 1000)) ms")
        logger.info("📊 Total for \(iterations) decodes: \(String(format: "%.3f", duration)) seconds")
        
        #expect(avgTime < 0.01, "Decode should be under 10ms")
        
        logger.info("✅ Test passed")
    }
    
    // MARK: - Stress Tests
    
    @Test("Hash calculation stability under stress")
    @MainActor
    func hashStabilityStress() async throws {
        logger.info("🧪 Testing hash stability under stress")
        
        let encoder = JSONEncoder()
        
        // Create complex ingredient data
        let ingredients = (1...50).map { sectionIndex in
            IngredientSection(
                title: "Section \(sectionIndex)",
                ingredients: (1...20).map { ingredientIndex in
                    Ingredient(
                        quantity: "\(Double(ingredientIndex) * 1.5)",
                        unit: "unit\(ingredientIndex)",
                        name: "ingredient_\(sectionIndex)_\(ingredientIndex)_with_long_name",
                        preparation: "prepared in specific way \(ingredientIndex)"
                    )
                }
            )
        }
        
        let data = try encoder.encode(ingredients)
        logger.info("📊 Complex data size: \(data.count) bytes (\(ingredients.count) sections, \(ingredients.flatMap { $0.ingredients }.count) ingredients)")
        
        // Calculate hash many times
        let iterations = 1000
        var hashes = Set<String>()
        
        let startTime = Date()
        
        for _ in 1...iterations {
            if let hash = RecipeX.calculateIngredientsHash(from: data) {
                hashes.insert(hash)
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        logger.info("⏱️ \(iterations) calculations in \(String(format: "%.3f", duration)) seconds")
        logger.info("📊 Unique hashes: \(hashes.count) (should be 1)")
        
        #expect(hashes.count == 1, "All hashes should be identical")
        // Wall-clock bound; shared CI simulators run several times slower than a Mac.
        #expect(duration < 30.0, "Should complete in under 30 seconds")
        
        logger.info("✅ Test passed")
    }
    
    // MARK: - Helper Methods
    
    @MainActor
    private func createTestRecipe(title: String = "Test Recipe") -> RecipeX {
        let ingredients = [
            IngredientSection(ingredients: [
                Ingredient(quantity: "2", unit: "cups", name: "flour")
            ])
        ]
        
        let instructions = [
            InstructionSection(steps: [
                InstructionStep(stepNumber: 1, text: "Mix ingredients")
            ])
        ]
        
        let ingredientsData = try? JSONEncoder().encode(ingredients)
        let instructionsData = try? JSONEncoder().encode(instructions)
        
        return RecipeX(
            title: title,
            ingredientSectionsData: ingredientsData,
            instructionSectionsData: instructionsData
        )
    }
}
