//
//  ConcurrencyStressTests.swift
//  Reczipes2Tests
//
//  Stress tests for `@unchecked Sendable` types verified safe in
//  SWIFT_6_CONCURRENCY_AUDIT.md. Hammers each type from many concurrent
//  tasks to detect data races, crashes, or inconsistent final state.
//

import Testing
import Foundation
import OSLog
import SwiftUI
@testable import Reczipes2

@Suite("Concurrency Stress Tests", .serialized)
struct ConcurrencyStressTests {

    private let logger = Logger(subsystem: "com.reczipes.tests", category: "concurrency-stress")

    // MARK: - DiagnosticLogger

    @Test("DiagnosticLogger handles concurrent logging without crashing")
    func diagnosticLoggerConcurrentLogging() async throws {
        logger.info("🧪 Stress testing DiagnosticLogger concurrent logging")

        let logger = DiagnosticLogger.shared
        let iterations = 200
        let categories = ["general", "allergen", "fodmap", "recipe", "network", "storage", "ui", "extraction", "image"]

        await withDiscardingTaskGroup { group in
            for i in 0..<iterations {
                group.addTask {
                    let category = categories[i % categories.count]
                    logger.debug("Stress debug \(i)", category: category)
                    logger.info("Stress info \(i)", category: category)
                    logger.warning("Stress warning \(i)", category: category)
                    logger.error("Stress error \(i)", category: category)
                }
            }
        }

        // If we got here without crashing, the logger handled concurrent access safely.
        #expect(logger.getLogFileURL() != nil, "Log file URL should remain valid after concurrent stress")

        self.logger.info("✅ DiagnosticLogger concurrent logging stress test passed")
    }

    @Test("DiagnosticLogger global functions are safe under concurrent calls")
    func diagnosticLoggerGlobalFunctionsConcurrent() async throws {
        logger.info("🧪 Stress testing DiagnosticLogger global functions")

        let iterations = 100

        await withDiscardingTaskGroup { group in
            for i in 0..<iterations {
                group.addTask {
                    logDebug("Global debug \(i)", category: "general")
                    logInfo("Global info \(i)", category: "general")
                    logWarning("Global warning \(i)", category: "general")
                    logError("Global error \(i)", category: "general")
                }
            }
        }

        // No crash = success
        logger.info("✅ DiagnosticLogger global functions stress test passed")
    }

    @Test("DiagnosticLogger read APIs are safe during concurrent writes")
    func diagnosticLoggerReadDuringWrites() async throws {
        logger.info("🧪 Stress testing DiagnosticLogger reads during writes")

        let diagLogger = DiagnosticLogger.shared

        await withDiscardingTaskGroup { group in
            // Writers
            for i in 0..<50 {
                group.addTask {
                    diagLogger.info("Concurrent write \(i)", category: "general")
                }
            }
            // Readers
            for _ in 0..<20 {
                group.addTask {
                    _ = diagLogger.getLogFileURL()
                    _ = diagLogger.getLogFileSize()
                    _ = diagLogger.getFormattedLogFileSize()
                }
            }
        }

        // Verify reads still return sensible values after the storm.
        #expect(diagLogger.getLogFileURL() != nil)
        #expect(diagLogger.getLogFileSize() >= 0)

        logger.info("✅ DiagnosticLogger reads-during-writes stress test passed")
    }

    // MARK: - AppLog gates

