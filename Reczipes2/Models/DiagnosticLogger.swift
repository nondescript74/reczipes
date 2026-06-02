//
//  DiagnosticLogger.swift
//  Reczipes
//
//  Created on December 19, 2025.
//

import Foundation
import OSLog

/// Centralized logging system that writes to both OSLog and a diagnostic file.
///
/// # Thread Safety (`@unchecked Sendable` justification)
///
/// This type is `@unchecked Sendable` rather than an `actor` because it must offer a
/// **synchronous** API to ~1500 call sites across the project. Converting to an actor
/// would require `await` at every logging call, with a large blast radius and no
/// material safety benefit beyond what is documented below.
///
/// Safety is guaranteed by these invariants:
///
/// 1. **`subsystems`** — `let`-bound dictionary of `Logger` values. `os.Logger` is
///    documented as thread-safe (see `OSLog`/`Logger` reference), and the dictionary
///    is never mutated after `init`.
/// 2. **`fileManager`** — `let`-bound `FileManager` instance. Per Apple's docs,
///    `FileManager` methods are thread-safe when accessed from multiple threads as
///    long as the instance itself is not reconfigured (we never reconfigure it).
/// 3. **`logFileURL`** — written exactly once during `init` and only read afterward.
///    Reads happen-after the singleton's `init` completes (Swift guarantees safe
///    publication of static `let` initializers), so no synchronization is required.
/// 4. **File writes** — all `writeToFile` invocations dispatch onto the serial
///    `logQueue`, providing total ordering of writes and exclusive access to the
///    `FileHandle` lifecycle.
/// 5. **UserDefaults** — `UserDefaults` is documented as thread-safe.
///
/// Because every mutable resource is either confined to `logQueue` or written-once
/// during init, there is no data race surface that an actor would protect against
/// more strongly than the current implementation.
@preconcurrency
final class DiagnosticLogger: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = DiagnosticLogger()

    // MARK: - Properties

    // Write-once during init, never mutated afterward — safe to read from any thread.
    private nonisolated(unsafe) let fileManager = FileManager()
    private let logFileName = "reczipes_diagnostics.log"
    // Written once in `setupLogFile()` (called only from `init`) and treated as
    // read-only thereafter. Reads happen-after init via static-let publication.
    private nonisolated(unsafe) var logFileURL: URL?
    // Serial queue: provides total ordering and mutual exclusion for file writes.
    private let logQueue = DispatchQueue(label: "com.reczipes.diagnosticlogger", qos: .utility)
    
    // UserDefaults key for tracking security migration
    private let securityMigrationKey = "com.reczipes.diagnosticlog.securityMigration.v1"
    
    // OSLog subsystems for different areas of the app
    private let subsystems: [String: Logger]
    
    // MARK: - Initialization
    
    private init() {
        // Use hardcoded bundle ID to avoid @MainActor isolation issues
        let bundleID = "com.reczipes"
        self.subsystems = [
            "general": Logger(subsystem: bundleID, category: "general"),
            "allergen": Logger(subsystem: bundleID, category: "allergen"),
            "fodmap": Logger(subsystem: bundleID, category: "fodmap"),
            "recipe": Logger(subsystem: bundleID, category: "recipe"),
            "network": Logger(subsystem: bundleID, category: "network"),
            "storage": Logger(subsystem: bundleID, category: "storage"),
            "ui": Logger(subsystem: bundleID, category: "ui"),
            "extraction": Logger(subsystem: bundleID, category: "extraction"),
            "image": Logger(subsystem: bundleID, category: "image")
        ]
        
        setupLogFile()
        performSecurityMigrationIfNeeded()
        logInitialization()
    }
    
    private func setupLogFile() {
        do {
            // Get Documents directory
            let documentsURL = try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            
            logFileURL = documentsURL.appendingPathComponent(logFileName)
            
            // Create file if it doesn't exist
            if let url = logFileURL, !fileManager.fileExists(atPath: url.path) {
                fileManager.createFile(atPath: url.path, contents: nil)
                writeToFile("=== Reczipes Diagnostic Log Started ===\n")
                writeToFile("Date: \(Date().formatted())\n")
                writeToFile("=====================================\n\n")
            }
        } catch {
            // Fallback to OSLog only if file setup fails
            Logger(subsystem: "com.reczipes", category: "logger")
                .error("Failed to setup log file: \(error.localizedDescription)")
        }
    }
    
    private func logInitialization() {
        info("DiagnosticLogger initialized", category: "general")
        if let url = logFileURL {
            info("Log file location: \(url.path)", category: "general")
        }
    }
    
    /// One-time security migration to clear logs that may contain exposed API keys
    /// This runs once per app installation after the security fix is deployed
    private func performSecurityMigrationIfNeeded() {
        // Check if migration has already been performed
        let migrationCompleted = UserDefaults.standard.bool(forKey: securityMigrationKey)
        
        if migrationCompleted {
            // Migration already done, nothing to do
            return
        }
        
        // Perform one-time log deletion
        guard let url = logFileURL else {
            // No log file to clear, mark as complete
            UserDefaults.standard.set(true, forKey: securityMigrationKey)
            return
        }
        
        logQueue.async { [weak self] in
            guard let self else { return }
            
            do {
                // Check if log file exists
                if fileManager.fileExists(atPath: url.path) {
                    // Get file size before deletion for logging
                    let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                    let fileSize = attributes?[.size] as? Int64 ?? 0
                    
                    // Delete the old log file completely
                    try fileManager.removeItem(at: url)
                    
                    // Create a new log file with security migration notice
                    fileManager.createFile(atPath: url.path, contents: nil)
                    
                    let header = """
                    === Reczipes Diagnostic Log - Security Migration ===
                    Date: \(Date().formatted())
                    Previous log cleared for security (API key exposure fix)
                    Previous log size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                    ===================================================
                    
                    
                    """
                    try header.write(to: url, atomically: false, encoding: .utf8)
                    
                    // Log the migration
                    self.log("Security migration completed - diagnostic log cleared to remove potentially exposed API keys", 
                            level: .info, 
                            category: "general", 
                            file: #file, 
                            function: #function, 
                            line: #line)
                } else {
                    // Log file doesn't exist yet, just mark as migrated
                    self.log("Security migration: No existing log file to clear", 
                            level: .info, 
                            category: "general", 
                            file: #file, 
                            function: #function, 
                            line: #line)
                }
                
                // Mark migration as complete
                UserDefaults.standard.set(true, forKey: self.securityMigrationKey)
                
            } catch {
                // Log error but still mark as complete to avoid repeated attempts
                self.log("Security migration failed: \(error.localizedDescription)", 
                        level: .error, 
                        category: "general", 
                        file: #file, 
                        function: #function, 
                        line: #line)
                
                // Mark as complete anyway to prevent infinite retry
                UserDefaults.standard.set(true, forKey: self.securityMigrationKey)
            }
        }
    }
    
    // MARK: - Public Logging Methods
    
    /// Log a debug message
    nonisolated func debug(_ message: String, category: String = "general", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }
    
    /// Log an info message
    nonisolated func info(_ message: String, category: String = "general", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }
    
    /// Log a warning message
    nonisolated func warning(_ message: String, category: String = "general", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .default, category: category, file: file, function: function, line: line)
    }
    
    /// Log an error message
    nonisolated func error(_ message: String, category: String = "general", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }
    
    /// Log a critical/fault message
    nonisolated func critical(_ message: String, category: String = "general", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .fault, category: category, file: file, function: function, line: line)
    }
    
    // MARK: - Private Logging Implementation
    
    nonisolated private func log(
        _ message: String,
        level: OSLogType,
        category: String,
        file: String,
        function: String,
        line: Int
    ) {
        // Convert OSLogType to LogLevel for checking
        let logLevel: LogLevel
        switch level {
        case .debug:
            logLevel = .debug
        case .info:
            logLevel = .info
        case .error:
            logLevel = .error
        case .fault:
            logLevel = .critical
        default:
            logLevel = .warning
        }
        
        // Check if this log level should be logged (thread-safe)
        guard LoggingHelper.shouldLog(level: logLevel) else {
            return
        }
        
        // Check if this category should be logged (thread-safe)
        guard LoggingHelper.shouldLog(category: category) else {
            return
        }
        
        let fileName = (file as NSString).lastPathComponent
        let timestamp = Date()
        let formattedTimestamp = timestamp.formatted(date: .numeric, time: .standard)
        
        // Get appropriate logger
        let logger = subsystems[category] ?? subsystems["general"]!
        
        // Format the log message once to avoid repeated interpolation
        let logMessage = "[\(fileName):\(line)] \(function) - \(message)"
        
        // Log to OSLog
        switch level {
        case .debug:
            logger.debug("\(logMessage)")
        case .info:
            logger.info("\(logMessage)")
        case .error:
            logger.error("\(logMessage)")
        case .fault:
            logger.critical("\(logMessage)")
        default:
            logger.notice("\(logMessage)")
        }
        
        // Format for file
        let levelString = logLevelString(level)
        let fileLogMessage = "[\(formattedTimestamp)] [\(levelString)] [\(category)] [\(fileName):\(line)] \(function)\n  → \(message)\n"
        
        // Write to file if enabled (thread-safe)
        if LoggingHelper.isFileLoggingEnabled {
            writeToFile(fileLogMessage)
        }
    }
    
    nonisolated private func logLevelString(_ level: OSLogType) -> String {
        switch level {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .error:
            return "ERROR"
        case .fault:
            return "CRITICAL"
        case .default:
            return "WARNING"
        default:
            return "NOTICE"
        }
    }
    
    nonisolated private func writeToFile(_ message: String) {
        guard let url = logFileURL else { return }
        
        logQueue.async {
            do {
                let fileHandle = try FileHandle(forWritingTo: url)
                defer { try? fileHandle.close() }
                
                fileHandle.seekToEndOfFile()
                if let data = message.data(using: .utf8) {
                    fileHandle.write(data)
                }
            } catch {
                // If file handle fails, try appending
                if let data = message.data(using: .utf8) {
                    try? data.append(fileOrURL: url)
                }
            }
        }
    }
    
    // MARK: - Log Management
    
    /// Get the current log file URL
    func getLogFileURL() -> URL? {
        return logFileURL
    }
    
    /// Get the contents of the log file
    func getLogContents() -> String {
        guard let url = logFileURL else {
            return "Log file not available"
        }
        
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return "Error reading log file: \(error.localizedDescription)"
        }
    }
    
    /// Clear the log file
    func clearLog() {
        guard let url = logFileURL else { return }
        
        logQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Clear the file
                try "".write(to: url, atomically: true, encoding: .utf8)
                
                // Write new header
                let header = """
                === Reczipes Diagnostic Log Cleared ===
                Date: \(Date().formatted())
                =====================================
                
                
                """
                try header.write(to: url, atomically: false, encoding: .utf8)
                
                self.log("Diagnostic log cleared by user", level: .info, category: "general", file: #file, function: #function, line: #line)
            } catch {
                self.log("Failed to clear log file: \(error.localizedDescription)", level: .error, category: "general", file: #file, function: #function, line: #line)
            }
        }
    }
    
    /// Get the size of the log file in bytes
    func getLogFileSize() -> Int64 {
        guard let url = logFileURL else { return 0 }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    /// Get formatted file size (e.g., "1.5 MB")
    func getFormattedLogFileSize() -> String {
        let bytes = getLogFileSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Data Extension for File Appending

private extension Data {
    nonisolated func append(fileOrURL: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileOrURL.path) {
            defer {
                try? fileHandle.close()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        } else {
            try write(to: fileOrURL, options: .atomic)
        }
    }
}

// MARK: - Convenience Global Functions

/// Global convenience function for debug logging
func logDebug(_ message: String, category: String = "general", file: String = #file, function: String = #function, line: Int = #line) {
    DiagnosticLogger.shared.debug(message, category: category, file: file, function: function, line: line)
}

/// Global convenience function for info logging
func logInfo(_ message: String, category: String = "general", file: String = #file, function: String = #function, line: Int = #line) {
    DiagnosticLogger.shared.info(message, category: category, file: file, function: function, line: line)
}

/// Global convenience function for warning logging
func logWarning(_ message: String, category: String = "general", file: String = #file, function: String = #function, line: Int = #line) {
    DiagnosticLogger.shared.warning(message, category: category, file: file, function: function, line: line)
}

/// Global convenience function for error logging
func logError(_ message: String, category: String = "general", file: String = #file, function: String = #function, line: Int = #line) {
    DiagnosticLogger.shared.error(message, category: category, file: file, function: function, line: line)
}

/// Global convenience function for critical logging
func logCritical(_ message: String, category: String = "general", file: String = #file, function: String = #function, line: Int = #line) {
    DiagnosticLogger.shared.critical(message, category: category, file: file, function: function, line: line)
}
