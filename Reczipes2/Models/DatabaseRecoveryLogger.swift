//
//  DatabaseRecoveryLogger.swift
//  Reczipes2
//
//  Enhanced logging and diagnostics for database recovery operations
//  Created on 1/23/26
//

import Foundation
import SwiftData

/// Tracks database recovery attempts and outcomes for diagnostics
@MainActor
class DatabaseRecoveryLogger {
    static let shared = DatabaseRecoveryLogger()
    
    // MARK: - Recovery Tracking
    
    struct RecoveryAttempt: Codable {
        let timestamp: Date
        let errorCode: Int
        let errorDomain: String
        let errorDescription: String
        let filesDeleted: [String]
        let success: Bool
        let cloudKitEnabled: Bool
        let databaseSizeMB: Double?
        let recoveryDurationSeconds: Double
    }
    
    private var recoveryHistory: [RecoveryAttempt] = []
    private var currentAttemptStart: Date?
    
    private init() {
        loadRecoveryHistory()
    }
    
    // MARK: - Logging Methods
    
    /// Start tracking a recovery attempt
    func beginRecoveryAttempt() {
        currentAttemptStart = Date()
        AppLog.info("📊 Starting database recovery attempt #\(recoveryHistory.count + 1)", category: .storage)
    }
    
    /// Log successful recovery
    func logRecoverySuccess(
        error: NSError,
        filesDeleted: [String],
        cloudKitEnabled: Bool,
        databaseSizeMB: Double?
    ) {
        guard let startTime = currentAttemptStart else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        
        let attempt = RecoveryAttempt(
            timestamp: startTime,
            errorCode: error.code,
            errorDomain: error.domain,
            errorDescription: error.localizedDescription,
            filesDeleted: filesDeleted,
            success: true,
            cloudKitEnabled: cloudKitEnabled,
            databaseSizeMB: databaseSizeMB,
            recoveryDurationSeconds: duration
        )
        
        recoveryHistory.append(attempt)
        saveRecoveryHistory()
        
        AppLog.info("✅ RECOVERY SUCCESS", category: .storage)
        AppLog.info("   Duration: \(String(format: "%.2f", duration))s", category: .storage)
        AppLog.info("   Files deleted: \(filesDeleted.count)", category: .storage)
        AppLog.info("   CloudKit: \(cloudKitEnabled ? "enabled" : "disabled")", category: .storage)
        if let sizeMB = databaseSizeMB {
            AppLog.info("   Database size: \(String(format: "%.1f", sizeMB)) MB", category: .storage)
        }
        
        // Log user-facing diagnostic
        logUserDiagnostic(
            .info,
            category: .storage,
            title: "Database Recovered",
            message: "Your database was successfully recreated. \(cloudKitEnabled ? "Your data will sync from iCloud." : "Local data may be lost.")",
            technicalDetails: "Recovery completed in \(String(format: "%.2f", duration))s. Deleted \(filesDeleted.count) files.",
            suggestedActions: cloudKitEnabled ? [
                DiagnosticAction(
                    title: "Wait for Sync",
                    description: "Your recipes will sync from iCloud in a few moments",
                    actionType: .retryOperation
                ),
                DiagnosticAction(
                    title: "Verify Your Data",
                    description: "Check that your recipes appear correctly",
                    actionType: .retryOperation
                )
            ] : [
                DiagnosticAction(
                    title: "Check Your Data",
                    description: "Some local data may have been lost. Enable iCloud sync to prevent this in the future.",
                    actionType: .openSettings(.icloud)
                )
            ]
        )
        
        currentAttemptStart = nil
    }
    