    @Test("AppLog honors LoggingHelper level + category + file gates")
    @MainActor
    func appLogGatesShortCircuit() async throws {
        logger.info("🧪 Stress testing AppLog gate behavior")

        // Snapshot existing settings so we can restore them afterward.
        let defaults = UserDefaults.standard
        let prevLevel = defaults.string(forKey: "com.reczipes.logging.level")
        let prevCategories = defaults.array(forKey: "com.reczipes.logging.categories")
        let prevFile = defaults.object(forKey: "com.reczipes.logging.fileLogging") as? Bool
        defer {
            if let prevLevel { defaults.set(prevLevel, forKey: "com.reczipes.logging.level") }
            else { defaults.removeObject(forKey: "com.reczipes.logging.level") }
            if let prevCategories { defaults.set(prevCategories, forKey: "com.reczipes.logging.categories") }
            else { defaults.removeObject(forKey: "com.reczipes.logging.categories") }
            if let prevFile { defaults.set(prevFile, forKey: "com.reczipes.logging.fileLogging") }
            else { defaults.removeObject(forKey: "com.reczipes.logging.fileLogging") }
        }

        // Case 1: level = .off — every call must be dropped.
        defaults.set("Off", forKey: "com.reczipes.logging.level")
        #expect(LoggingHelper.shouldLog(level: .error) == false, "Off must drop errors")
        #expect(LoggingHelper.shouldLog(level: .debug) == false, "Off must drop debug")

        // Case 2: level = .errors — only error/critical pass.
        defaults.set("Errors Only", forKey: "com.reczipes.logging.level")
        #expect(LoggingHelper.shouldLog(level: .error) == true)
        #expect(LoggingHelper.shouldLog(level: .critical) == true)
        #expect(LoggingHelper.shouldLog(level: .warning) == false)
        #expect(LoggingHelper.shouldLog(level: .info) == false)
        #expect(LoggingHelper.shouldLog(level: .debug) == false)

        // Case 3: level = .debug — everything passes.
        defaults.set("All (Debug Mode)", forKey: "com.reczipes.logging.level")
        #expect(LoggingHelper.shouldLog(level: .debug) == true)

        // Case 4: typed category gate. Set only `.background` enabled, then
        // confirm `.background` passes and `.recipe` does not.
        defaults.set(["Background Processing"], forKey: "com.reczipes.logging.categories")
        #expect(LoggingHelper.shouldLog(category: .background) == true)
        #expect(LoggingHelper.shouldLog(category: .recipe) == false)
        #expect(LoggingHelper.shouldLog(category: .lifecycle) == false)

        // Case 5: file logging toggle.
        defaults.set(false, forKey: "com.reczipes.logging.fileLogging")
        #expect(LoggingHelper.isFileLoggingEnabled == false)
        defaults.set(true, forKey: "com.reczipes.logging.fileLogging")
        #expect(LoggingHelper.isFileLoggingEnabled == true)

        // Case 6: confirm AppLog itself doesn't crash when gates are clamped
        // off — fire a storm of calls while gated, then unclamp and fire more.
        defaults.set("Off", forKey: "com.reczipes.logging.level")
        await withDiscardingTaskGroup { group in
            for i in 0..<100 {
                group.addTask {
                    AppLog.info("Gated-off message \(i)", category: .background)
                }
            }
        }

        defaults.set("All (Debug Mode)", forKey: "com.reczipes.logging.level")
        defaults.set(LoggingSettings.LoggingCategory.allCases.map(\.rawValue),
                     forKey: "com.reczipes.logging.categories")
        await withDiscardingTaskGroup { group in
            for i in 0..<100 {
                group.addTask {
                    AppLog.info("Gated-on message \(i)", category: .background)
                }
            }
        }

        logger.info("✅ AppLog gate behavior stress test passed")
    }

    // MARK: - DiabeticInfoCache

    @Test("DiabeticInfoCache handles concurrent store/get without crashing")
    @MainActor
    func diabeticInfoCacheConcurrentStoreGet() async throws {
        logger.info("🧪 Stress testing DiabeticInfoCache concurrent store/get")

        let cache = DiabeticInfoCache.shared
        let recipeIds = (0..<50).map { _ in UUID() }
        let samples = recipeIds.map { makeSampleDiabeticInfo(recipeId: $0) }

        // Ensure clean starting state for our keys.
        for id in recipeIds {
            cache.clear(recipeId: id)
        }

        await withDiscardingTaskGroup { group in
            // Storers
            for sample in samples {
                let id = sample.recipeId
                group.addTask { @MainActor in
                    cache.store(sample, recipeId: id)
                }
            }
            // Concurrent readers (some will hit, some will miss)
            for id in recipeIds {
                group.addTask { @MainActor in
                    _ = cache.get(recipeId: id)
                }
            }
        }

        // After all stores complete, every key should be retrievable.
        for id in recipeIds {
            #expect(cache.get(recipeId: id) != nil, "Cache entry should exist for \(id)")
        }

        // Cleanup
        for id in recipeIds {
            cache.clear(recipeId: id)
        }

        logger.info("✅ DiabeticInfoCache concurrent store/get stress test passed")
    }

