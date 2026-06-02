//
//  Extensions.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/4/25.
//

import Foundation

// MARK: - Ingredient Extensions
extension Ingredient {
    /// Returns a formatted display text for the ingredient
    var displayText: String {
        var parts: [String] = []
        
        if let quantity = quantity {
            parts.append(quantity)
        }
        
        if let unit = unit {
            parts.append(unit)
        }
        
        parts.append(name)
        
        if let preparation = preparation {
            parts.append("(\(preparation))")
        }
        
        return parts.joined(separator: " ")
    }
}


// MARK: - Book Extension

extension Book {
    convenience init(
        id: UUID,
        name: String,
        bookDescription: String?,
        dateCreated: Date,
        dateModified: Date,
        recipeIDs: [UUID],
        color: String?
    ) {
        self.init()
        self.id = id
        self.name = name
        self.bookDescription = bookDescription
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.recipeIDs = recipeIDs
        self.color = color
    }
}

/// Saves backup JSON data to a file
func saveBackupFile(jsonData: Data, prefix: String) async throws -> URL {
    // Get or create Reczipes2 folder
    var reczipesDirectory: URL
    
    let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    var isDir: ObjCBool = false
    let docsExists = FileManager.default.fileExists(atPath: documentsDirectory.path, isDirectory: &isDir)
    
    if docsExists && isDir.boolValue {
        reczipesDirectory = documentsDirectory.appendingPathComponent("Reczipes2")
    } else {
        AppLog.warning("Documents directory not accessible, using temporary directory", category: .backup)
        reczipesDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Reczipes2")
    }
    
    try FileManager.default.createDirectory(at: reczipesDirectory, withIntermediateDirectories: true, attributes: nil)
    
    // Create filename with timestamp and milliseconds
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
    let currentDate = Date()
    let dateString = dateFormatter.string(from: currentDate)
    let milliseconds = Int((currentDate.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)
    let fileName = "\(prefix)_\(dateString)_\(String(format: "%03d", milliseconds)).reczipes"
    let fileURL = reczipesDirectory.appendingPathComponent(fileName)
    
    try jsonData.write(to: fileURL)
    AppLog.info("Backup created successfully: \(fileName) (\(jsonData.count) bytes)", category: .backup)
    return fileURL
}

// MARK: - Extension to make logging easier

extension RecipeX {
    /// Log this recipe's creation
    @MainActor func logCreation() {
        CloudKitSyncLogger.shared.logRecipeCreated(self)
    }
    
    /// Log this recipe's update
    @MainActor func logUpdate() {
        CloudKitSyncLogger.shared.logRecipeUpdated(self)
    }
}