    /// Log failed recovery
    func logRecoveryFailure(
        error: NSError,
        filesDeleted: [String],
        cloudKitEnabled: Bool,
        secondaryError: Error?
    ) {
        guard let startTime = currentAttemptStart else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        
        let attempt = RecoveryAttempt(
            timestamp: startTime,
            errorCode: error.code,
            errorDomain: error.domain,
            errorDescription: error.localizedDescription,
            filesDeleted: filesDeleted,
            success: false,
            cloudKitEnabled: cloudKitEnabled,
            databaseSizeMB: nil,
            recoveryDurationSeconds: duration
        )
        
        recoveryHistory.append(attempt)
        saveRecoveryHistory()
        
        AppLog.error("❌ RECOVERY FAILED", category: .storage)
        AppLog.error("   Duration: \(String(format: "%.2f", duration))s", category: .storage)
        AppLog.error("   Files deleted: \(filesDeleted.count)", category: .storage)
        if let secondaryError = secondaryError {
            AppLog.error("   Secondary error: \(secondaryError.localizedDescription)", category: .storage)
        } else {
            AppLog.error("   Secondary error: None (no files found to delete)", category: .storage)
        }
        
        // Log critical user-facing diagnostic
        let technicalDetails: String
        if let secondaryError = secondaryError {
            technicalDetails = "Primary error: \(error.localizedDescription)\nSecondary error: \(secondaryError.localizedDescription)"
        } else {
            technicalDetails = "Primary error: \(error.localizedDescription)\nNo database files found to delete"
        }
        
        logUserDiagnostic(
            .critical,
            category: .storage,
            title: "Database Recovery Failed",
            message: "Automatic recovery couldn't fix the issue. Your data may be in iCloud if sync was enabled.",
            technicalDetails: technicalDetails,
            suggestedActions: [
                DiagnosticAction(
                    title: "Restart Reczipes",
                    description: "Close the app completely and reopen it",
                    actionType: .retryOperation
                ),
                DiagnosticAction(
                    title: "Check iCloud Status",
                    description: "Verify you're signed into iCloud",
                    actionType: .openSettings(.icloud)
                ),
                DiagnosticAction(
                    title: "Reinstall App",
                    description: "If the problem persists, delete and reinstall Reczipes. Your iCloud data will sync back.",
                    actionType: .deleteAndReinstall
                ),
                DiagnosticAction(
                    title: "Contact Support",
                    description: "Share your diagnostic logs with support",
                    actionType: .contactSupport
                )
            ]
        )
        
        currentAttemptStart = nil
    }
    
    // MARK: - Recovery Statistics
    
    /// Get recovery statistics for diagnostics
    func getRecoveryStatistics() -> RecoveryStatistics {
        let totalAttempts = recoveryHistory.count
        let successfulAttempts = recoveryHistory.filter { $0.success }.count
        let failedAttempts = totalAttempts - successfulAttempts
        let averageDuration = recoveryHistory.isEmpty ? 0 : recoveryHistory.map { $0.recoveryDurationSeconds }.reduce(0, +) / Double(totalAttempts)
        let lastAttempt = recoveryHistory.last
        
        return RecoveryStatistics(
            totalAttempts: totalAttempts,
            successfulAttempts: successfulAttempts,
            failedAttempts: failedAttempts,
            averageDurationSeconds: averageDuration,
            lastAttempt: lastAttempt
        )
    }
    
    struct RecoveryStatistics {
        let totalAttempts: Int
        let successfulAttempts: Int
        let failedAttempts: Int
        let averageDurationSeconds: Double
        let lastAttempt: RecoveryAttempt?
        
        var successRate: Double {
            guard totalAttempts > 0 else { return 0 }
            return Double(successfulAttempts) / Double(totalAttempts)
        }
        
        var hasRecentFailures: Bool {
            guard let last = lastAttempt else { return false }
            return !last.success && Date().timeIntervalSince(last.timestamp) < 3600 // Within last hour
        }
    }
    
    /// Log recovery statistics for diagnostics
    func logRecoveryStatistics() {
        let stats = getRecoveryStatistics()
        
        AppLog.info("📊 RECOVERY STATISTICS", category: .storage)
        AppLog.info("   Total attempts: \(stats.totalAttempts)", category: .storage)
        AppLog.info("   Successful: \(stats.successfulAttempts)", category: .storage)
        AppLog.info("   Failed: \(stats.failedAttempts)", category: .storage)
        AppLog.info("   Success rate: \(String(format: "%.1f", stats.successRate * 100))%", category: .storage)
        AppLog.info("   Average duration: \(String(format: "%.2f", stats.averageDurationSeconds))s", category: .storage)
        
        if let last = stats.lastAttempt {
            let timeAgo = Date().timeIntervalSince(last.timestamp)
            AppLog.info("   Last attempt: \(last.success ? "✅ Success" : "❌ Failed") (\(formatTimeAgo(timeAgo)))", category: .storage)
        }
        
        if stats.hasRecentFailures {
            AppLog.warning("   ⚠️ Recent recovery failures detected - may need manual intervention", category: .storage)
        }
    }
    