    @Test("DiabeticInfoCache handles concurrent store/clear without losing consistency")
    @MainActor
    func diabeticInfoCacheConcurrentStoreClear() async throws {
        logger.info("🧪 Stress testing DiabeticInfoCache concurrent store/clear")

        let cache = DiabeticInfoCache.shared
        let recipeIds = (0..<30).map { _ in UUID() }
        let samples = recipeIds.map { makeSampleDiabeticInfo(recipeId: $0) }

        // Pre-populate
        for sample in samples {
            cache.store(sample, recipeId: sample.recipeId)
        }

        await withDiscardingTaskGroup { group in
            // Storers re-storing
            for sample in samples {
                let id = sample.recipeId
                group.addTask { @MainActor in
                    cache.store(sample, recipeId: id)
                }
            }
            // Concurrent clears for the same keys
            for id in recipeIds {
                group.addTask { @MainActor in
                    cache.clear(recipeId: id)
                }
            }
        }

        // Final state is non-deterministic (race between store and clear),
        // but: no crash, and every get either returns a valid value or nil.
        for id in recipeIds {
            let result = cache.get(recipeId: id)
            if let cached = result {
                #expect(cached.info.recipeId == id, "Returned entry must match key")
            }
        }

        // Cleanup
        for id in recipeIds {
            cache.clear(recipeId: id)
        }

        logger.info("✅ DiabeticInfoCache concurrent store/clear stress test passed")
    }

    @Test("DiabeticInfoCache clearAll under concurrent stores leaves consistent state")
    @MainActor
    func diabeticInfoCacheConcurrentClearAll() async throws {
        logger.info("🧪 Stress testing DiabeticInfoCache concurrent clearAll")

        let cache = DiabeticInfoCache.shared
        let recipeIds = (0..<30).map { _ in UUID() }
        let samples = recipeIds.map { makeSampleDiabeticInfo(recipeId: $0) }

        await withDiscardingTaskGroup { group in
            for sample in samples {
                let id = sample.recipeId
                group.addTask { @MainActor in
                    cache.store(sample, recipeId: id)
                }
            }
            for _ in 0..<5 {
                group.addTask { @MainActor in
                    cache.clearAll()
                }
            }
        }

        // No crash. Final state is undefined (race), so we only assert internal consistency.
        for id in recipeIds {
            if let cached = cache.get(recipeId: id) {
                #expect(cached.info.recipeId == id)
            }
        }

        cache.clearAll()
        logger.info("✅ DiabeticInfoCache concurrent clearAll stress test passed")
    }

    // MARK: - Helpers

    @MainActor
    private func makeSampleDiabeticInfo(recipeId: UUID) -> DiabeticInfo {
        DiabeticInfo(
            id: UUID(),
            recipeId: recipeId,
            lastUpdated: Date(),
            estimatedGlycemicLoad: GlycemicLoad(value: 10.0, explanation: "test"),
            glycemicImpactFactors: [],
            carbCount: CarbInfo(totalCarbs: 30, netCarbs: 25, fiber: 5),
            fiberContent: FiberInfo(total: 5, soluble: 2, insoluble: 3),
            sugarBreakdown: SugarBreakdown(total: 5, added: 2, natural: 3),
            diabeticGuidance: [],
            portionRecommendations: PortionGuidance(
                recommendedServing: "1 serving",
                servingSize: "100g",
                explanation: "test"
            ),
            substitutionSuggestions: [],
            sources: [],
            consensusLevel: .strongConsensus
        )
    }
}
