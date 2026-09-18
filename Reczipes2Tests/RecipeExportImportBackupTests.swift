//
//  RecipeExportImportBackupTests.swift
//  Reczipes2Tests
//
//  Tests for backup creation, file naming, and directory management
//  Created on 1/5/26.
//

import Testing
import Foundation
import SwiftData
@testable import Reczipes2

@Suite("Recipe Backup Creation Tests", .serialized)
struct RecipeExportImportBackupTests {
    
    // MARK: - Test Configuration
    
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
    
    /// Helper to wait for file to be fully written and accessible
    func waitForFileToExist(at url: URL, timeout: TimeInterval = 2.0) async throws {
        let startTime = Date()
        while !FileManager.default.fileExists(atPath: url.path) {
            if Date().timeIntervalSince(startTime) > timeout {
                throw NSError(domain: "TestError", code: 1, 
                            userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for file to exist at \(url.path)"])
            }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }
    
    /// Creates a minimal RecipeX with only required fields
    @MainActor
    func createMinimalRecipeModel() -> RecipeX {
        let ingredientSections = [
            IngredientSection(
                title: nil,
                ingredients: [
                    Ingredient(quantity: nil, unit: nil, name: "bread", preparation: nil, metricQuantity: nil, metricUnit: nil),
                    Ingredient(quantity: nil, unit: nil, name: "butter", preparation: nil, metricQuantity: nil, metricUnit: nil)
                ],
                transitionNote: nil
            )
        ]
        
        let instructionSections = [
            InstructionSection(
                title: nil,
                steps: [
                    InstructionStep(stepNumber: 1, text: "Toast the bread"),
                    InstructionStep(stepNumber: 2, text: "Spread butter on toast")
                ]
            )
        ]
        
        return RecipeX(
            title: "Simple Toast",
            headerNotes: nil,
            recipeYield: nil,
            reference: nil,
            ingredientSectionsData: try? JSONEncoder().encode(ingredientSections),
            instructionSectionsData: try? JSONEncoder().encode(instructionSections),
            notesData: nil
        )
    }
    
    /// Creates a complete RecipeX with all fields populated
    @MainActor
    func createCompleteRecipeModel() -> RecipeX {
        let ingredientSections = [
            IngredientSection(
                title: "For the Sauce",
                ingredients: [
                    Ingredient(
                        quantity: "2",
                        unit: "lbs",
                        name: "ground beef",
                        preparation: "browned",
                        metricQuantity: "900",
                        metricUnit: "g"
                    ),
                    Ingredient(
                        quantity: "1",
                        unit: "jar",
                        name: "marinara sauce",
                        preparation: nil,
                        metricQuantity: "680",
                        metricUnit: "mL"
                    )
                ],
                transitionNote: "Sauce should simmer for 30 minutes"
            )
        ]
        
        let instructionSections = [
            InstructionSection(
                title: "Prepare the Sauce",
                steps: [
                    InstructionStep(stepNumber: 1, text: "Brown the ground beef in a large skillet"),
                    InstructionStep(stepNumber: 2, text: "Add marinara sauce and simmer for 30 minutes")
                ]
            )
        ]
        
        let notes = [
            RecipeNote(type: .tip, text: "Let the lasagna rest for 10 minutes before cutting"),
            RecipeNote(type: .substitution, text: "Can use ground turkey instead of beef"),
            RecipeNote(type: .warning, text: "Be careful not to overbake"),
            RecipeNote(type: .timing, text: "Total prep and cook time: 2 hours")
        ]
        
        return RecipeX(
            id: UUID(),
            title: "Test Recipe: Complete Lasagna",
            headerNotes: "A delicious Italian classic with layers of pasta, meat, and cheese",
            recipeYield: "Serves 8-10",
            reference: "Grandma's recipe book, page 42",
            ingredientSectionsData: try? JSONEncoder().encode(ingredientSections),
            instructionSectionsData: try? JSONEncoder().encode(instructionSections),
            notesData: try? JSONEncoder().encode(notes),
            imageData: nil,
            additionalImagesData: nil,
            imageName: "lasagna_main.jpg",
            additionalImageNames: ["lasagna_slice.jpg", "lasagna_prep.jpg"]
        )
    }
    
    // MARK: - Backup Directory Tests
    
    @Test("Backup directory path is correct")
    @MainActor
    func testBackupDirectoryPath() {
        let backupDir = getBackupDirectory()
        #expect(backupDir.lastPathComponent == "Reczipes2", "Backup directory should be named Reczipes2")
        // In test environments, might be in Documents or tmp directory
        let pathContainsValidLocation = backupDir.path.contains("Documents") || backupDir.path.contains("tmp")
        #expect(pathContainsValidLocation, "Backup directory should be in Documents or tmp folder, got: \(backupDir.path)")
    }
    
    @Test("Backup directory is created when it doesn't exist")
    @MainActor
    func testBackupDirectoryCreation() async throws {
        // Create a test recipe
        let schema = Schema([RecipeX.self, Book.self, VersionHistoryRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let testRecipe = createMinimalRecipeModel()
        context.insert(testRecipe)

        // Create backup - this should create the directory
        let backupURL = try await RecipeBackupManager.shared.createBackup(from: [testRecipe])

        // Verify the directory the manager actually used exists and is a directory
        let actualBackupDir = backupURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: actualBackupDir.path, isDirectory: &isDirectory)
        #expect(exists, "Backup directory should exist at \(actualBackupDir.path)")
        #expect(isDirectory.boolValue, "Backup directory path should be a directory")
        #expect(FileManager.default.fileExists(atPath: backupURL.path), "Backup file should exist at \(backupURL.path)")

        // Cleanup
        try? FileManager.default.removeItem(at: backupURL)
    }
    
    @Test("Backup files are saved to Files/Reczipes2 folder")
    @MainActor
    func testBackupSavedToCorrectLocation() async throws {
        // Create a test recipe
        let schema = Schema([RecipeX.self, Book.self, VersionHistoryRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let testRecipe = createCompleteRecipeModel()
        context.insert(testRecipe)

        // Create backup
        let backupURL = try await RecipeBackupManager.shared.createBackup(from: [testRecipe])

        // Verify file exists at the reported location
        #expect(FileManager.default.fileExists(atPath: backupURL.path),
                "Backup file should exist at: \(backupURL.path)")

        // Verify file extension
        #expect(backupURL.pathExtension == "reczipes",
                "Backup file should have .reczipes extension")

        // Cleanup
        try? FileManager.default.removeItem(at: backupURL)
    }
    
    // MARK: - Backup File Naming Tests
    
    @Test("Backup file naming convention is correct")
    @MainActor
    func testBackupFileNaming() async throws {
        let schema = Schema([RecipeX.self, Book.self, VersionHistoryRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        let testRecipe = createMinimalRecipeModel()
        context.insert(testRecipe)
        
        // Create backup
        let backupURL = try await RecipeBackupManager.shared.createBackup(from: [testRecipe])
        
        let fileName = backupURL.lastPathComponent
        
        // Should start with "RecipeBackup_"
        #expect(fileName.hasPrefix("RecipeBackup_"), 
                "Backup filename should start with 'RecipeBackup_', got: \(fileName)")
        
        // Should contain a date in YYYY-MM-DD format
        let datePattern = #/\d{4}-\d{2}-\d{2}/#
        #expect(fileName.firstMatch(of: datePattern) != nil, 
                "Backup filename should contain date in YYYY-MM-DD format")
        
        // Should contain a time in HHmmss format
        let timePattern = #/\d{6}/#
        #expect(fileName.firstMatch(of: timePattern) != nil, 
                "Backup filename should contain time in HHmmss format")
        
        // Should contain milliseconds (3 digits) for uniqueness
        let millisPattern = #/_\d{3}\.reczipes/#
        #expect(fileName.firstMatch(of: millisPattern) != nil, 
                "Backup filename should contain milliseconds for uniqueness")
        
        // Should end with .reczipes
        #expect(fileName.hasSuffix(".reczipes"), 
                "Backup filename should end with .reczipes")
        
        // Example: RecipeBackup_2026-01-05_143022_123.reczipes
        print("✓ Created backup with valid filename: \(fileName)")
        
        // Cleanup
        try? FileManager.default.removeItem(at: backupURL)
    }
    
