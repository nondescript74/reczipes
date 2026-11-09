//
//  VersionHistoryService.swift
//  Reczipes2
//
//  Created on 02/01/26.
//

import Foundation
import SwiftData

// MARK: - Version History Service

@MainActor
class VersionHistoryService {
    static let shared = VersionHistoryService()
    
    private let lastShownVersionKey = "com.reczipes.lastShownVersion"
    private var modelContext: ModelContext?
    
    private init() {}
    
    // MARK: - Setup
    
    /// Initialize with the app's model context
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Version Management
    
    /// Get the current app version
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    /// Get the current build number
    var currentBuildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    /// Get the current version string
    var currentVersionString: String {
        "\(currentVersion) (\(currentBuildNumber))"
    }
    
    // MARK: - Add/Update History
    
    /// Add a new version history entry (checks for duplicates)
    func addVersionHistory(version: String, buildNumber: String, releaseDate: Date = Date(), changes: [String]) throws {
        guard let context = modelContext else {
            throw VersionHistoryError.contextNotInitialized
        }
        
        // Check if version already exists
        let versionString = "\(version) (\(buildNumber))"
        let descriptor = FetchDescriptor<VersionHistoryRecord>(
            predicate: #Predicate { record in
                record.versionString == versionString
            }
        )
        
        let existing = try context.fetch(descriptor)
        
        if existing.isEmpty {
            // Add new entry
            let record = VersionHistoryRecord(
                version: version,
                buildNumber: buildNumber,
                releaseDate: releaseDate,
                changes: changes
            )
            context.insert(record)
            try context.save()
            print("✅ Added version history: \(versionString)")
        } else {
            print("⚠️ Version \(versionString) already exists in history")
        }
    }
    
    /// Add current version with changes (convenience method)
    func addCurrentVersion(changes: [String]) throws {
        try addVersionHistory(
            version: currentVersion,
            buildNumber: currentBuildNumber,
            releaseDate: Date(),
            changes: changes
        )
    }
    
    // MARK: - Query History
    
    /// Get all version history records, sorted by release date (newest first)
    func getAllHistory() throws -> [VersionHistoryRecord] {
        guard let context = modelContext else {
            throw VersionHistoryError.contextNotInitialized
        }
        
        let descriptor = FetchDescriptor<VersionHistoryRecord>(
            sortBy: [SortDescriptor(\.releaseDate, order: .reverse)]
        )
        
        return try context.fetch(descriptor)
    }
    
    /// Get version history entry for a specific version
    func getHistory(for versionString: String) throws -> VersionHistoryRecord? {
        guard let context = modelContext else {
            throw VersionHistoryError.contextNotInitialized
        }
        
        let descriptor = FetchDescriptor<VersionHistoryRecord>(
            predicate: #Predicate { record in
                record.versionString == versionString
            }
        )
        
        return try context.fetch(descriptor).first
    }
    
    /// Get version history entry for current version
    func getCurrentVersionEntry() throws -> VersionHistoryRecord? {
        return try getHistory(for: currentVersionString)
    }
    
    /// Get what's new for the current version (changes since last shown version)
    func getWhatsNew() throws -> [String] {
        guard let currentEntry = try getCurrentVersionEntry() else {
            return ["Welcome to Reczipes!"]
        }
        
        return currentEntry.changes
    }
    
    // MARK: - What's New Tracking
    
    /// Check if this is a new version (should show what's new)
    func shouldShowWhatsNew() -> Bool {
        let lastShownVersion = UserDefaults.standard.string(forKey: lastShownVersionKey)
        let currentVersionString = self.currentVersionString
        
        // First launch or version changed
        return lastShownVersion == nil || lastShownVersion != currentVersionString
    }
    
    /// Mark current version as shown
    func markWhatsNewAsShown() {
        UserDefaults.standard.set(currentVersionString, forKey: lastShownVersionKey)
    }
    
    // MARK: - Formatted Output
    
    /// Get formatted changelog text
    func getFormattedChangelog() throws -> String {
        var changelog = ""
        let history = try getAllHistory()
        
        for record in history {
            changelog += "Version \(record.versionString)\n"
            changelog += "Released: \(formatDate(record.releaseDate))\n\n"
            
            for change in record.changes {
                changelog += "• \(change)\n"
            }
            
            changelog += "\n---\n\n"
        }
        
        return changelog
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // MARK: - Development Helper
    
    /// Reset version tracking (useful for testing)
    func resetVersionTracking() {
        UserDefaults.standard.removeObject(forKey: lastShownVersionKey)
    }
    
    /// Delete all version history (use with caution)
    func deleteAllHistory() throws {
        guard let context = modelContext else {
            throw VersionHistoryError.contextNotInitialized
        }
        
        try context.delete(model: VersionHistoryRecord.self)
        try context.save()
        print("🗑️ Deleted all version history")
    }
}

// MARK: - Error Types

enum VersionHistoryError: LocalizedError {
    case contextNotInitialized
    case versionAlreadyExists
    
    var errorDescription: String? {
        switch self {
        case .contextNotInitialized:
            return String(localized: "Version history service not initialized with model context", bundle: .appLanguage)
        case .versionAlreadyExists:
            return String(localized: "This version already exists in history", bundle: .appLanguage)
        }
    }
}
