//
//  RecipeDataDiagnosticView.swift
//  Reczipes2
//
//  Created to diagnose and fix recipes with missing data
//

import SwiftUI
import SwiftData

/// Diagnostic view to check and repair recipes with missing data
struct RecipeDataDiagnosticView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query private var allRecipes: [RecipeX]
    
    @State private var recipesWithMissingData: [RecipeX] = []
    @State private var isScanning = false
    @State private var isRepairing = false
    @State private var scanResults: String = ""
    @State private var repairResults: String = ""
    @State private var exportResult: String = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recipe Data Diagnostic Tool")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("This tool scans all recipes to find any with missing ingredients, instructions, or notes data.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Scan Results") {
                    if isScanning {
                        HStack {
                            ProgressView()
                            Text("Scanning recipes...")
                                .foregroundStyle(.secondary)
                        }
                    } else if scanResults.isEmpty {
                        Text("No scan performed yet")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        Text(scanResults)
                            .font(.subheadline)
                    }
                    
                    Button {
                        Task {
                            await scanRecipes()
                        }
                    } label: {
                        Label("Scan All Recipes", systemImage: "magnifyingglass")
                    }
                    .disabled(isScanning || isRepairing)
                }
                
                if !recipesWithMissingData.isEmpty {
                    Section("Found Issues") {
                        ForEach(recipesWithMissingData) { recipe in
                            NavigationLink {
                                RecipeDataInspectorView(recipe: recipe)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recipe.title ?? "Untitled")
                                        .font(.headline)
                                    
                                    Text(diagnosticInfo(for: recipe))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    
                    Section("Export for Analysis") {
                Button {
                    Task {
                        await exportSingleRecipeForDebugging()
                    }
                } label: {
                    Label("Export Problem Recipe for Analysis", systemImage: "square.and.arrow.up.on.square")
                }
                .disabled(recipesWithMissingData.isEmpty)
                
                if !exportResult.isEmpty {
                    Text(exportResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Repair Options") {
                        if isRepairing {
                            HStack {
                                ProgressView()
                                Text("Attempting repairs...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if !repairResults.isEmpty {
                            Text(repairResults)
                                .font(.subheadline)
                        }
                        
                        Button(role: .destructive) {
                            Task {
                                await attemptRepair()
                            }
                        } label: {
                            Label("Attempt Auto-Repair", systemImage: "wrench.and.screwdriver.fill")
                        }
                        .disabled(isScanning || isRepairing)
                        
                        Text("⚠️ This will try to migrate any file-based images to the database. Make sure you have a backup!")
                            .font(.caption)
                            .foregroundStyle(Color.appWarning)
                    }
                }
            }
            .navigationTitle("Recipe Diagnostics")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Scanning
    
    @MainActor
    private func scanRecipes() async {
        isScanning = true
        recipesWithMissingData.removeAll()
        
        var issueCount = 0
        var missingIngredients = 0
        var missingInstructions = 0
       // var missingNotes = 0
        var emptyTitles = 0
        
        for recipe in allRecipes {
            var hasIssue = false
            
            // Check for missing or empty data
            if recipe.ingredientSectionsData == nil || recipe.ingredientSections.isEmpty {
                missingIngredients += 1
                hasIssue = true
            }
            
            if recipe.instructionSectionsData == nil || recipe.instructionSections.isEmpty {
                missingInstructions += 1
                hasIssue = true
            }
            
            if recipe.title == nil || recipe.title?.isEmpty == true {
                emptyTitles += 1
                hasIssue = true
            }
            
            if hasIssue {
                recipesWithMissingData.append(recipe)
                issueCount += 1
            }
        }
        
        // Build scan results message
        var resultsMessage = "Scanned \(allRecipes.count) recipes.\n\n"
        
        if issueCount == 0 {
            resultsMessage += "✅ All recipes look good!"
        } else {
            resultsMessage += "Found \(issueCount) recipe\(issueCount == 1 ? "" : "s") with issues:\n"
            if missingIngredients > 0 {
                resultsMessage += "• \(missingIngredients) missing ingredients\n"
            }
            if missingInstructions > 0 {
                resultsMessage += "• \(missingInstructions) missing instructions\n"
            }
            if emptyTitles > 0 {
                resultsMessage += "• \(emptyTitles) empty titles\n"
            }
        }
        
        scanResults = resultsMessage
        isScanning = false
    }
    
    // MARK: - Repair
    
    @MainActor
    private func attemptRepair() async {
        isRepairing = true
        var repairedCount = 0
        var failedCount = 0
        
        for recipe in recipesWithMissingData {
            do {
                // Try to migrate images if they're missing
                let didMigrate = recipe.migrateImagesToSwiftData()
                
                // If title is empty, try to use filename or set a placeholder
                if recipe.title == nil || recipe.title?.isEmpty == true {
                    if let filename = recipe.originalFileName, !filename.isEmpty {
                        recipe.title = filename
                            .replacingOccurrences(of: "_", with: " ")
                            .replacingOccurrences(of: ".pdf", with: "")
                            .replacingOccurrences(of: ".jpg", with: "")
                            .replacingOccurrences(of: ".png", with: "")
                    } else {
                        recipe.title = "Untitled Recipe \(recipe.safeID.uuidString.prefix(8))"
                    }
                }
                
                // If we made any changes or migrations, save
                if didMigrate {
                    try modelContext.save()
                    repairedCount += 1
                } else if recipe.ingredientSectionsData == nil || recipe.instructionSectionsData == nil {
                    // Can't repair missing recipe content - this is data loss
                    failedCount += 1
                }
            } catch {
                print("❌ Failed to repair recipe \(recipe.title ?? "unknown"): \(error)")
                failedCount += 1
            }
        }
        
        // Build repair results message
        var resultsMessage = ""
        if repairedCount > 0 {
            resultsMessage += "✅ Successfully repaired \(repairedCount) recipe\(repairedCount == 1 ? "" : "s").\n\n"
        }
        if failedCount > 0 {
            resultsMessage += "⚠️ \(failedCount) recipe\(failedCount == 1 ? "" : "s") could not be fully repaired (missing core data).\n\n"
            resultsMessage += "These recipes may need to be manually edited or re-imported."
        }
        
        repairResults = resultsMessage
        isRepairing = false
        
        // Re-scan after repair
        await scanRecipes()
    }
    
    // MARK: - Helpers
    
    private func diagnosticInfo(for recipe: RecipeX) -> String {
        var issues: [String] = []
        
        if recipe.title == nil || recipe.title?.isEmpty == true {
            issues.append("Empty title")
        }
        
        if recipe.ingredientSectionsData == nil {
            issues.append("No ingredient data")
        } else if recipe.ingredientSections.isEmpty {
            issues.append("Empty ingredients")
        } else {
            let count = recipe.ingredientSections.flatMap { $0.ingredients }.count
            issues.append("✓ \(count) ingredients")
        }
        
        if recipe.instructionSectionsData == nil {
            issues.append("No instruction data")
        } else if recipe.instructionSections.isEmpty {
            issues.append("Empty instructions")
        } else {
            let count = recipe.instructionSections.flatMap { $0.steps }.count
            issues.append("✓ \(count) steps")
        }
        
        if recipe.notesData == nil {
            // Notes are optional, don't report as issue
        } else if !recipe.notes.isEmpty {
            issues.append("✓ \(recipe.notes.count) notes")
        }
        
        return issues.joined(separator: " • ")
    }
    
    // MARK: - Export for Debugging
    
    @MainActor
    private func exportSingleRecipeForDebugging() async {
        guard let recipe = recipesWithMissingData.first else {
            exportResult = "No problem recipes to export"
            return
        }
        
        do {
            // Create a backup with just this one recipe
            let url = try await RecipeBackupManager.shared.createBackupX(from: [recipe])
            
            // Read the JSON back
            let jsonData = try Data(contentsOf: url)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                // Check if ingredientSectionsData is in the JSON
                let hasRecipeField = jsonString.contains("\"recipe\"")
                let hasIngredients = jsonString.contains("ingredientSectionsData")
                let hasInstructions = jsonString.contains("instructionSectionsData")
                let hasNotes = jsonString.contains("notesData")
                
                // Find the position of "recipe" field
                var recipeSnippet = "Not found"
                if let range = jsonString.range(of: "\"recipe\"") {
                    let start = jsonString.index(range.lowerBound, offsetBy: -50, limitedBy: jsonString.startIndex) ?? jsonString.startIndex
                    let end = jsonString.index(range.upperBound, offsetBy: 500, limitedBy: jsonString.endIndex) ?? jsonString.endIndex
                    recipeSnippet = String(jsonString[start..<end])
                }
                
                exportResult = """
                ✅ SUCCESS! Export working correctly!
                
                Exported '\(recipe.title ?? "Untitled")' to:
                \(url.lastPathComponent)
                
                JSON structure:
                - "recipe" field: \(hasRecipeField ? "✓ FOUND" : "✗ MISSING")
                - ingredientSectionsData: \(hasIngredients ? "✓" : "✗")
                - instructionSectionsData: \(hasInstructions ? "✓" : "✗")
                - notesData: \(hasNotes ? "✓" : "✗")
                
                File size: \(jsonData.count / 1024) KB
                
                Recipe field preview:
                \(recipeSnippet)
                """
                
                // Also log to console for deeper analysis
                print("=== FULL JSON (first 5000 chars) ===")
                print(jsonString.prefix(5000))
                print("=== END ===")
            }
        } catch {
            exportResult = "Export failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    RecipeDataDiagnosticView()
        .modelContainer(for: [RecipeX.self], inMemory: true)
}

// MARK: - Recipe Data Inspector

/// Detailed view showing raw data for a recipe
struct RecipeDataInspectorView: View {
    let recipe: RecipeX
    
    var body: some View {
        List {
            Section("Basic Info") {
                DataRow(label: "ID", value: recipe.id?.uuidString ?? "nil")
                DataRow(label: "Title", value: recipe.title ?? "nil")
                DataRow(label: "Yield", value: recipe.recipeYield ?? "nil")
            }
            
            Section("Ingredients") {
                DataRow(label: "Data", value: recipe.ingredientSectionsData != nil ? "\(recipe.ingredientSectionsData!.count) bytes" : "nil")
                
                if let data = recipe.ingredientSectionsData {
                    DataRow(label: "Sections", value: "\(recipe.ingredientSections.count)")
                    
                    ForEach(recipe.ingredientSections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            if let title = section.title {
                                Text(title)
                                    .font(.subheadline)
                                    .bold()
                            }
                            Text("\(section.ingredients.count) ingredients")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            ForEach(section.ingredients) { ingredient in
                                Text("• \(ingredient.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    DisclosureGroup("Raw JSON") {
                        if let jsonString = String(data: data, encoding: .utf8) {
                            Text(jsonString)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            
            Section("Instructions") {
                DataRow(label: "Data", value: recipe.instructionSectionsData != nil ? "\(recipe.instructionSectionsData!.count) bytes" : "nil")
                
                if let data = recipe.instructionSectionsData {
                    DataRow(label: "Sections", value: "\(recipe.instructionSections.count)")
                    
                    ForEach(recipe.instructionSections) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            if let title = section.title {
                                Text(title)
                                    .font(.subheadline)
                                    .bold()
                            }
                            Text("\(section.steps.count) steps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            ForEach(section.steps) { step in
                                Text("\(step.stepNumber). \(step.text)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    DisclosureGroup("Raw JSON") {
                        if let jsonString = String(data: data, encoding: .utf8) {
                            Text(jsonString)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            
            Section("Notes") {
                DataRow(label: "Data", value: recipe.notesData != nil ? "\(recipe.notesData!.count) bytes" : "nil")
                
                if let data = recipe.notesData {
                    DataRow(label: "Count", value: "\(recipe.notes.count)")
                    
                    ForEach(recipe.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.type.rawValue.capitalized)
                                .font(.subheadline)
                                .bold()
                            Text(note.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    DisclosureGroup("Raw JSON") {
                        if let jsonString = String(data: data, encoding: .utf8) {
                            Text(jsonString)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            
            Section("Images") {
                DataRow(label: "Main Image Data", value: recipe.imageData != nil ? "\(recipe.imageData!.count / 1024) KB" : "nil")
                DataRow(label: "Main Image Name", value: recipe.imageName ?? "nil")
                DataRow(label: "Additional Images", value: recipe.additionalImagesData != nil ? "\(recipe.additionalImagesData!.count / 1024) KB" : "nil")
            }
            
            Section("Metadata") {
                DataRow(label: "Date Added", value: recipe.dateAdded?.formatted() ?? "nil")
                DataRow(label: "Date Created", value: recipe.dateCreated?.formatted() ?? "nil")
                DataRow(label: "Last Modified", value: recipe.lastModified?.formatted() ?? "nil")
                DataRow(label: "Version", value: recipe.version?.description ?? "nil")
                DataRow(label: "Extraction Source", value: recipe.extractionSource ?? "nil")
            }
        }
        .navigationTitle("Recipe Data Inspector")
        .platformNavigationBarTitleDisplayMode(.inline)
    }
}

struct DataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }
}

