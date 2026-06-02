//
//  AppLog.swift
//  Reczipes2
//
//  A Swift-6 strict-concurrency-clean logger intended to replace the legacy
//  `DiagnosticLogger` / `logInfo` / `logError` family over time. This logger
//  carries NO `@unchecked Sendable`, NO `nonisolated(unsafe)`, and NO
//  `DispatchQueue` plumbing. All mutable state lives inside an `actor`.
//
//  # When to use which method
//
//  Log *decisions*, *state transitions*, and *errors* — not "I'm here" markers
//  or per-iteration progress. The legacy logger has ~1500 call sites because
//  it logged everything. Be selective.
//
//    - `debug`    : developer detail, off in shipped builds
//    - `info`     : a state change worth noticing on a sampled trace
//    - `notice`   : a non-error event a support engineer would want
//    - `warning`  : something unexpected but recoverable
//    - `error`    : an operation failed
//    - `critical` : data loss / corruption / unrecoverable state
//
//  # Design
//
//  - OSLog `Logger` per `Category` (built once at process start, immutable).
//    `os.Logger` is `Sendable` (from iOS 15), so the dictionary is safely
//    shareable as a `let` static.
//  - File mirroring is handled by a `private actor FileSink` — Swift enforces
//    serialized access at compile time. No locks, no queues, no `@unchecked`.
//  - The sync facade (`AppLog.info(...)` etc.) keeps call sites synchronous;
//    file writes are dispatched into the actor via a fire-and-forget `Task`.
//

import Foundation
import OSLog

public enum AppLog {

    // MARK: - Typed Categories

    /// Typed log categories — replaces stringly-typed `category: "foo"` to
    /// prevent typos. Add new cases here as new subsystems appear.
    public enum Category: String, Sendable, CaseIterable {
        case general
        case allergen
        case fodmap
        case recipe
        case network
        case storage
        case ui
        case extraction
        case image
        case background
        case lifecycle
        case sync
        case cloudKit
        case sharing
        case backup
        case onboarding
        case analytics
        case api
        case batch
        case state

        /// Map an `AppLog` category to the user-visible `LoggingSettings` category
        /// so the existing Logging Settings UI controls AppLog output too.
        fileprivate nonisolated var settingsCategory: LoggingSettings.LoggingCategory {
            switch self {
            case .general:    return .general
            case .allergen:   return .allergen
            case .fodmap:     return .fodmap
            case .recipe:     return .recipe
            case .network:    return .network
            case .storage:    return .storage
            case .ui:         return .ui
            case .extraction: return .extraction
            case .image:      return .image
            case .background: return .background
            case .lifecycle:  return .lifecycle
            case .sync:       return .sync
            case .cloudKit:   return .cloudkit
            case .sharing:    return .sharing
            case .backup:     return .backup
            case .onboarding: return .onboarding
            case .analytics:  return .analytics
            case .api:        return .api
            case .batch:      return .batch
            case .state:      return .state
            }
        }
    }

    // MARK: - Public Sync Facade
    //
    // All entry points are `nonisolated` so logging can be invoked from any
    // actor context (MainActor, custom actors, `Task.detached`, etc.) without
    // requiring `await`. Thread safety is provided by `os.Logger` (Sendable)
    // for OSLog output and by the `FileSink` actor for file mirroring.

    public nonisolated static func debug(
        _ message: String,
        category: Category = .general,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        emit(.debug, message, category, file, function, line)
    }

    public nonisolated static func info(
        _ message: String,
        category: Category = .general,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        emit(.info, message, category, file, function, line)
    }

    public nonisolated static func notice(
        _ message: String,
        category: Category = .general,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        // `LogLevel` has no distinct "notice"; warning is the closest non-error.
        emit(.warning, message, category, file, function, line)
    }

    public nonisolated static func warning(
        _ message: String,
        category: Category = .general,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        emit(.warning, message, category, file, function, line)
    }

    public nonisolated static func error(
        _ message: String,
        category: Category = .general,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        emit(.error, message, category, file, function, line)
    }

    public nonisolated static func critical(
        _ message: String,
        category: Category = .general,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        emit(.critical, message, category, file, function, line)
    }

    // MARK: - File-Backed Log Access

