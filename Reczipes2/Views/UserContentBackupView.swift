//
//  UserContentBackupView.swift
//  Reczipes2
//
//  Created by Xcode Assistant on 01/09/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Comprehensive backup and restore view for all user content (recipes and recipe books)
struct UserContentBackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // CloudKit-compatible models
    @Query private var recipes: [RecipeX]
    @Query private var books: [Book]
    @Query private var meals: [Meal]
    
    @State private var selectedTab: ContentType = .recipes
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showExportSuccess = false
    @State private var showImportSuccess = false
    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    @State private var importResult: String?
    @State private var exportResult: String?
    @State private var showImportPicker = false
    @State private var selectedImportMode: ImportOverwriteMode = .overwrite
    @State private var availableRecipeBackups: [BackupFileInfo] = []
    @State private var availableBookBackups: [URL] = []
    @State private var selectedBackup: BackupFileInfo?
    @State private var showShareSheet = false
    
    enum ContentType {
        case recipes
        case books
        case meals
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Content Type", selection: $selectedTab) {
                Text("Recipes (\(recipes.count))").tag(ContentType.recipes)
                Text("Books (\(books.count))").tag(ContentType.books)
                Text("Meals (\(meals.count))").tag(ContentType.meals)
            }
            .pickerStyle(.segmented)
            .padding()

            // Content
            Group {
                switch selectedTab {
                case .recipes:
                    recipeBackupView
                case .books:
                    booksBackupView
                case .meals:
                    MealImportView()
                }
            }
        }
        .navigationTitle("User Content Import/Export")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Done") {
                    AppStateManager.shared.currentTab = .recipes
                }
            }
        }
        .onAppear {
            loadAvailableBackups()
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: selectedTab == .recipes
                ? [.reczipesBackup]
                : [.bookBackup],
            allowsMultipleSelection: false
        ) { result in
            Task {
                if selectedTab == .recipes {
                    await handleRecipeImport(result: result)
                } else {
                    await handleBookImport(result: result)
                }
            }
        }
        .alert("Export Successful", isPresented: $showExportSuccess) {
            Button("Share") {
                showShareSheet = true
            }
            Button("Done", role: .cancel) { }
        } message: {
            Text(exportSuccessMessage)
        }
        .alert("Import Successful", isPresented: $showImportSuccess) {
            Button("OK") { }
        } message: {
            if let result = importResult {
                Text(result)
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
    }
    
    // MARK: - Recipe Backup View
    
    private var recipeBackupView: some View {
        List {
            // Current Status
            Section("Current Database") {
                HStack {
                    Image(systemName: "book.fill")
                        .foregroundColor(.blue)
                    Text("Total Recipes")
                    Spacer()
                    Text("\(recipes.count)")
                        .bold()
                }
                
                if recipes.count > 0 {
                    HStack {
                        Image(systemName: "photo.fill")
                            .foregroundColor(.orange)
                        Text("With Images")
                        Spacer()
                        Text("\(recipesWithImages)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Export Section
            Section {
                Button {
                    Task {
                        await exportRecipes()
                    }
                } label: {
                    if isExporting {
                        HStack {
                            ProgressView()
                            Text("Exporting...")
                        }
                    } else {
                        Label("Export Recipes", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(recipes.count == 0 || isExporting || isImporting)
            } header: {
                Text("Export")
            } footer: {
                Text("Creates a backup file containing \(recipes.count) RecipeX recipes with their images and CloudKit data.")
            }
            
            // Import Section
            Section {
                Picker("Import Mode", selection: $selectedImportMode) {
                    Text("Overwrite").tag(ImportOverwriteMode.overwrite)
                }
                .pickerStyle(.menu)
                
                // Show available backups
                if !availableRecipeBackups.isEmpty {
                    ForEach(availableRecipeBackups) { backup in
                        Button {
                            selectedBackup = backup
                            Task {
                                await importFromRecipeBackup(backup)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(backup.displayName)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    
                                    HStack {
                                        Text(backup.modificationDate, style: .date)
                                        Text("•")
                                        Text(backup.fileSizeFormatted)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if isImporting && selectedBackup?.id == backup.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "square.and.arrow.down")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .disabled(isImporting || isExporting)
                    }
                } else {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundColor(.secondary)
                        Text("No backups found")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Import from other location
                Button {
                    showImportPicker = true
                } label: {
                    Label("Import from Other Location", systemImage: "folder")
                }
                .disabled(isExporting || isImporting)
            } header: {
                HStack {
                    Text("Import")
                    Spacer()
                    Button {
                        loadAvailableBackups()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                importModeFooter
            }
        }
    }
    
    // MARK: - Books Backup View
    
    private var booksBackupView: some View {
        List {
            // Current Status
            Section("Current Library") {
                HStack {
                    Image(systemName: "books.vertical.fill")
                        .foregroundColor(.blue)
                    Text("Total Books")
                    Spacer()
                    Text("\(books.count)")
                        .bold()
                }
                
                if books.count > 0 {
                    HStack {
                        Image(systemName: "book.pages.fill")
                            .foregroundColor(.orange)
                        Text("Total Recipes in Books")
                        Spacer()
                        Text("\(totalRecipesInBooks)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Export All Section
            if books.count > 0 {
                Section {
                    Button {
                        Task {
                            await exportAllBooks()
                        }
                    } label: {
                        if isExporting {
                            HStack {
                                ProgressView()
                                Text("Exporting All Books...")
                            }
                        } else {
                            Label("Export All Books", systemImage: "square.and.arrow.up.on.square")
                        }
                    }
                    .disabled(isExporting || isImporting)
                } header: {
                    Text("Export All Books")
                } footer: {
                    Text("Creates a backup of \(books.count) Books with CloudKit sync data.")
                }
            }
            
            // Export Individual Section
            Section {
                if books.count == 0 {
                    Text("No books to export")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(books) { book in
                        Button {
                            Task {
                                await exportBook(book)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.name ?? "No Name")
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    
                                    Text("\(book.recipeIDs?.count ?? 0) recipes")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if isExporting {
                                    ProgressView()
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .disabled(isExporting || isImporting)
                    }
                }
            } header: {
                Text("Export Individual Books")
            } footer: {
                Text("Export a single book to share with others or backup separately.")
            }
            
            // Import Section
            Section {
                Button {
                    showImportPicker = true
                } label: {
                    Label("Import Book", systemImage: "square.and.arrow.down")
                }
                .disabled(isExporting || isImporting)
                
                if isImporting {
                    HStack {
                        ProgressView()
                        Text("Importing book...")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Import")
            } footer: {
                Text("Import a .bookbackup file. The books and all their data will be added to your library.")
            }
            
            // Info Section
            Section("About Books") {
                InfoRow(
                    icon: "book.pages",
                    title: "Complete Collections",
                    description: "Each book contains its recipes and all associated data"
                )
                
                InfoRow(
                    icon: "square.and.arrow.up.on.square",
                    title: "Easy Sharing",
                    description: "Share entire recipe collections with friends and family"
                )
                
                InfoRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Smart Import",
                    description: "Books are merged intelligently to avoid duplicates"
                )
            }
        }
    }
    
    // MARK: - Helper Views
    
    private var importModeFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import recipes from a backup file (.reczipes).")
            
            Text("Import Modes:")
                .font(.caption)
                .bold()
            
            Text("• Keep Both: Imports all recipes, even duplicates")
                .font(.caption)
            Text("• Skip Existing: Only imports new recipes")
                .font(.caption)
            Text("• Overwrite: Replaces existing recipes with imported ones")
                .font(.caption)
        }
    }
    
    private struct InfoRow: View {
        let icon: String
        let title: String
        let description: String
        
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Recipes with images
    private var recipesWithImages: Int {
        recipes.filter { $0.imageData != nil || $0.additionalImagesData != nil }.count
    }
    
    /// Total recipes in all books
    private var totalRecipesInBooks: Int {
        books.reduce(into: 0) { accumulator, book in
            accumulator += (book.recipeIDs?.count ?? 0)
        }
    }
    
    private var exportSuccessMessage: String {
        // Use the export-specific result if available
        if let result = exportResult {
            return result
        }
        
        // Fall back to default messages
        switch selectedTab {
        case .recipes:
            return "Backup created with \(recipes.count) recipes. Share it to save somewhere safe."
        case .books:
            return "Book backup created successfully. You can now share it with others."
        case .meals:
            return "Meal import complete."
        }
    }
    
    // MARK: - Actions
    
    private func loadAvailableBackups() {
        // Load recipe backups
        do {
            availableRecipeBackups = try RecipeBackupManager.shared.listAvailableBackups()
        } catch {
            AppLog.error("Failed to load available backups: \(error)", category: .backup)
            availableRecipeBackups = []
        }
        
        // Load book backups (from Reczipes2 folder) - look for .bookbackup files
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let reczipesDirectory = documentsDirectory.appendingPathComponent("Reczipes2", isDirectory: true)
        
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: reczipesDirectory,
            includingPropertiesForKeys: nil
        ) {
            availableBookBackups = contents.filter { $0.pathExtension == "bookbackup" }
        }
    }
    
    // MARK: - Recipe Export/Import
    
    private func exportRecipes() async {
        isExporting = true
        errorMessage = nil
        exportResult = nil
        
        do {
            guard recipes.count > 0 else {
                throw RecipeBackupError.noRecipesToBackup
            }
            
            let url = try await RecipeBackupManager.shared.createBackupX(from: recipes)
            exportResult = "Backup created with \(recipes.count) RecipeX recipes with CloudKit sync data"
            
            await MainActor.run {
                exportedURL = url
                showExportSuccess = true
            }
        } catch {
            await MainActor.run {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isExporting = false
        }
    }
    
    private func importFromRecipeBackup(_ backup: BackupFileInfo) async {
        isImporting = true
        errorMessage = nil
        
        do {
            let result = try await RecipeBackupManager.shared.importBackupX(
                from: backup.url,
                into: modelContext,
                existingRecipes: recipes,
                overwriteMode: selectedImportMode
            )
            
            importResult = "\(result.summary)\n\nTotal: \(result.totalRecipes) recipes\nImported as RecipeX models with CloudKit sync enabled"
            
            showImportSuccess = true
            loadAvailableBackups()
            
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
        
        isImporting = false
    }
    
    private func handleRecipeImport(result: Result<[URL], Error>) async {
        isImporting = true
        errorMessage = nil
        
        do {
            let urls = try result.get()
            guard let url = urls.first else {
                errorMessage = "No file selected"
                isImporting = false
                return
            }
            
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Cannot access file"
                isImporting = false
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            let importResult = try await RecipeBackupManager.shared.importBackupX(
                from: url,
                into: modelContext,
                existingRecipes: recipes,
                overwriteMode: selectedImportMode
            )
            
            self.importResult = "\(importResult.summary)\n\nTotal: \(importResult.totalRecipes) recipes\nImported as RecipeX models with CloudKit sync enabled"
            
            showImportSuccess = true
            
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
        
        isImporting = false
    }
    
    // MARK: - Book Export/Import
    
    private func exportAllBooks() async {
        isExporting = true
        errorMessage = nil
        exportResult = nil
        
        do {
            guard books.count > 0 else {
                throw RecipeBackupError.noRecipesToBackup
            }
            
            let url = try await BookBackupManager.shared.createBackup(from: books)
            let resultMessage = "Successfully exported \(books.count) Books with CloudKit sync data"
            
            await MainActor.run {
                exportedURL = url
                exportResult = resultMessage
                showExportSuccess = true
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Export all books failed: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isExporting = false
        }
    }
    
    private func exportBook(_ book: Book) async {
        isExporting = true
        errorMessage = nil
        exportResult = nil
        
        do {
            // Export single book as array
            let url = try await BookBackupManager.shared.createBackup(from: [book])
            
            await MainActor.run {
                exportedURL = url
                exportResult = "Book '\(book.name ?? "Untitled")' exported successfully with \(book.recipeIDs?.count ?? 0) recipes."
                showExportSuccess = true
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isExporting = false
        }
    }
    
    private func handleBookImport(result: Result<[URL], Error>) async {
        isImporting = true
        errorMessage = nil
        
        do {
            let urls = try result.get()
            guard let url = urls.first else {
                errorMessage = "No file selected"
                isImporting = false
                return
            }
            
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Cannot access file"
                isImporting = false
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            // Check file extension - support both legacy .bookbackup and current .reczipes
            let fileExtension = url.pathExtension.lowercased()
            
            if fileExtension == "bookbackup" || fileExtension == "reczipes" {
                // Book model import (supports both legacy .bookbackup and current .reczipes extensions)
                let importResult = try await BookBackupManager.shared.importBackup(
                    from: url,
                    into: modelContext,
                    existingBooks: books,
                    overwriteMode: selectedImportMode
                )
                
                self.importResult = "Successfully imported \(importResult.totalBooks) books.\n\(importResult.summary)"
                
            } else {
                errorMessage = "Unsupported file type: .\(fileExtension). Expected .bookbackup or .reczipes"
                isImporting = false
                return
            }
            
            showImportSuccess = true
            loadAvailableBackups()
            
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
        
        isImporting = false
    }
}

// MARK: - Share Sheet
//
//struct ShareSheet_UCBV: UIViewControllerRepresentable {
//    let items: [Any]
//    
//    func makeUIViewController(context: Context) -> UIActivityViewController {
//        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
//        return controller
//    }
//    
//    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
//        // No updates needed
//    }
//}

#Preview {
    NavigationView {
        UserContentBackupView()
            .modelContainer(for: [RecipeX.self, Book.self], inMemory: true)
    }
}
// MARK: - UTType Extensions

extension UTType {
    /// RecipeX backup format - uses .reczipes extension
    static var reczipesBackup: UTType {
        UTType(exportedAs: "com.headydiscy.reczipes.backup")
    }
    
    /// Book backup format - uses .bookbackup extension
    static var bookBackup: UTType {
        UTType(exportedAs: "com.headydiscy.reczipes.bookbackup")
    }
}

