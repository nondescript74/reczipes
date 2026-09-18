//
//  RecipeExportImportRestoreTests.swift
//  Reczipes2Tests
//
//  Tests for backup import, overwrite modes, and restore workflows
//  Created on 1/5/26.
//

import Testing
import Foundation
import SwiftData
@testable import Reczipes2

@Suite("Recipe Backup Restore Tests", .serialized)
@MainActor
struct RecipeExportImportRestoreTests {
    
    // MARK: - Helper Functions
    
    /// Helper to get the Reczipes2 backup directory path
    /// Uses the same logic as RecipeBackupManager to handle test environments
    func getBackupDirectory() -> URL {
        // Use the same logic as RecipeBackupManager
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Check if Documents directory is accessible
        var isDir: ObjCBool = false
        let docsExists = FileManager.default.fileExists(atPath: documentsDirectory.path, isDirectory: &isDir)
        
        if docsExists && isDir.boolValue {
            return documentsDirectory.appendingPathComponent("Reczipes2", isDirectory: true)
        } else {
            // Fall back to temp directory (common in test environments)
            return FileManager.default.temporaryDirectory.appendingPathComponent("Reczipes2", isDirectory: true)
        }
    }
    
    /// Helper to encode ingredient sections
    func encodeIngredientSections(_ sections: [IngredientSection]) throws -> Data {
        return try JSONEncoder().encode(sections)
    }
    
    /// Helper to encode instruction sections
    func encodeInstructionSections(_ sections: [InstructionSection]) throws -> Data {
        return try JSONEncoder().encode(sections)
    }
    
    /// Helper to encode notes
    func encodeNotes(_ notes: [RecipeNote]) throws -> Data {
        return try JSONEncoder().encode(notes)
    }
    
    /// Creates a complete RecipeX with all fields populated
    func createCompleteRecipe() throws -> RecipeX {
        return RecipeX(
            id: UUID(),
            title: "Test Recipe: Complete Lasagna",
            headerNotes: "A delicious Italian classic",
            recipeYield: "Serves 8-10",
            reference: "Grandma's recipe book, page 42",
            ingredientSectionsData: try encodeIngredientSections([
                IngredientSection(
                    title: "For the Sauce",
                    ingredients: [
                        Ingredient(quantity: "2", unit: "lbs", name: "ground beef", preparation: "browned")
                    ]
                )
            ]),
            instructionSectionsData: try encodeInstructionSections([
                InstructionSection(
                    title: "Prepare the Sauce",
                    steps: [
                        InstructionStep(stepNumber: 1, text: "Brown the ground beef in a large skillet")
                    ]
                )
            ]),
            notesData: try encodeNotes([
                RecipeNote(type: .tip, text: "Let the lasagna rest for 10 minutes before cutting")
            ])
        )
    }
    
    /// Creates a minimal RecipeX
    func createMinimalRecipe() throws -> RecipeX {
        return RecipeX(
            title: "Simple Toast",
            ingredientSectionsData: try encodeIngredientSections([
                IngredientSection(ingredients: [Ingredient(name: "bread")])
            ]),
            instructionSectionsData: try encodeInstructionSections([
                InstructionSection(steps: [InstructionStep(stepNumber: 1, text: "Toast the bread")])
            ])
        )
    }
    
    // MARK: - Import Success Tests
    