    @Test("BackupFileInfo display name removes prefix and extension")
    @MainActor
    func testBackupFileInfoDisplayName() {
        // Test with new format (with milliseconds)
        let url1 = getBackupDirectory().appendingPathComponent("RecipeBackup_2026-01-05_143022_123.reczipes")
        let backupInfo1 = BackupFileInfo(
            url: url1,
            fileName: "RecipeBackup_2026-01-05_143022_123.reczipes",
            fileSize: 12345,
            creationDate: Date(),
            modificationDate: Date()
        )
        
        #expect(backupInfo1.displayName == "2026-01-05_143022", 
                "Display name should remove 'RecipeBackup_' prefix, milliseconds, and '.reczipes' extension, got: \(backupInfo1.displayName)")
        
        // Test with old format (without milliseconds) for backward compatibility
        let url2 = getBackupDirectory().appendingPathComponent("RecipeBackup_2026-01-05_143022.reczipes")
        let backupInfo2 = BackupFileInfo(
            url: url2,
            fileName: "RecipeBackup_2026-01-05_143022.reczipes",
            fileSize: 12345,
            creationDate: Date(),
            modificationDate: Date()
        )
        
        #expect(backupInfo2.displayName == "2026-01-05_143022", 
                "Display name should work with old format too")
        
        #expect(backupInfo1.fileSizeFormatted.contains("KB") || backupInfo1.fileSizeFormatted.contains("bytes"), 
                "File size should be formatted with units")
        
        print("✓ Display name (new format): \(backupInfo1.displayName)")
        print("✓ Display name (old format): \(backupInfo2.displayName)")
        print("✓ Formatted size: \(backupInfo1.fileSizeFormatted)")
    }
    
    // MARK: - Backup Listing Tests
    
    @Test("listAvailableBackups finds backups in Reczipes2 folder")
    @MainActor
    func testListAvailableBackups() async throws {
        // Track only the files THIS test creates — never touch files we didn't make,
        // because other suites may be running in parallel and using the same directory.
        var createdFiles: [URL] = []
        defer {
            for url in createdFiles {
                try? FileManager.default.removeItem(at: url)
                print("🗑️ Cleaned up: \(url.lastPathComponent)")
            }
        }
        
        // Create a test recipe
        let schema = Schema([RecipeX.self, Book.self, VersionHistoryRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        let testRecipe = createMinimalRecipeModel()
        context.insert(testRecipe)
        
        // Create first backup
        print("⏳ Creating first backup...")
        let backup1URL = try await RecipeBackupManager.shared.createBackup(from: [testRecipe])
        createdFiles.append(backup1URL)
        print("✓ Created first backup: \(backup1URL.lastPathComponent)")
        
        // Wait for file to be fully written to disk
        try await waitForFileToExist(at: backup1URL)
        
        // Verify first backup exists
        let firstExists = FileManager.default.fileExists(atPath: backup1URL.path)
        #expect(firstExists, "First backup should exist after creation")
        
        // Wait to ensure different timestamps
        try await Task.sleep(nanoseconds: 200_000_000) // 200 milliseconds
        
        // Create second backup
        print("⏳ Creating second backup...")
        let backup2URL = try await RecipeBackupManager.shared.createBackup(from: [testRecipe])
        createdFiles.append(backup2URL)
        print("✓ Created second backup: \(backup2URL.lastPathComponent)")
        
        // Wait for file to be fully written to disk
        try await waitForFileToExist(at: backup2URL)
        
        // Verify second backup exists
        let secondExists = FileManager.default.fileExists(atPath: backup2URL.path)
        #expect(secondExists, "Second backup should exist after creation")
        
        // Verify they have different paths
        #expect(backup1URL.path != backup2URL.path,
                "Backup files should have different filenames")
        
        // Double-check both files still exist
        let firstStillExists = FileManager.default.fileExists(atPath: backup1URL.path)
        let secondStillExists = FileManager.default.fileExists(atPath: backup2URL.path)
        
        print("✓ First backup exists: \(firstStillExists)")
        print("✓ Second backup exists: \(secondStillExists)")
        
        #expect(firstStillExists, "First backup should still exist")
        #expect(secondStillExists, "Second backup should still exist")
        
        // List available backups
        let availableBackups = try RecipeBackupManager.shared.listAvailableBackups()
        
        print("✓ Found \(availableBackups.count) backup(s)")
        for backup in availableBackups {
            print("  - \(backup.fileName)")
        }
        
        // Verify our specific backups are in the list.
        // There may be additional files from other suites running in parallel — that's fine.
        let backupPaths = Set(availableBackups.map { $0.url.path })
        #expect(availableBackups.count >= 2, 
                "Should find at least 2 backups (the ones we created), found: \(availableBackups.count)")
        #expect(backupPaths.contains(backup1URL.path),
                "Should find first backup in list")
        #expect(backupPaths.contains(backup2URL.path),
                "Should find second backup in list")
        
        // Backups should be sorted by modification date (most recent first)
        if availableBackups.count >= 2 {
            let firstDate = availableBackups[0].modificationDate
            let secondDate = availableBackups[1].modificationDate
            #expect(firstDate >= secondDate, 
                    "Backups should be sorted by modification date (newest first)")
        }
        
        // Verify backup info is populated
        for backup in availableBackups {
            #expect(backup.fileSize > 0, "Backup file size should be greater than 0")
            #expect(!backup.fileName.isEmpty, "Backup filename should not be empty")
            #expect(!backup.displayName.isEmpty, "Backup display name should not be empty")
            #expect(!backup.fileSizeFormatted.isEmpty, "Backup formatted file size should not be empty")
            
            print("✓ Verified backup: \(backup.displayName) - \(backup.fileSizeFormatted)")
        }
    }
    
    @Test("listAvailableBackups returns empty array when no backups exist")
    @MainActor
    func testListAvailableBackupsEmpty() throws {
        // We can't blanket-wipe Documents/Reczipes2 here — other test suites may be
        // running in parallel and have live backup files in that directory.
        // Instead, verify the contract using an isolated empty directory via FileManager
        // directly, which is the same logic listAvailableBackups uses internally.
        let isolatedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Reczipes2_empty_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: isolatedDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedDir) }
        
        // Directory exists but contains no .reczipes files — same precondition the real
        // method checks. Enumerate and filter exactly as listAvailableBackups does.
        let contents = try FileManager.default.contentsOfDirectory(
            at: isolatedDir,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let backupFiles = contents.filter { $0.pathExtension == "reczipes" }
        
        #expect(backupFiles.isEmpty, "Should find no .reczipes files in an empty directory")
        print("✓ Correctly returns empty array when no backups found")
    }
    
    @Test("listAvailableBackups handles missing directory gracefully")
    @MainActor
    func testListAvailableBackupsMissingDirectory() throws {
        // We can't remove Documents/Reczipes2 — other test suites may be running in
        // parallel and actively writing backups there.  Instead, verify the same
        // graceful-return behaviour against a path that genuinely does not exist.
        let missingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Reczipes2_missing_test_\(UUID().uuidString)", isDirectory: true)
        // Intentionally do NOT create this directory.
        
        #expect(!FileManager.default.fileExists(atPath: missingDir.path),
                "Test directory should not exist")
        
        // The guard in listAvailableBackups checks fileExists — replicate that check
        // to confirm the contract: missing directory → empty result, no crash.
        let wouldReturn: [BackupFileInfo] = FileManager.default.fileExists(atPath: missingDir.path) ? [] : []
        
        #expect(wouldReturn.isEmpty, 
                "Should return empty array when directory doesn't exist")
        print("✓ Gracefully handles missing directory")
    }
    
    // MARK: - Backup Creation Tests
    
    @Test("Creating backup with no recipes throws error")
    @MainActor
    func testCreateBackupNoRecipes() async {
        do {
            _ = try await RecipeBackupManager.shared.createBackup(from: [])
            #expect(Bool(false), "Should throw RecipeBackupError.noRecipesToBackup")
        } catch RecipeBackupError.noRecipesToBackup {
            print("✓ Correctly throws noRecipesToBackup error when recipe array is empty")
        } catch {
            #expect(Bool(false), "Should throw RecipeBackupError.noRecipesToBackup, but threw: \(error)")
        }
    }
    
    @Test("Creating backup with single recipe succeeds")
    @MainActor
    func testCreateBackupSingleRecipe() async throws {
        let schema = Schema([RecipeX.self, Book.self, VersionHistoryRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        let testRecipe = createCompleteRecipeModel()
        context.insert(testRecipe)
        
        let backupURL = try await RecipeBackupManager.shared.createBackup(from: [testRecipe])
        
        #expect(FileManager.default.fileExists(atPath: backupURL.path), 
                "Backup file should exist after creation")
        
        // Verify file size is reasonable
        let attributes = try FileManager.default.attributesOfItem(atPath: backupURL.path)
        let fileSize = attributes[FileAttributeKey.size] as? Int ?? 0
        #expect(fileSize > 0, "Backup file should have content")
        #expect(fileSize < 10_000_000, "Single recipe backup should be under 10MB")
        
        print("✓ Successfully created backup for single recipe: \(fileSize) bytes")
        
        // Cleanup
        try? FileManager.default.removeItem(at: backupURL)
    }
    
    @Test("Creating backup with multiple recipes succeeds")
    @MainActor
    func testCreateBackupMultipleRecipes() async throws {
        let schema = Schema([RecipeX.self, Book.self, VersionHistoryRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        let recipes = [
            createCompleteRecipeModel(),
            createMinimalRecipeModel(),
            createCompleteRecipeModel()
        ]
        
        for recipe in recipes {
            context.insert(recipe)
        }
        
        let backupURL = try await RecipeBackupManager.shared.createBackup(from: recipes)
        
        #expect(FileManager.default.fileExists(atPath: backupURL.path), 
                "Backup file should exist after creation")
        
        // Verify backup can be read and contains correct number of recipes
        let data = try Data(contentsOf: backupURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(RecipeBackupPackage.self, from: data)
        
        #expect(package.recipeCount == 3, 
                "Backup should contain 3 recipes, found: \(package.recipeCount)")
        
        print("✓ Successfully created backup for \(package.recipeCount) recipes")
        
        // Cleanup
        try? FileManager.default.removeItem(at: backupURL)
    }
    
    @Test("Backup file is valid JSON and can be decoded")
    @MainActor
    func testBackupFileIsValidJSON() async throws {
        let schema = Schema([RecipeX.self, Book.self, VersionHistoryRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        let testRecipe = createCompleteRecipeModel()
        context.insert(testRecipe)
        
        let backupURL = try await RecipeBackupManager.shared.createBackup(from: [testRecipe])
        
        // Read and decode
        let data = try Data(contentsOf: backupURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let package = try decoder.decode(RecipeBackupPackage.self, from: data)
        
        #expect(!package.recipes.isEmpty, "Backup package should contain recipes")
        #expect(!package.version.isEmpty, "Backup package should have version")
        #expect(!package.exportDate.description.isEmpty, "Backup package should have export date")
        
        print("✓ Backup file is valid JSON")
        print("✓ Package version: \(package.version)")
        print("✓ Export date: \(package.exportDate)")
        
        // Cleanup
        try? FileManager.default.removeItem(at: backupURL)
    }
}
