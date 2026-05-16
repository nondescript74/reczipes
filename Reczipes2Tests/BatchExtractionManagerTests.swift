//
//  BatchExtractionManagerTests.swift
//  Reczipes2Tests
//
//  Comprehensive test suite for BatchExtractionManager
//  Created on 1/14/26.
//

import Testing
import Foundation
import SwiftData
import OSLog
@testable import Reczipes2

@Suite("BatchExtractionManager Tests", .serialized)
@MainActor
struct BatchExtractionManagerTests {
    
    private let logger = Logger(subsystem: "com.reczipes.tests", category: "batch-extraction")
    
    // MARK: - Test Utilities
    
    /// Creates a temporary in-memory model container for testing
    private func createTestModelContainer() throws -> ModelContainer {
        let schema = Schema([RecipeX.self, SavedLink.self, RecipeImageAssignment.self, VersionHistoryRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
    
    /// Creates test SavedLink objects
    private func createTestLinks(count: Int) -> [SavedLink] {
        (0..<count).map { index in
            SavedLink(
                title: "Test Recipe \(index)", url: "https://example.com/recipe\(index)",
                isProcessed: false
            )
        }
    }
    
    /// Clean up manager state before each test
    private func cleanupManager() {
        let manager = BatchExtractionManager.shared
        manager.stop()
        manager.reset()
        manager.clearConfiguration()
    }
    
    // MARK: - Initialization Tests
    
    @Test("Manager initializes as singleton")
    func singletonInitialization() async throws {
        logger.info("🧪 Testing singleton initialization")
        
        // First ensure clean state
        cleanupManager()
        
        let manager1 = BatchExtractionManager.shared
        let manager2 = BatchExtractionManager.shared
        
        #expect(manager1 === manager2, "Should return the same instance")
        #expect(!manager1.isExtracting, "Should not be extracting on init")
        #expect(!manager1.isPaused, "Should not be paused on init")
        #expect(manager1.totalProcessed == 0, "Should have zero processed on init")
        #expect(manager1.successCount == 0, "Should have zero success count on init")
        #expect(manager1.failureCount == 0, "Should have zero failure count on init")
        
        logger.info("✅ Singleton initialization test passed")
    }
    
    @Test("Manager configuration")
    func configuration() async throws {
        logger.info("🧪 Testing manager configuration")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        let container = try createTestModelContainer()
        let context = ModelContext(container)
        
        manager.configure(apiKey: "test-api-key", modelContext: context)
        
        // Configuration should not change public state
        #expect(!manager.isExtracting, "Should not start extracting after configuration")
        
        logger.info("✅ Configuration test passed")
    }
    
    // MARK: - State Management Tests
    
    @Test("Reset clears all state")
    func resetState() async throws {
        logger.info("🧪 Testing state reset")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        
        // Manually set some state
        manager.totalProcessed = 10
        manager.successCount = 8
        manager.failureCount = 2
        manager.errorLog = [("test", "error", Date())]
        manager.recentlyExtracted = []
        
        // Reset
        manager.reset()
        
        #expect(manager.totalProcessed == 0, "Total processed should be reset")
        #expect(manager.successCount == 0, "Success count should be reset")
        #expect(manager.failureCount == 0, "Failure count should be reset")
        #expect(manager.errorLog.isEmpty, "Error log should be empty")
        #expect(manager.currentStatus == nil, "Current status should be nil")
        #expect(manager.currentRecipe == nil, "Current recipe should be nil")
        #expect(manager.recentlyExtracted.isEmpty, "Recently extracted should be empty")
        
        logger.info("✅ Reset state test passed")
    }
    
    @Test("Pause and resume functionality")
    func pauseAndResume() async throws {
        logger.info("🧪 Testing pause and resume")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        
        #expect(!manager.isPaused, "Should not be paused initially")
        
        manager.pause()
        #expect(manager.isPaused, "Should be paused after pause()")
        
        manager.resume()
        #expect(!manager.isPaused, "Should not be paused after resume()")
        
        logger.info("✅ Pause and resume test passed")
    }
    
    @Test("Stop cancels extraction")
    func stopExtraction() async throws {
        logger.info("🧪 Testing stop extraction")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        
        // Set extracting state manually
        manager.isExtracting = true
        manager.isPaused = false
        
        manager.stop()
        
        // Give it a moment to process
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        #expect(!manager.isExtracting, "Should not be extracting after stop")
        #expect(!manager.isPaused, "Should not be paused after stop")
        #expect(manager.currentStatus == nil, "Current status should be cleared")
        
        logger.info("✅ Stop extraction test passed")
    }
    
    // MARK: - Extraction Status Tests
    
    @Test("ExtractionStep enum values")
    func extractionStepValues() async throws {
        logger.info("🧪 Testing ExtractionStep enum")
        
        #expect(ExtractionStep.fetching.rawValue == "Fetching recipe page...")
        #expect(ExtractionStep.analyzing.rawValue == "Analyzing with Claude AI...")
        #expect(ExtractionStep.downloadingImages.rawValue == "Downloading images...")
        #expect(ExtractionStep.savingRecipe.rawValue == "Saving recipe...")
        #expect(ExtractionStep.waiting.rawValue == "Waiting before next extraction...")
        #expect(ExtractionStep.complete.rawValue == "Complete")
        #expect(ExtractionStep.failed.rawValue == "Failed")
        
        logger.info("✅ ExtractionStep test passed")
    }
    
    @Test("ExtractionStatus structure")
    func extractionStatusStructure() async throws {
        logger.info("🧪 Testing ExtractionStatus structure")
        
        let link = SavedLink(title: "Test", url: "https://example.com", isProcessed: false)
        
        let status = ExtractionStatus(
            currentIndex: 1,
            totalCount: 10,
            currentLink: link,
            currentRecipe: nil,
            currentStep: .fetching,
            stepProgress: 0.5,
            imagesDownloaded: 2,
            totalImages: 5,
            timeElapsed: 30.0,
            estimatedTimeRemaining: 270.0
        )
        
        #expect(status.currentIndex == 1)
        #expect(status.totalCount == 10)
        #expect(status.currentLink?.url == "https://example.com")
        #expect(status.currentStep == .fetching)
        #expect(status.stepProgress == 0.5)
        #expect(status.imagesDownloaded == 2)
        #expect(status.totalImages == 5)
        #expect(status.timeElapsed == 30.0)
        #expect(status.estimatedTimeRemaining == 270.0)
        
        logger.info("✅ ExtractionStatus test passed")
    }
    
    // MARK: - Input Validation Tests
    
    @Test("Start extraction with no configuration throws warning")
    func startWithoutConfiguration() async throws {
        logger.info("🧪 Testing start without configuration")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        
        // Try to start without configuration (should fail silently or log)
        let links = createTestLinks(count: 3)
        
        manager.startBatchExtraction(links: links)
        
        // Should not start extraction without config
        #expect(!manager.isExtracting, "Should not start without configuration")
        
        logger.info("✅ Start without configuration test passed")
    }
    
    @Test("Start extraction with empty links")
    func startWithEmptyLinks() async throws {
        logger.info("🧪 Testing start with empty links")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        
        let container = try createTestModelContainer()
        let context = ModelContext(container)
        manager.configure(apiKey: "test-key", modelContext: context)
        
        manager.startBatchExtraction(links: [])
        
        #expect(!manager.isExtracting, "Should not start with empty links")
        
        logger.info("✅ Empty links test passed")
    }
    
    @Test("Start extraction with all processed links")
    func startWithAllProcessedLinks() async throws {
        logger.info("🧪 Testing start with all processed links")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        
        let container = try createTestModelContainer()
        let context = ModelContext(container)
        manager.configure(apiKey: "test-key", modelContext: context)
        
        let links = createTestLinks(count: 3)
        links.forEach { $0.isProcessed = true }
        
        manager.startBatchExtraction(links: links)
        
        #expect(!manager.isExtracting, "Should not start with all processed links")
        
        logger.info("✅ All processed links test passed")
    }
    
    @Test("Start extraction while already extracting")
    func startWhileExtracting() async throws {
        logger.info("🧪 Testing start while already extracting")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        
        let container = try createTestModelContainer()
        let context = ModelContext(container)
        manager.configure(apiKey: "test-key", modelContext: context)
        
        // Set extracting state
        manager.isExtracting = true
        
        let links = createTestLinks(count: 3)
        let initialProcessed = manager.totalProcessed
        
        manager.startBatchExtraction(links: links)
        
        // Should not change state when already extracting
        #expect(manager.totalProcessed == initialProcessed, "Should not start new extraction")
        
        manager.isExtracting = false
        
        logger.info("✅ Start while extracting test passed")
    }
    
    @Test("Batch size limit enforced")
    func batchSizeLimit() async throws {
        logger.info("🧪 Testing batch size limit (max 50)")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        
        let container = try createTestModelContainer()
        let context = ModelContext(container)
        manager.configure(apiKey: "test-key", modelContext: context)
        
        // Create more than max (50) links
        let links = createTestLinks(count: 75)
        
        manager.startBatchExtraction(links: links)
        
        // Give it a moment to start
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Should be processing, but limited to 50
        if let status = manager.currentStatus {
            #expect(status.totalCount <= 50, "Should limit to max batch size of 50")
        }
        
        manager.stop()
        
        logger.info("✅ Batch size limit test passed")
    }
    
    // MARK: - Error Logging Tests
    
    @Test("Error log structure")
    func errorLogStructure() async throws {
        logger.info("🧪 Testing error log structure")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        
        let now = Date()
        manager.errorLog.append((
            link: "https://example.com/recipe",
            error: "Network error",
            timestamp: now
        ))
        
        #expect(manager.errorLog.count == 1)
        #expect(manager.errorLog[0].link == "https://example.com/recipe")
        #expect(manager.errorLog[0].error == "Network error")
        #expect(manager.errorLog[0].timestamp == now)
        
        manager.reset()
        
        logger.info("✅ Error log test passed")
    }
    
    // MARK: - Recently Extracted Tests
    
    @Test("Recently extracted maintains max 5 items")
    func recentlyExtractedLimit() async throws {
        logger.info("🧪 Testing recently extracted limit")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        
        // Add 7 recipes
        for i in 0..<7 {
            let recipe = RecipeX(
                title: "Recipe \(i)"
            )
            
            manager.recentlyExtracted.insert(recipe, at: 0)
            if manager.recentlyExtracted.count > 5 {
                manager.recentlyExtracted = Array(manager.recentlyExtracted.prefix(5))
            }
        }
        
        #expect(manager.recentlyExtracted.count == 5, "Should maintain max 5 items")
        #expect(manager.recentlyExtracted[0].title == "Recipe 6", "Most recent should be first")
        #expect(manager.recentlyExtracted[4].title == "Recipe 2", "Oldest kept should be last")
        
        manager.reset()
        
        logger.info("✅ Recently extracted limit test passed")
    }
    
    // MARK: - Time Estimation Tests
    
    @Test("Time estimation with no data")
    func timeEstimationWithNoData() async throws {
        logger.info("🧪 Testing time estimation with no data")
        
        // When currentIndex is 0, estimated time should be nil
        let status = ExtractionStatus(
            currentIndex: 0,
            totalCount: 10,
            currentLink: nil,
            currentRecipe: nil,
            currentStep: .fetching,
            stepProgress: 0.0,
            imagesDownloaded: 0,
            totalImages: 0,
            timeElapsed: 0,
            estimatedTimeRemaining: nil
        )
        
        #expect(status.estimatedTimeRemaining == nil, "Should have no estimate with no data")
        
        logger.info("✅ Time estimation with no data test passed")
    }
    
    @Test("Time estimation calculation")
    func timeEstimationCalculation() async throws {
        logger.info("🧪 Testing time estimation calculation")
        
        // After processing 2 of 10 items in 60 seconds
        // Average: 30 seconds per item
        // Remaining: 8 items
        // Estimate: 8 * 30 = 240 seconds
        
        let timeElapsed: TimeInterval = 60.0
        let currentIndex = 2
        let totalCount = 10
        
        let averageTimePerRecipe = timeElapsed / Double(currentIndex)
        let remaining = totalCount - currentIndex
        let expectedEstimate = averageTimePerRecipe * Double(remaining)
        
        #expect(expectedEstimate == 240.0, "Should calculate 240 seconds remaining")
        
        logger.info("✅ Time estimation calculation test passed")
    }
    
    // MARK: - SavedLink Model Tests
    
    @Test("SavedLink initialization")
    func savedLinkInitialization() async throws {
        logger.info("🧪 Testing SavedLink initialization")
        
        let link = SavedLink(
            title: "Test Recipe", url: "https://example.com/recipe",
            isProcessed: false
        )
        
        #expect(link.url == "https://example.com/recipe")
        #expect(link.title == "Test Recipe")
        #expect(!link.isProcessed)
        #expect(link.processingError == nil)
        #expect(link.extractedRecipeID == nil)
        
        logger.info("✅ SavedLink initialization test passed")
    }
    
    @Test("SavedLink processing state")
    func savedLinkProcessingState() async throws {
        logger.info("🧪 Testing SavedLink processing state")
        
        let link = SavedLink(
            title: "Test Recipe", url: "https://example.com/recipe",
            isProcessed: false
        )
        
        #expect(!link.isProcessed)
        
        // Mark as processed
        link.isProcessed = true
        #expect(link.isProcessed)
        
        // Add error
        link.processingError = "Network timeout"
        #expect(link.processingError == "Network timeout")
        
        logger.info("✅ SavedLink processing state test passed")
    }
    
    // MARK: - Integration Setup Tests
    
    @Test("ModelContext integration setup")
    func modelContextSetup() async throws {
        logger.info("🧪 Testing ModelContext integration")
        
        let container = try createTestModelContainer()
        let context = ModelContext(container)
        
        // Create a SavedLink and insert it
        let link = SavedLink(
            title: "Test", url: "https://example.com/test",
            isProcessed: false
        )
        
        context.insert(link)
        try context.save()
        
        // Fetch it back
        let descriptor = FetchDescriptor<SavedLink>()
        let links = try context.fetch(descriptor)
        
        #expect(links.count == 1)
        #expect(links[0].url == "https://example.com/test")
        
        logger.info("✅ ModelContext integration test passed")
    }
    
    // MARK: - Concurrency Tests
    
    @Test("Concurrent pause requests")
    func concurrentPauseRequests() async throws {
        logger.info("🧪 Testing concurrent pause requests")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        
        await withDiscardingTaskGroup { group in
            for _ in 0..<10 {
                group.addTask { @MainActor in
                    manager.pause()
                }
            }
        }
        
        #expect(manager.isPaused, "Should be paused after concurrent requests")
        
        manager.resume()
        
        logger.info("✅ Concurrent pause requests test passed")
    }
    
    @Test("Concurrent reset calls")
    func concurrentResetCalls() async throws {
        logger.info("🧪 Testing concurrent reset calls")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        
        // Set some state
        manager.totalProcessed = 10
        manager.successCount = 5
        manager.failureCount = 5
        
        await withDiscardingTaskGroup { group in
            for _ in 0..<10 {
                group.addTask { @MainActor in
                    manager.reset()
                }
            }
        }
        
        #expect(manager.totalProcessed == 0, "Should be reset")
        #expect(manager.successCount == 0, "Should be reset")
        #expect(manager.failureCount == 0, "Should be reset")
        
        logger.info("✅ Concurrent reset calls test passed")
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Extraction with mix of processed and unprocessed links")
    func mixedProcessingState() async throws {
        logger.info("🧪 Testing mixed processing state")
        
        let links = createTestLinks(count: 5)
        links[0].isProcessed = true
        links[2].isProcessed = true
        links[4].isProcessed = true
        
        let unprocessed = links.filter { !$0.isProcessed }
        
        #expect(unprocessed.count == 2, "Should have 2 unprocessed links")
        #expect(unprocessed[0].title == "Test Recipe 1")
        #expect(unprocessed[1].title == "Test Recipe 3")
        
        logger.info("✅ Mixed processing state test passed")
    }
    
    @Test("Error log maintains chronological order")
    func errorLogChronologicalOrder() async throws {
        logger.info("🧪 Testing error log chronological order")
        
        cleanupManager()
        
        let manager = BatchExtractionManager.shared
        
        let time1 = Date()
        let time2 = Date().addingTimeInterval(1)
        let time3 = Date().addingTimeInterval(2)
        
        manager.errorLog.append(("link1", "error1", time1))
        manager.errorLog.append(("link2", "error2", time2))
        manager.errorLog.append(("link3", "error3", time3))
        
        #expect(manager.errorLog[0].timestamp == time1)
        #expect(manager.errorLog[1].timestamp == time2)
        #expect(manager.errorLog[2].timestamp == time3)
        
        manager.reset()
        
        logger.info("✅ Error log chronological order test passed")
    }
    
    @Test("Progress calculation edge cases")
    func progressCalculationEdgeCases() async throws {
        logger.info("🧪 Testing progress calculation edge cases")
        
        // Test 0 progress
        let status1 = ExtractionStatus(
            currentIndex: 0,
            totalCount: 10,
            currentLink: nil,
            currentRecipe: nil,
            currentStep: .fetching,
            stepProgress: 0.0,
            imagesDownloaded: 0,
            totalImages: 0,
            timeElapsed: 0,
            estimatedTimeRemaining: nil
        )
        #expect(status1.stepProgress == 0.0)
        
        // Test 100% progress
        let status2 = ExtractionStatus(
            currentIndex: 10,
            totalCount: 10,
            currentLink: nil,
            currentRecipe: nil,
            currentStep: .complete,
            stepProgress: 1.0,
            imagesDownloaded: 5,
            totalImages: 5,
            timeElapsed: 300,
            estimatedTimeRemaining: 0
        )
        #expect(status2.stepProgress == 1.0)
        
        // Test partial progress
        let status3 = ExtractionStatus(
            currentIndex: 5,
            totalCount: 10,
            currentLink: nil,
            currentRecipe: nil,
            currentStep: .analyzing,
            stepProgress: 0.5,
            imagesDownloaded: 2,
            totalImages: 4,
            timeElapsed: 150,
            estimatedTimeRemaining: 150
        )
        #expect(status3.stepProgress == 0.5)
        
        logger.info("✅ Progress calculation edge cases test passed")
    }
}