    // MARK: - Persistence
    
    private func loadRecoveryHistory() {
        guard let data = UserDefaults.standard.data(forKey: "DatabaseRecoveryHistory"),
              let history = try? JSONDecoder().decode([RecoveryAttempt].self, from: data) else {
            return
        }
        
        // Keep only last 50 attempts to avoid unbounded growth
        recoveryHistory = Array(history.suffix(50))
    }
    
    private func saveRecoveryHistory() {
        guard let data = try? JSONEncoder().encode(recoveryHistory) else { return }
        UserDefaults.standard.set(data, forKey: "DatabaseRecoveryHistory")
    }
    
    /// Clear recovery history (for testing or privacy)
    func clearHistory() {
        recoveryHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "DatabaseRecoveryHistory")
        AppLog.info("🗑️ Recovery history cleared", category: .storage)
    }
    
    // MARK: - Helper Methods
    
    private func formatTimeAgo(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s ago"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m ago"
        } else if seconds < 86400 {
            return "\(Int(seconds / 3600))h ago"
        } else {
            return "\(Int(seconds / 86400))d ago"
        }
    }
    
    /// Get database size in MB for logging
    static func getDatabaseSize(at url: URL) -> Double? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return Double(size) / 1_048_576.0 // Convert bytes to MB
    }
}

// MARK: - Error Analysis Helper

extension DatabaseRecoveryLogger {
    
    /// Analyze error chain and provide detailed diagnostic info
    static func analyzeError(_ error: NSError) -> ErrorAnalysis {
        var errorChain: [String] = []
        var currentError: NSError? = error
        var depth = 0
        let maxDepth = 5
        
        while let err = currentError, depth < maxDepth {
            errorChain.append("\(err.domain) (\(err.code)): \(err.localizedDescription)")
            currentError = err.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        
        let isSchemaIssue = errorChain.contains { $0.contains("134504") || $0.contains("unknown coordinator model") }
        let isSwiftDataWrapper = error.domain == "SwiftData.SwiftDataError" && error.code == 1
        let isCoreDataIssue = errorChain.contains { $0.contains("NSCocoaErrorDomain") }
        
        return ErrorAnalysis(
            errorChain: errorChain,
            isSchemaIssue: isSchemaIssue,
            isSwiftDataWrapper: isSwiftDataWrapper,
            isCoreDataIssue: isCoreDataIssue,
            suggestedResolution: isSchemaIssue ? "Delete and recreate database" : "Check CloudKit configuration"
        )
    }
    
    struct ErrorAnalysis {
        let errorChain: [String]
        let isSchemaIssue: Bool
        let isSwiftDataWrapper: Bool
        let isCoreDataIssue: Bool
        let suggestedResolution: String
        
        func logAnalysis() {
            AppLog.error("🔍 ERROR ANALYSIS:", category: .storage)
            AppLog.error("   Error chain depth: \(errorChain.count)", category: .storage)
            for (index, errorString) in errorChain.enumerated() {
                AppLog.error("   [\(index)] \(errorString)", category: .storage)
            }
            AppLog.error("   Schema issue: \(isSchemaIssue ? "YES ⚠️" : "NO")", category: .storage)
            AppLog.error("   SwiftData wrapper: \(isSwiftDataWrapper ? "YES" : "NO")", category: .storage)
            AppLog.error("   Core Data issue: \(isCoreDataIssue ? "YES" : "NO")", category: .storage)
            AppLog.error("   Suggested resolution: \(suggestedResolution)", category: .storage)
        }
    }
}
