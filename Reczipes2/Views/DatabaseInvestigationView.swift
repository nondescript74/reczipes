//
//  DatabaseInvestigationView.swift
//  Reczipes2
//
//  Created by Assistant on 1/15/26.
//  Deep investigation of database files to find missing recipes
//

import SwiftUI
import SwiftData
import SQLite3

struct DatabaseInvestigationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var investigationResults: InvestigationResults?
    @State private var isInvestigating = true
    @State private var selectedDatabase: DatabaseFileInfo?
    @State private var showDatabaseContent = false
    
    var body: some View {
        NavigationStack {
            Group {
                if isInvestigating {
                    investigatingView
                } else if let results = investigationResults {
                    resultsView(results: results)
                } else {
                    errorView
                }
            }
            .navigationTitle("Database Investigation")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDatabaseContent) {
                if let db = selectedDatabase {
                    DatabaseContentView(databaseInfo: db)
                }
            }
            .task {
                await investigate()
            }
        }
    }
    
    // MARK: - Views
    
    private var investigatingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Investigating Database Files...")
                .font(.headline)
            
            Text("Scanning all possible database locations")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    
    private func resultsView(results: InvestigationResults) -> some View {
        List {
            // Summary
            Section("Investigation Summary") {
                LabeledContent("Current Database") {
                    Text(results.currentDatabase.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                LabeledContent("Recipe Count") {
                    Text("\(results.currentDatabase.recipeCount)")
                        .fontWeight(results.currentDatabase.recipeCount == 0 ? .bold : .regular)
                        .foregroundStyle(results.currentDatabase.recipeCount == 0 ? .red : .primary)
                }
                
                LabeledContent("Total Databases Found") {
                    Text("\(results.allDatabases.count)")
                }
                
                if let largest = results.largestDatabase, largest.url != results.currentDatabase.url {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Possible Data Location Found!")
                                .fontWeight(.semibold)
                            Text(largest.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.appWarning)
                    }
                }
            }
            
            // All databases
            Section("All Database Files") {
                ForEach(results.allDatabases) { dbInfo in
                    Button {
                        selectedDatabase = dbInfo
                        showDatabaseContent = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(dbInfo.name)
                                        .font(.headline)
                                    
                                    Text(dbInfo.path)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if dbInfo.url == results.currentDatabase.url {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.appSuccess)
                                }
                            }
                            
                            HStack(spacing: 16) {
                                Label("\(dbInfo.recipeCount) recipes", systemImage: "book.fill")
                                    .font(.caption)
                                    .foregroundStyle(dbInfo.recipeCount > 0 ? .primary : .secondary)
                                
                                Label(dbInfo.sizeFormatted, systemImage: "internaldrive")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                    Text(dbInfo.modificationDate, style: .relative)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            
                            if dbInfo.error != nil {
                                Label("Could not read database", systemImage: "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(Color.appCritical)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Raw file system scan
            Section("File System Details") {
                ForEach(results.rawFiles, id: \.path) { fileInfo in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fileInfo.name)
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Text(fileInfo.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Text("Size: \(fileInfo.size)")
                            Spacer()
                            Text("Modified: \(fileInfo.modified, style: .relative)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Export button
            Section {
                Button {
                    exportInvestigationReport(results: results)
                } label: {
                    Label("Export Investigation Report", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
    
    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(Color.appCritical)
            
            Text("Investigation Failed")
                .font(.title)
            
            Text("Unable to scan database files")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func investigate() async {
        isInvestigating = true
        
        do {
            let results = try await DatabaseInvestigationService.investigateAllDatabases()
            investigationResults = results
        } catch {
            print("Investigation error: \(error)")
        }
        
        isInvestigating = false
    }
    
    private func exportInvestigationReport(results: InvestigationResults) {
        let report = results.generateReport()
        
        // Share the report
        #if os(iOS)
        let activityVC = UIActivityViewController(
            activityItems: [report],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #elseif os(macOS)
        // macOS fallback: copy the report to the clipboard.
        PlatformPasteboard.copy(report)
        #endif
    }
}

// MARK: - Database Content Detail View

struct DatabaseContentView: View {
    let databaseInfo: DatabaseFileInfo
    @Environment(\.dismiss) private var dismiss
    @State private var recipes: [RecipeInfo] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading recipes...")
                } else if recipes.isEmpty {
                    ContentUnavailableView(
                        "No Recipes",
                        systemImage: "book.closed",
                        description: Text("This database contains no recipes")
                    )
                } else {
                    List(recipes) { recipe in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.title)
                                .font(.headline)
                            
                            if let date = recipe.dateAdded {
                                Text("Added: \(date, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            HStack {
                                if recipe.hasImage {
                                    Label("Has Image", systemImage: "photo")
                                        .font(.caption)
                                        .foregroundStyle(Color.appInfo)
                                }
                                
                                if recipe.hasIngredients {
                                    Label("Has Ingredients", systemImage: "list.bullet")
                                        .font(.caption)
                                        .foregroundStyle(Color.appSuccess)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(databaseInfo.name)
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadRecipes()
            }
        }
    }
    
    private func loadRecipes() async {
        isLoading = true
        
        do {
            recipes = try await DatabaseInvestigationService.readRecipesFromDatabase(url: databaseInfo.url)
        } catch {
            print("Error loading recipes: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Investigation Service

@MainActor
class DatabaseInvestigationService {
    
    static func investigateAllDatabases() async throws -> InvestigationResults {
        print("🔍 Starting deep database investigation...")
        
        let fileManager = FileManager.default
        let appSupport = URL.applicationSupportDirectory
        
        // Get current database URL (what the app is using now)
        let currentDBURL = appSupport.appendingPathComponent("CloudKitModel.sqlite")
        
        // Scan for ALL .sqlite and .store files
        var allDatabaseFiles: [DatabaseFileInfo] = []
        
        // Known possible names
        let knownNames = [
            "CloudKitModel.sqlite",
            "default.store",
            "Model.sqlite",
            "Reczipes2.sqlite",
            "Reczipes.sqlite"
        ]
        
        for name in knownNames {
            let url = appSupport.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                let info = try await analyzeDatabase(url: url, isCurrent: url == currentDBURL)
                allDatabaseFiles.append(info)
            }
        }
        
        // Also scan directory for any other .sqlite or .store files
        // Collect URLs in a non-async way first
        let additionalFiles: [URL] = {
            var files: [URL] = []
            guard let enumerator = fileManager.enumerator(at: appSupport, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) else {
                return files
            }
            
            // Use allObjects to avoid async iteration issues
            let allItems = enumerator.allObjects
            for case let fileURL as URL in allItems {
                let pathExtension = fileURL.pathExtension
                if (pathExtension == "sqlite" || pathExtension == "store") &&
                   !allDatabaseFiles.contains(where: { $0.url == fileURL }) {
                    files.append(fileURL)
                }
            }
            return files
        }()
        
        // Now process the files asynchronously
        for fileURL in additionalFiles {
            let info = try await analyzeDatabase(url: fileURL, isCurrent: fileURL == currentDBURL)
            allDatabaseFiles.append(info)
        }
        
        // Get raw file info
        let rawFiles = getRawFileInfo(in: appSupport)
        
        // Find current database
        guard let currentDB = allDatabaseFiles.first(where: { $0.url == currentDBURL }) else {
            throw InvestigationError.currentDatabaseNotFound
        }
        
        // Find largest database
        let largestDB = allDatabaseFiles.max(by: { $0.fileSize < $1.fileSize })
        
        print("✅ Investigation complete:")
        print("   Current database: \(currentDB.name) (\(currentDB.recipeCount) recipes)")
        print("   Total databases found: \(allDatabaseFiles.count)")
        if let largest = largestDB {
            print("   Largest database: \(largest.name) (\(largest.recipeCount) recipes, \(largest.sizeFormatted))")
        }
        
        return InvestigationResults(
            currentDatabase: currentDB,
            allDatabases: allDatabaseFiles,
            largestDatabase: largestDB,
            rawFiles: rawFiles
        )
    }
    
    private static func analyzeDatabase(url: URL, isCurrent: Bool) async throws -> DatabaseFileInfo {
        print("   Analyzing: \(url.lastPathComponent)...")
        
        let fileManager = FileManager.default
        
        // Get file attributes
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        let modDate = attributes[.modificationDate] as? Date ?? Date.distantPast
        
        // Try to read recipe count
        var recipeCount = 0
        var error: Error?
        
        do {
            recipeCount = try await readRecipeCount(from: url)
        } catch let readError {
            error = readError
            print("      ⚠️ Could not read recipes: \(readError.localizedDescription)")
        }
        
        print("      Size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
        print("      Recipes: \(recipeCount)")
        
        return DatabaseFileInfo(
            url: url,
            name: url.lastPathComponent,
            path: url.path,
            fileSize: fileSize,
            modificationDate: modDate,
            recipeCount: recipeCount,
            isCurrent: isCurrent,
            error: error
        )
    }
    
    private static func readRecipeCount(from url: URL) async throws -> Int {
        // Use SQLite directly to avoid migration issues
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Import SQLite3
                    var db: OpaquePointer?
                    
                    // Open database in read-only mode
                    let result = sqlite3_open_v2(
                        url.path,
                        &db,
                        SQLITE_OPEN_READONLY,
                        nil
                    )
                    
                    guard result == SQLITE_OK, let db = db else {
                        throw InvestigationError.cannotOpenDatabase(url.lastPathComponent)
                    }
                    
                    defer {
                        sqlite3_close(db)
                    }
                    
                    // Try different table names that Recipe might use
                    let possibleTableNames = ["ZRECIPE", "Recipe", "Z_Recipe"]
                    var count = 0
                    
                    for tableName in possibleTableNames {
                        var statement: OpaquePointer?
                        let query = "SELECT COUNT(*) FROM \(tableName)"
                        
                        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                            defer { sqlite3_finalize(statement) }
                            
                            if sqlite3_step(statement) == SQLITE_ROW {
                                count = Int(sqlite3_column_int(statement, 0))
                                print("      ✅ Found \(count) recipes in table \(tableName)")
                                break
                            }
                        }
                    }
                    
                    continuation.resume(returning: count)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    static func readRecipesFromDatabase(url: URL) async throws -> [RecipeInfo] {
        // Create a simple configuration for reading the database
        let config = ModelConfiguration(url: url, allowsSave: false)
        
        let container = try ModelContainer(
            for: RecipeX.self,
            RecipeImageAssignment.self,
            UserAllergenProfile.self,
            CachedDiabeticAnalysis.self,
            SavedLink.self,
            Book.self,
            CookingSession.self,
            SharedRecipe.self,
            SharedRecipeBook.self,
            SharingPreferences.self,
            CachedSharedRecipe.self,
            CloudKitRecipePreview.self,
            VersionHistoryRecord.self,
            migrationPlan: Reczipes2MigrationPlan.self,
            configurations: config
        )
        
        let context = container.mainContext
        let descriptor = FetchDescriptor<RecipeX>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        let recipes = try context.fetch(descriptor)
        
        return recipes.compactMap { recipe in
            guard let id = recipe.id else { return nil }
            
            return RecipeInfo(
                id: id,
                title: recipe.title ?? "Untitled Recipe",
                dateAdded: recipe.dateAdded,
                hasImage: recipe.imageData != nil || recipe.imageName != nil,
                hasIngredients: recipe.ingredientSectionsData != nil
            )
        }
    }
    
    private static func getRawFileInfo(in directory: URL) -> [RawFileInfo] {
        var files: [RawFileInfo] = []
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) else {
            return files
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                
                if resourceValues.isRegularFile == true {
                    let size = resourceValues.fileSize ?? 0
                    let modified = resourceValues.contentModificationDate ?? Date.distantPast
                    
                    files.append(RawFileInfo(
                        name: fileURL.lastPathComponent,
                        path: fileURL.path,
                        size: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file),
                        modified: modified
                    ))
                }
            } catch {
                print("Error reading file info: \(error)")
            }
        }
        
        return files.sorted { $0.name < $1.name }
    }
}

// MARK: - Supporting Types

struct InvestigationResults {
    let currentDatabase: DatabaseFileInfo
    let allDatabases: [DatabaseFileInfo]
    let largestDatabase: DatabaseFileInfo?
    let rawFiles: [RawFileInfo]
    
    func generateReport() -> String {
        var report = """
        DATABASE INVESTIGATION REPORT
        Generated: \(Date())
        
        === SUMMARY ===
        Current Database: \(currentDatabase.name)
        Current Recipe Count: \(currentDatabase.recipeCount)
        Total Databases Found: \(allDatabases.count)
        
        """
        
        if let largest = largestDatabase, largest.url != currentDatabase.url {
            report += """
            
            ⚠️ ISSUE DETECTED
            The largest database (\(largest.name)) is not the current database!
            Largest contains \(largest.recipeCount) recipes vs current \(currentDatabase.recipeCount)
            
            """
        }
        
        report += "\n=== ALL DATABASES ===\n"
        for db in allDatabases {
            report += """
            
            File: \(db.name)
            Path: \(db.path)
            Size: \(db.sizeFormatted)
            Recipes: \(db.recipeCount)
            Modified: \(db.modificationDate)
            Is Current: \(db.isCurrent ? "YES" : "NO")
            
            """
        }
        
        return report
    }
}

struct DatabaseFileInfo: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let path: String
    let fileSize: Int64
    let modificationDate: Date
    let recipeCount: Int
    let isCurrent: Bool
    let error: Error?
    
    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    // Hashable conformance
    static func == (lhs: DatabaseFileInfo, rhs: DatabaseFileInfo) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct RecipeInfo: Identifiable {
    let id: UUID
    let title: String
    let dateAdded: Date?
    let hasImage: Bool
    let hasIngredients: Bool
}

struct RawFileInfo {
    let name: String
    let path: String
    let size: String
    let modified: Date
}

enum InvestigationError: LocalizedError {
    case currentDatabaseNotFound
    case cannotOpenDatabase(String)
    
    var errorDescription: String? {
        switch self {
        case .currentDatabaseNotFound:
            return "Current database file not found"
        case .cannotOpenDatabase(let name):
            return "Cannot open database: \(name)"
        }
    }
}

#Preview {
    DatabaseInvestigationView()
}