    @Test("Importing backup from Reczipes2 folder succeeds")
    func testImportBackupFromReczipes2Folder() async throws {
        // Create export
        let exportSchema = Schema([RecipeX.self, Book.self])
        let exportConfig = ModelConfiguration(schema: exportSchema, isStoredInMemoryOnly: true)
        let exportContainer = try ModelContainer(for: exportSchema, configurations: [exportConfig])
        let exportContext = exportContainer.mainContext
        
        let originalRecipe = try createCompleteRecipe()
        exportContext.insert(originalRecipe)
        
        let backupURL = try await RecipeBackupManager.shared.createBackup(from: [originalRecipe])
        
        // Create new context for import
        let importSchema = Schema([RecipeX.self, Book.self])
        let importConfig = ModelConfiguration(schema: importSchema, isStoredInMemoryOnly: true)
        let importContainer = try ModelContainer(for: importSchema, configurations: [importConfig])
        let importContext = importContainer.mainContext
        
        // Import backup
        let result = try await RecipeBackupManager.shared.importBackup(
            from: backupURL,
            into: importContext,
            existingRecipes: [],
            overwriteMode: .overwrite
        )
        
        #expect(result.newRecipes == 1, 
                "Should import 1 new recipe, got: \(result.newRecipes)")
        #expect(result.totalRecipes == 1, 
                "Total recipes should be 1, got: \(result.totalRecipes)")
        
        print("✓ Successfully imported backup: \(result.summary)")
        
        // Cleanup
        try? FileManager.default.removeItem(at: backupURL)
    }
    
    @Test("Import with overwrite mode replaces existing recipes")
    func testImportOverwriteMode() async throws {
        let schema = Schema([RecipeX.self, Book.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        // Create and export a recipe
        let originalRecipe = try createCompleteRecipe()
        context.insert(originalRecipe)
        
        let backupURL = try await RecipeBackupManager.shared.createBackup(from: [originalRecipe])
        
        // Import with overwrite mode (recipe already exists)
        let result = try await RecipeBackupManager.shared.importBackup(
            from: backupURL,
            into: context,
            existingRecipes: [originalRecipe],
            overwriteMode: .overwrite
        )
        
        #expect(result.updatedRecipes == 1, 
                "overwrite mode should update existing recipe")
        #expect(result.newRecipes == 0, 
                "overwrite mode should not create new recipes when they exist")
        
        print("✓ overwrite mode correctly replaces existing recipes")
        
        // Cleanup
        try? FileManager.default.removeItem(at: backupURL)
    }
    
    // MARK: - Import Failure Tests
    
    @Test("Importing from non-existent file throws error")
    func testImportNonExistentFile() async {
        let nonExistentURL = getBackupDirectory().appendingPathComponent("DoesNotExist.reczipes")
        
        let schema = Schema([RecipeX.self, Book.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        do {
            _ = try await RecipeBackupManager.shared.importBackup(
                from: nonExistentURL,
                into: context,
                existingRecipes: [],
                overwriteMode: .overwrite
            )
            #expect(Bool(false), "Should throw error for non-existent file")
        } catch RecipeBackupError.invalidBackupFile {
            print("✓ Correctly throws invalidBackupFile error for non-existent file")
        } catch {
            print("✓ Throws error for non-existent file: \(error.localizedDescription)")
        }
    }
    
    @Test("Importing corrupted backup file throws decoding error")
    func testImportCorruptedBackupFile() async throws {
        // Use the manager's own directory resolution (guaranteed writable)
        let backupDir = RecipeBackupManager.shared.getBackupDirectoryShared()
        let corruptedURL = backupDir.appendingPathComponent("TEST_Corrupted.reczipes")
        let corruptedData = "This is not valid JSON {{{".data(using: .utf8)!
        try corruptedData.write(to: corruptedURL)
        
        let schema = Schema([RecipeX.self, Book.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        do {
            _ = try await RecipeBackupManager.shared.importBackup(
                from: corruptedURL,
                into: context,
                existingRecipes: [],
                overwriteMode: .overwrite
            )
            #expect(Bool(false), "Should throw decoding error for corrupted file")
        } catch RecipeBackupError.decodingFailed(let underlyingError) {
            print("✓ Correctly throws decodingFailed error for corrupted file")
            print("  Underlying error: \(underlyingError.localizedDescription)")
        } catch {
            print("✓ Throws error for corrupted file: \(error.localizedDescription)")
        }
        
        // Cleanup
        try? FileManager.default.removeItem(at: corruptedURL)
    }
    
    @Test("Importing empty backup file throws error")
    func testImportEmptyBackupFile() async throws {
        // Use the manager's own directory resolution (guaranteed writable)
        let backupDir = RecipeBackupManager.shared.getBackupDirectoryShared()
        let emptyURL = backupDir.appendingPathComponent("TEST_Empty.reczipes")
        let emptyData = Data()
        try emptyData.write(to: emptyURL)
        
        let schema = Schema([RecipeX.self, Book.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        do {
            _ = try await RecipeBackupManager.shared.importBackup(
                from: emptyURL,
                into: context,
                existingRecipes: [],
                overwriteMode: .overwrite
            )
            #expect(Bool(false), "Should throw error for empty file")
        } catch {
            print("✓ Correctly throws error for empty backup file: \(error.localizedDescription)")
        }
        
        // Cleanup
        try? FileManager.default.removeItem(at: emptyURL)
    }
    
    // MARK: - Backup Persistence Tests
    
    @Test("Backup persists across app sessions")
    func testBackupPersistence() async throws {
        let schema = Schema([RecipeX.self, Book.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        let testRecipe = try createMinimalRecipe()
        context.insert(testRecipe)
        
        // Create backup
        let backupURL = try await RecipeBackupManager.shared.createBackup(from: [testRecipe])
        let fileName = backupURL.lastPathComponent
        
        // Set up cleanup to happen no matter what
        defer {
            try? FileManager.default.removeItem(at: backupURL)
            print("🗑️ Cleaned up backup: \(fileName)")
        }
        
        print("Created backup: \(fileName) at: \(backupURL.path)")
        
        // Verify file exists immediately
        let existsImmediately = FileManager.default.fileExists(atPath: backupURL.path)
        print("File exists immediately: \(existsImmediately)")
        #expect(existsImmediately, 
                "Backup should exist immediately after creation at: \(backupURL.path)")
        
        // Verify it appears in the list immediately
        var availableBackups = try RecipeBackupManager.shared.listAvailableBackups()
        var foundBackup = availableBackups.first { $0.fileName == fileName }
        
        print("Found in list immediately: \(foundBackup != nil)")
        print("Available backups: \(availableBackups.map { $0.fileName })")
        
        #expect(foundBackup != nil, 
                "Backup should be in available backups list immediately")
        
        // Wait a moment (simulating app closing/reopening)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Verify file still exists after waiting
        let existsAfterWait = FileManager.default.fileExists(atPath: backupURL.path)
        print("File exists after waiting: \(existsAfterWait)")
        #expect(existsAfterWait, 
                "Backup should still exist after waiting at: \(backupURL.path)")
        
        // Verify it's still in the list after waiting
        availableBackups = try RecipeBackupManager.shared.listAvailableBackups()
        foundBackup = availableBackups.first { $0.fileName == fileName }
        
        print("Found in list after waiting: \(foundBackup != nil)")
        
        #expect(foundBackup != nil, 
                "Backup should still be in available backups list after waiting")
        
        print("✓ Backup persists across simulated app sessions")
    }
    
    @Test("Multiple sequential backups all persist")
    func testMultipleSequentialBackups() async throws {
        let schema = Schema([RecipeX.self, Book.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        let testRecipe = try createMinimalRecipe()
        context.insert(testRecipe)
        
        var backupURLs: [URL] = []
        var backupFileNames: [String] = []
        
        // Create 3 backups sequentially
        for i in 1...3 {
            let backupURL = try await RecipeBackupManager.shared.createBackup(from: [testRecipe])
            backupURLs.append(backupURL)
            backupFileNames.append(backupURL.lastPathComponent)
            
            // Verify file exists immediately after creation
            #expect(FileManager.default.fileExists(atPath: backupURL.path), 
                    "Backup \(i) should exist immediately after creation at: \(backupURL.path)")
            
            print("Created backup \(i): \(backupURL.lastPathComponent) - exists: \(FileManager.default.fileExists(atPath: backupURL.path))")
            
            // Small delay to ensure different timestamps
            if i < 3 {
                try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds
            }
        }
        
        // Wait a moment before final verification
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Verify all backups still exist
        print("Verifying all backups still exist...")
        for (i, url) in backupURLs.enumerated() {
            let exists = FileManager.default.fileExists(atPath: url.path)
            print("  Backup \(i + 1) (\(url.lastPathComponent)): exists = \(exists)")
            #expect(exists, "Backup \(i + 1) should still exist at: \(url.path)")
        }
        
        // Verify all appear in available backups by checking their filenames
        let availableBackups = try RecipeBackupManager.shared.listAvailableBackups()
        let availableFileNames = Set(availableBackups.map { $0.fileName })
        
        print("Available backups: \(availableFileNames.sorted())")
        print("Expected backups: \(backupFileNames.sorted())")
        
        for (i, fileName) in backupFileNames.enumerated() {
            #expect(availableFileNames.contains(fileName), 
                    "Backup \(i + 1) (\(fileName)) should be in available backups list")
        }
        
        print("✓ All \(backupURLs.count) sequential backups persisted successfully")
        
        // Cleanup - with retry logic
        for url in backupURLs {
            do {
                try FileManager.default.removeItem(at: url)
                print("🗑️ Cleaned up: \(url.lastPathComponent)")
            } catch {
                print("⚠️ Failed to clean up \(url.lastPathComponent): \(error)")
                // Try again after brief delay
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                try? FileManager.default.removeItem(at: url)
            }
        }
        
        // Final verification of cleanup
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        let remainingFiles = backupURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !remainingFiles.isEmpty {
            print("⚠️ Warning: \(remainingFiles.count) backup file(s) could not be deleted")
        }
    }
}
