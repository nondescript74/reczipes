//
//  DatabaseRecoveryService.swift
//  Reczipes2
//
//  Created by Assistant on 1/15/26.
//  Helps recover recipes after database file location changes
//

import Foundation
import SwiftData

@MainActor
class DatabaseRecoveryService {
    
    /// Check if we need to migrate from an old database file to the current one
    static func checkForDatabaseMigration() async -> DatabaseMigrationInfo? {
        let fileManager = FileManager.default
        let appSupport = URL.applicationSupportDirectory
        
        // Current database file
        let currentDB = appSupport.appendingPathComponent("CloudKitModel.sqlite")
        
        // Possible old database locations
        let oldDatabases = [
            "default.store",
            "Model.sqlite",
            "Reczipes2.sqlite"
        ]
        
        // Check if current database is empty or very small
        let currentSize = getDatabaseSize(currentDB)
        let currentIsEmpty = currentSize < 50_000 // Less than 50KB suggests empty
        
        // Find the largest old database
        var largestOldDB: (url: URL, size: Int64)?
        
        for dbName in oldDatabases {
            let url = appSupport.appendingPathComponent(dbName)
            
            if fileManager.fileExists(atPath: url.path) {
                let size = getDatabaseSize(url)
                
                // Only consider databases with substantial data
                if size > 100_000 { // More than 100KB
                    if largestOldDB == nil || size > largestOldDB!.size {
                        largestOldDB = (url, size)
                    }
                }
            }
        }
        
        // If current is empty but we have a large old database, migration needed
        if currentIsEmpty, let oldDB = largestOldDB {
            return DatabaseMigrationInfo(
                oldDatabaseURL: oldDB.url,
                oldDatabaseSize: oldDB.size,
                currentDatabaseURL: currentDB,
                currentDatabaseSize: currentSize
            )
        }
        
        return nil
    }
    
    /// Get the size of a database file
    private static func getDatabaseSize(_ url: URL) -> Int64 {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: url.path) else {
            return 0
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            AppLog.warning("⚠️  Failed to get size for \(url.lastPathComponent): \(error)", category: .storage)
            return 0
        }
    }
    
    /// Attempt to recover recipes from old database file
    
    /// Copy old database file to current location
    static func copyOldDatabaseToCurrent(migrationInfo: DatabaseMigrationInfo) throws {
        let fileManager = FileManager.default
        
        AppLog.info("📋 Copying database file...", category: .storage)
        AppLog.info("   From: \(migrationInfo.oldDatabaseURL.path)", category: .storage)
        AppLog.info("   To: \(migrationInfo.currentDatabaseURL.path)", category: .storage)
        
        // Remove current database if it exists (assuming it's empty)
        if fileManager.fileExists(atPath: migrationInfo.currentDatabaseURL.path) {
            try fileManager.removeItem(at: migrationInfo.currentDatabaseURL)
            AppLog.info("   Removed existing empty database", category: .storage)
        }
        
        // Copy old database to current location
        try fileManager.copyItem(
            at: migrationInfo.oldDatabaseURL,
            to: migrationInfo.currentDatabaseURL
        )
        
        // Also copy associated files (-wal, -shm)
        let walSource = migrationInfo.oldDatabaseURL.appendingPathExtension("wal")
        let walDest = migrationInfo.currentDatabaseURL.appendingPathExtension("wal")
        if fileManager.fileExists(atPath: walSource.path) {
            try? fileManager.copyItem(at: walSource, to: walDest)
        }
        
        let shmSource = migrationInfo.oldDatabaseURL.appendingPathExtension("shm")
        let shmDest = migrationInfo.currentDatabaseURL.appendingPathExtension("shm")
        if fileManager.fileExists(atPath: shmSource.path) {
            try? fileManager.copyItem(at: shmSource, to: shmDest)
        }
        
        AppLog.info("✅ Database copied successfully", category: .storage)
    }
    
    /// Backup the old database before any operations
    static func backupOldDatabase(url: URL) throws -> URL {
        let fileManager = FileManager.default
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-backup-\(timestamp).sqlite")
        
        try fileManager.copyItem(at: url, to: backupURL)
        AppLog.info("✅ Backup created: \(backupURL.lastPathComponent)", category: .storage)
        
        return backupURL
    }
}

// MARK: - Supporting Types

struct DatabaseMigrationInfo {
    let oldDatabaseURL: URL
    let oldDatabaseSize: Int64
    let currentDatabaseURL: URL
    let currentDatabaseSize: Int64
    
    var oldDatabaseSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: oldDatabaseSize, countStyle: .file)
    }
    
    var currentDatabaseSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: currentDatabaseSize, countStyle: .file)
    }
}

struct RecoveryResult {
    let recipesFound: Int
    let booksFound: Int
    let profilesFound: Int
    let oldDatabaseURL: URL
    
    var hasData: Bool {
        // If counts are unknown (-1), assume we have data
        // since we only get here if the database file was large enough
        if recipesFound < 0 {
            return true
        }
        return recipesFound > 0 || booksFound > 0 || profilesFound > 0
    }
}
