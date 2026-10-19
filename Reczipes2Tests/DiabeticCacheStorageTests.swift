//
//  DiabeticCacheStorageTests.swift
//  Reczipes2Tests
//
//  Cache storage and retrieval tests with SwiftData
//  Created on 1/3/26.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
import OSLog
@testable import Reczipes2

@Suite("Diabetic Cache Storage Tests", .serialized)
@MainActor
struct DiabeticCacheStorageTests {
    
    private let logger = Logger(subsystem: "com.reczipes.tests", category: "storage")
    
    // MARK: - Model Container Setup
    
    /// Creates an in-memory model container for testing
    private func createTestContainer() throws -> ModelContainer {
        let schema = Schema([
            RecipeX.self,
            Book.self,
            VersionHistoryRecord.self,
            CachedDiabeticAnalysis.self
        ])
        
        let configuration = ModelConfiguration(
            UUID().uuidString,
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
    
    // MARK: - Basic CRUD Tests
    
    @Test("Save and retrieve cache from SwiftData")
    func saveAndRetrieveCache() async throws {
        logger.info("🧪 Testing save and retrieve")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create recipe
        let recipe = createTestRecipe(title: "Storage Test Recipe")
        context.insert(recipe)
        
        logger.info("📝 Created and inserted recipe")
        
        // Create analysis
        let analysis = createMockAnalysis(for: recipe)
        let cached = try CachedDiabeticAnalysis.create(from: analysis, recipe: recipe)
        
        context.insert(cached)
        logger.info("💾 Inserted cache entry")
        
        // Save
        try context.save()
        logger.info("✅ Saved context")
        
        // Retrieve
        let recipeId = recipe.safeID  // Capture the value
        let descriptor = FetchDescriptor<CachedDiabeticAnalysis>(
            predicate: #Predicate { $0.recipeId == recipeId }
        )
        
        let results = try context.fetch(descriptor)
        logger.info("🔍 Fetched \(results.count) results")
        
        #expect(results.count == 1, "Should retrieve one cache entry")
        #expect(results.first?.recipeId == recipe.safeID, "Should retrieve correct entry")
        #expect(results.first?.recipeVersion == recipe.currentVersion, "Version should match")
        
        logger.info("✅ Test passed")
    }
    
    @Test("Update cache entry")
    func updateCacheEntry() async throws {
        logger.info("🧪 Testing cache update")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let recipe = createTestRecipe(title: "Update Test Recipe")
        context.insert(recipe)
        
        // Create initial cache
        let analysis1 = createMockAnalysis(for: recipe, carbCount: 50)
        let cached = try CachedDiabeticAnalysis.create(from: analysis1, recipe: recipe)
        context.insert(cached)
        try context.save()
        
        logger.info("💾 Initial cache saved with carb count: 50")
        
        // Update recipe
        let newIngredients = [
            IngredientSection(ingredients: [
                Ingredient(quantity: "3", unit: "cups", name: "flour")
            ])
        ]
        let newData = try JSONEncoder().encode(newIngredients)
        recipe.updateIngredients(newData)
        
        logger.info("🔧 Recipe updated to version \(recipe.currentVersion)")
        
        // Create new analysis with updated data
        let analysis2 = createMockAnalysis(for: recipe, carbCount: 75)
        
        // Update the existing cache entry
        cached.recipeVersion = recipe.currentVersion
        cached.ingredientsHash = recipe.ingredientsHash ?? ""
        cached.recipeLastModified = recipe.modificationDate
        cached.cachedAt = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        cached.analysisData = try encoder.encode(analysis2)
        
        try context.save()
        logger.info("✅ Cache updated")
        
        // Verify update
        let recipeId = recipe.safeID  // Capture the value
        let descriptor = FetchDescriptor<CachedDiabeticAnalysis>(
            predicate: #Predicate { $0.recipeId == recipeId }
        )
        let results = try context.fetch(descriptor)
        
        #expect(results.count == 1, "Should still have one entry")
        #expect(results.first?.recipeVersion == recipe.currentVersion, "Version should be updated")
        
        let decoded = try results.first?.decodedAnalysis()
        #expect(decoded?.carbCount.totalCarbs == 75, "Carb count should be updated")
        
        logger.info("✅ Test passed")
    }
    
    @Test("Delete cache entry")
    func deleteCacheEntry() async throws {
        logger.info("🧪 Testing cache deletion")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let recipe = createTestRecipe(title: "Delete Test Recipe")
        context.insert(recipe)
        
        let analysis = createMockAnalysis(for: recipe)
        let cached = try CachedDiabeticAnalysis.create(from: analysis, recipe: recipe)
        context.insert(cached)
        try context.save()
        
        logger.info("💾 Cache entry saved")
        
        // Verify exists
        let recipeId = recipe.safeID  // Capture the value
        var descriptor = FetchDescriptor<CachedDiabeticAnalysis>(
            predicate: #Predicate { $0.recipeId == recipeId }
        )
        var results = try context.fetch(descriptor)
        #expect(results.count == 1, "Should have one entry")
        
        // Delete
        context.delete(cached)
        try context.save()
        logger.info("🗑️ Cache entry deleted")
        
        // Verify deleted
        descriptor = FetchDescriptor<CachedDiabeticAnalysis>(
            predicate: #Predicate { $0.recipeId == recipeId }
        )
        results = try context.fetch(descriptor)
        #expect(results.isEmpty, "Should have no entries after deletion")
        
        logger.info("✅ Test passed")
    }
    
    // MARK: - Query Tests
    
    @Test("Query all cache entries")
    func queryAllCacheEntries() async throws {
        logger.info("🧪 Testing query all entries")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create multiple recipes with caches
        let recipeCount = 10
        for i in 1...recipeCount {
            let recipe = createTestRecipe(title: "Recipe \(i)")
            context.insert(recipe)
            
            let analysis = createMockAnalysis(for: recipe)
            let cached = try CachedDiabeticAnalysis.create(from: analysis, recipe: recipe)
            context.insert(cached)
        }
        
        try context.save()
        logger.info("💾 Saved \(recipeCount) cache entries")
        
        // Query all
        let descriptor = FetchDescriptor<CachedDiabeticAnalysis>()
        let results = try context.fetch(descriptor)
        
        logger.info("🔍 Fetched \(results.count) entries")
        #expect(results.count == recipeCount, "Should retrieve all cache entries")
        
        logger.info("✅ Test passed")
    }
    
    @Test("Query stale cache entries")
    func queryStaleCacheEntries() async throws {
        logger.info("🧪 Testing query stale entries")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create some fresh and some stale entries
        for i in 1...5 {
            let recipe = createTestRecipe(title: "Fresh Recipe \(i)")
            context.insert(recipe)
            
            let analysis = createMockAnalysis(for: recipe)
            let cached = try CachedDiabeticAnalysis.create(from: analysis, recipe: recipe)
            context.insert(cached)
        }
        
        for i in 1...3 {
            let recipe = createTestRecipe(title: "Stale Recipe \(i)")
            context.insert(recipe)
            
            let analysis = createMockAnalysis(for: recipe)
            let cached = try CachedDiabeticAnalysis.create(from: analysis, recipe: recipe)
            
            // Make it stale (31 days old)
            let staleDate = Calendar.current.date(byAdding: .day, value: -31, to: Date())!
            cached.cachedAt = staleDate
            
            context.insert(cached)
        }
        
        try context.save()
        logger.info("💾 Saved 5 fresh + 3 stale entries")
        
        // Query all and filter stale
        let descriptor = FetchDescriptor<CachedDiabeticAnalysis>()
        let allResults = try context.fetch(descriptor)
        let staleResults = allResults.filter { $0.isStale }
        
        logger.info("🔍 Total: \(allResults.count), Stale: \(staleResults.count)")
        #expect(allResults.count == 8, "Should have 8 total entries")
        #expect(staleResults.count == 3, "Should have 3 stale entries")
        
        logger.info("✅ Test passed")
    }
    
    @Test("Query by recipe ID")
    func queryByRecipeId() async throws {
        logger.info("🧪 Testing query by recipe ID")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create multiple recipes
        var targetRecipe: RecipeX?
        for i in 1...10 {
            let recipe = createTestRecipe(title: "Recipe \(i)")
            context.insert(recipe)
            
            if i == 5 {
                targetRecipe = recipe
            }
            
            let analysis = createMockAnalysis(for: recipe)
            let cached = try CachedDiabeticAnalysis.create(from: analysis, recipe: recipe)
            context.insert(cached)
        }
        
        try context.save()
        
        guard let targetRecipe = targetRecipe else {
            Issue.record("Target recipe not created")
            return
        }
        
        logger.info("💾 Saved 10 recipes, querying for recipe: \(targetRecipe.safeTitle)")
        
        // Query specific recipe
        let targetId: UUID = targetRecipe.safeID  // Capture the value with explicit type
        let descriptor = FetchDescriptor<CachedDiabeticAnalysis>(
            predicate: #Predicate { $0.recipeId == targetId }
        )
        let results = try context.fetch(descriptor)
        
        logger.info("🔍 Found \(results.count) results")
        #expect(results.count == 1, "Should find exactly one entry")
        #expect(results.first?.recipeId == targetRecipe.safeID, "Should match recipe ID")
        
        logger.info("✅ Test passed")
    }
    
    // MARK: - Bulk Operations
    
    @Test("Bulk delete stale entries")
    func bulkDeleteStaleEntries() async throws {
        logger.info("🧪 Testing bulk delete stale entries")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create 20 entries, half stale
        for i in 1...10 {
            let recipe = createTestRecipe(title: "Fresh \(i)")
            context.insert(recipe)
            
            let analysis = createMockAnalysis(for: recipe)
            let cached = try CachedDiabeticAnalysis.create(from: analysis, recipe: recipe)
            context.insert(cached)
        }
        
        for i in 1...10 {
            let recipe = createTestRecipe(title: "Stale \(i)")
            context.insert(recipe)
            
            let analysis = createMockAnalysis(for: recipe)
            let cached = try CachedDiabeticAnalysis.create(from: analysis, recipe: recipe)
            cached.cachedAt = Calendar.current.date(byAdding: .day, value: -35, to: Date())!
            context.insert(cached)
        }
        
        try context.save()
        logger.info("💾 Created 10 fresh + 10 stale entries")
        
        // Find and delete stale entries
        let descriptor = FetchDescriptor<CachedDiabeticAnalysis>()
        let allResults = try context.fetch(descriptor)
        let staleEntries = allResults.filter { $0.isStale }
        
        logger.info("🗑️ Deleting \(staleEntries.count) stale entries...")
        for entry in staleEntries {
            context.delete(entry)
        }
        
        try context.save()
        
        // Verify deletion
        let remainingResults = try context.fetch(descriptor)
        logger.info("📊 Remaining entries: \(remainingResults.count)")
        
        #expect(remainingResults.count == 10, "Should have 10 entries remaining")
        #expect(remainingResults.allSatisfy { !$0.isStale }, "All remaining should be fresh")
        
        logger.info("✅ Test passed")
    }
    
    @Test("Bulk update cache timestamps")
    func bulkUpdateTimestamps() async throws {
        logger.info("🧪 Testing bulk update timestamps")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create entries
        let count = 5
        for i in 1...count {
            let recipe = createTestRecipe(title: "Recipe \(i)")
            context.insert(recipe)
            
            let analysis = createMockAnalysis(for: recipe)
            let cached = try CachedDiabeticAnalysis.create(from: analysis, recipe: recipe)
            cached.cachedAt = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
            context.insert(cached)
        }
        
        try context.save()
        logger.info("💾 Created \(count) entries with old timestamps")
        
        // Update all timestamps
        let descriptor = FetchDescriptor<CachedDiabeticAnalysis>()
        let allResults = try context.fetch(descriptor)
        
        let newTimestamp = Date()
        for entry in allResults {
            entry.cachedAt = newTimestamp
        }
        
        try context.save()
        logger.info("✅ Updated all timestamps")
        
        // Verify updates
        let updatedResults = try context.fetch(descriptor)
        let allUpdated = updatedResults.allSatisfy { 
            abs($0.cachedAt.timeIntervalSince(newTimestamp)) < 1.0 
        }
        
        #expect(allUpdated, "All timestamps should be updated")
        
        logger.info("✅ Test passed")
    }
    
    // MARK: - Relationship Tests
    
    @Test("Cache without recipe (orphaned entry)")
    func orphanedCacheEntry() async throws {
        logger.info("🧪 Testing orphaned cache entry")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        // Create cache without inserting recipe
        let recipe = createTestRecipe(title: "Not Inserted Recipe")
        let analysis = createMockAnalysis(for: recipe)
        let cached = try CachedDiabeticAnalysis.create(from: analysis, recipe: recipe)
        
        context.insert(cached)
        try context.save()
        
        logger.info("💾 Saved orphaned cache entry")
        
        // Try to find matching recipe
        let recipeId = recipe.safeID  // Capture the value
        let recipeDescriptor = FetchDescriptor<RecipeX>(
            predicate: #Predicate { $0.id == recipeId }
        )
        let recipeResults = try context.fetch(recipeDescriptor)
        
        logger.info("🔍 Found \(recipeResults.count) matching recipes")
        #expect(recipeResults.isEmpty, "Should not find recipe")
        
        // Cache should still exist
        let cacheDescriptor = FetchDescriptor<CachedDiabeticAnalysis>(
            predicate: #Predicate { $0.recipeId == recipeId }
        )
        let cacheResults = try context.fetch(cacheDescriptor)
        
        #expect(cacheResults.count == 1, "Cache should exist independently")
        
        logger.info("✅ Test passed: Cache can exist without recipe")
    }
    
    @Test("Multiple caches for same recipe (cleanup test)")
    func multipleCachesForRecipe() async throws {
        logger.info("🧪 Testing multiple caches for same recipe")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let recipe = createTestRecipe(title: "Multi-Cache Recipe")
        context.insert(recipe)
        
        // Create multiple cache entries for same recipe (simulating duplicate issue)
        for i in 1...3 {
            let analysis = createMockAnalysis(for: recipe, carbCount: Double(i * 10))
            let cached = try CachedDiabeticAnalysis.create(from: analysis, recipe: recipe)
            context.insert(cached)
        }
        
        try context.save()
        logger.info("💾 Created 3 cache entries for same recipe")
        
        // Query
        let recipeId = recipe.safeID  // Capture the value
        let descriptor = FetchDescriptor<CachedDiabeticAnalysis>(
            predicate: #Predicate { $0.recipeId == recipeId }
        )
        let results = try context.fetch(descriptor)
        
        logger.info("🔍 Found \(results.count) cache entries")
        #expect(results.count == 3, "Should have 3 entries")
        
        // Cleanup: Keep only the most recent
        let sorted = results.sorted { $0.cachedAt > $1.cachedAt }
        let toDelete = sorted.dropFirst()
        
        logger.info("🗑️ Deleting \(toDelete.count) old entries...")
        for entry in toDelete {
            context.delete(entry)
        }
        
        try context.save()
        
        // Verify cleanup
        let finalResults = try context.fetch(descriptor)
        #expect(finalResults.count == 1, "Should have only one entry after cleanup")
        
        logger.info("✅ Test passed")
    }
    
    // MARK: - Data Integrity Tests
    
    @Test("Large analysis data storage")
    func largeAnalysisDataStorage() async throws {
        logger.info("🧪 Testing large analysis data storage")
        
        let container = try createTestContainer()
        let context = ModelContext(container)
        
        let recipe = createTestRecipe(title: "Large Data Recipe")
        context.insert(recipe)
        
        // Create analysis with lots of data
        let largeAnalysis = DiabeticInfo(
            id: UUID(),
            recipeId: recipe.safeID,
            lastUpdated: Date(),
            estimatedGlycemicLoad: GlycemicLoad(value: 25.5, explanation: String(repeating: "Long explanation. ", count: 100)),
            glycemicImpactFactors: (1...50).map { i in
                GlycemicFactor(
                    ingredient: "ingredient_\(i)",
                    glycemicIndex: i,
                    impact: .medium,
                    explanation: "Detailed explanation for ingredient \(i)"
                )
            },
            carbCount: CarbInfo(totalCarbs: 100, netCarbs: 90, fiber: 10),
            fiberContent: FiberInfo(total: 10, soluble: 5, insoluble: 5),
            sugarBreakdown: SugarBreakdown(total: 20, added: 10, natural: 10),
            diabeticGuidance: (1...20).map { i in
                GuidanceItem(
                    title: "Guidance \(i)",
                    summary: "Summary \(i)",
                    detailedExplanation: String(repeating: "Detailed guidance. ", count: 50),
                    icon: "heart.fill",
                    color: .red
                )
            },
            portionRecommendations: PortionGuidance(
                recommendedServing: "1/8 recipe",
                servingSize: "100g",
                explanation: String(repeating: "Portion guidance. ", count: 50)
            ),
            substitutionSuggestions: (1...30).map { i in
                IngredientSubstitution(
                    originalIngredient: "ingredient_\(i)",
                    substitute: "substitute_\(i)",
                    reason: "Reason \(i)",
                    nutritionalImprovement: "Improvement \(i)"
                )
            },
            sources: (1...10).map { i in
                VerifiedSource(
                    title: "Source \(i)",
                    organization: "Organization \(i)",
                    credibilityScore: .high
                )
            },
            consensusLevel: .strongConsensus
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let analysisData = try encoder.encode(largeAnalysis)
        logger.info("📊 Analysis data size: \(analysisData.count) bytes")
        
        let cached = CachedDiabeticAnalysis(
            recipeId: recipe.safeID,
            analysisData: analysisData,
            cachedAt: Date(),
            recipeVersion: recipe.currentVersion,
            ingredientsHash: recipe.ingredientsHash ?? "",
            recipeLastModified: recipe.modificationDate
        )
        
        context.insert(cached)
        try context.save()
        logger.info("💾 Saved large analysis data")
        
        // Retrieve and decode
        let recipeId = recipe.safeID  // Capture the value
        let descriptor = FetchDescriptor<CachedDiabeticAnalysis>(
            predicate: #Predicate { $0.recipeId == recipeId }
        )
        let results = try context.fetch(descriptor)
        
        #expect(results.count == 1, "Should retrieve entry")
        
        let decoded = try results.first?.decodedAnalysis()
        #expect(decoded != nil, "Should decode successfully")
        #expect(decoded?.glycemicImpactFactors.count == 50, "Should have all factors")
        #expect(decoded?.diabeticGuidance.count == 20, "Should have all guidance")
        #expect(decoded?.substitutionSuggestions.count == 30, "Should have all substitutions")
        
        logger.info("✅ Test passed")
    }
    
    // MARK: - Helper Methods
    
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
        
        // Encode sections to Data
        let encoder = JSONEncoder()
        let ingredientsData = try? encoder.encode(ingredients)
        let instructionsData = try? encoder.encode(instructions)
        
        return RecipeX(
            id: UUID(),  // Explicitly provide a UUID
            title: title,
            ingredientSectionsData: ingredientsData,
            instructionSectionsData: instructionsData
        )
    }
    
    private func createMockAnalysis(for recipe: RecipeX, carbCount: Double = 50) -> DiabeticInfo {
        DiabeticInfo(
            id: UUID(),
            recipeId: recipe.safeID,  // Use safeID to get non-optional UUID
            lastUpdated: Date(),
            estimatedGlycemicLoad: GlycemicLoad(value: 15.5, explanation: "Moderate"),
            glycemicImpactFactors: [
                GlycemicFactor(ingredient: "flour", glycemicIndex: 70, impact: .high, explanation: "High GI")
            ],
            carbCount: CarbInfo(totalCarbs: carbCount, netCarbs: carbCount - 5, fiber: 5),
            fiberContent: FiberInfo(total: 5, soluble: 2, insoluble: 3),
            sugarBreakdown: SugarBreakdown(total: 10, added: 5, natural: 5),
            diabeticGuidance: [
                GuidanceItem(title: "Watch portions", summary: "Moderate carbs", detailedExplanation: "Keep controlled", icon: "fork.knife", color: .orange)
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
    }
}