    /// URL of the persistent log file, if one was successfully created.
    public nonisolated static func currentLogFileURL() async -> URL? {
        await FileSink.shared.currentURL()
    }

    /// Read the full contents of the persistent log file.
    public nonisolated static func readLogContents() async -> String {
        await FileSink.shared.readAll()
    }

    /// Truncate the persistent log file.
    public nonisolated static func clearPersistentLog() async {
        await FileSink.shared.clear()
    }

    // MARK: - Internals

    /// One `Logger` per `Category`. Built once, immutable thereafter. Safe to
    /// expose as `let static` because `os.Logger` is `Sendable` and the
    /// dictionary's value-type composition is `Sendable` by inference.
    private nonisolated static let osLoggers: [Category: Logger] = {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.reczipes"
        var dict: [Category: Logger] = [:]
        for category in Category.allCases {
            dict[category] = Logger(subsystem: bundleID, category: category.rawValue)
        }
        return dict
    }()

    private nonisolated static func emit(
        _ level: LogLevel,
        _ message: String,
        _ category: Category,
        _ file: String,
        _ function: String,
        _ line: Int
    ) {
        // === Gate 1: level ===
        // Honor the user's overall logging level (off / errors / warnings /
        // info / debug) via the existing settings surface. If a lower level
        // than configured is requested, drop the entry before doing any work.
        guard LoggingHelper.shouldLog(level: level) else { return }

        // === Gate 2: category ===
        // Honor the user's per-category toggle. Uses the typed overload so
        // multi-word rawValues like "Allergen Detection" match correctly.
        guard LoggingHelper.shouldLog(category: category.settingsCategory) else { return }

        let logger = osLoggers[category] ?? osLoggers[.general]!
        let location = "[\(file):\(line)] \(function)"

        // OSLog emission. Use `.public` privacy for fileID/function/line and
        // leave message at default (auto-redact in release).
        switch level {
        case .debug:
            logger.debug("\(location, privacy: .public) — \(message)")
        case .info:
            logger.info("\(location, privacy: .public) — \(message)")
        case .warning:
            // OSLog has no distinct "warning"; route to `.error` so it
            // surfaces clearly in Console.app, and prefix the file mirror.
            logger.error("\(location, privacy: .public) — [WARNING] \(message)")
        case .error:
            logger.error("\(location, privacy: .public) — \(message)")
        case .critical:
            logger.critical("\(location, privacy: .public) — \(message)")
        }

        // === Gate 3: file mirror ===
        // Skip the fire-and-forget Task entirely when the user has disabled
        // file logging. Avoids unbounded Task creation in performance-sensitive
        // builds.
        guard LoggingHelper.isFileLoggingEnabled else { return }

        let entry = formatFileEntry(
            level: level.rawValue,
            category: category.rawValue,
            location: location,
            message: message,
            timestamp: Date()
        )
        Task {
            await FileSink.shared.append(entry)
        }
    }

    private nonisolated static func formatFileEntry(
        level: String,
        category: String,
        location: String,
        message: String,
        timestamp: Date
    ) -> String {
        // `Date.formatted(.iso8601)` is Sendable-friendly — no shared formatter.
        let ts = timestamp.formatted(.iso8601)
        return "[\(ts)] [\(level)] [\(category)] \(location) → \(message)\n"
    }
}

// MARK: - File Sink Actor

/// Serialized, append-only file sink for `AppLog`. All access is
/// compile-time-enforced serial via the actor model — no locks, no queues.
private actor FileSink {
    static let shared = FileSink()

    private let fileURL: URL?
    private let fileManager: FileManager

    init() {
        let fm = FileManager()
        self.fileManager = fm
        let documents = try? fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = documents?.appendingPathComponent("reczipes_app.log")
        self.fileURL = url
        if let url, !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
    }

    func currentURL() -> URL? { fileURL }

    func append(_ entry: String) {
        guard let url = fileURL else { return }
        guard let data = entry.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Best-effort fallback — overwrite atomically only if append fails.
                try? data.write(to: url, options: .atomic)
            }
        } else {
            // File was deleted or never created; recreate.
            try? data.write(to: url, options: .atomic)
        }
    }

    func readAll() -> String {
        guard let url = fileURL else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func clear() {
        guard let url = fileURL else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }
}
