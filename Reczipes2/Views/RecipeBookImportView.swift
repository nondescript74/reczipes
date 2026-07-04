//
//  RecipeBookImportView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/28/25.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// View for importing recipe books from files
struct RecipeBookImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var isImporting = false
    @State private var showFileImporter = false
    @State private var showPreview = false
    @State private var previewPackage: RecipeBookImportService.BookExportPackage?
    @State private var importURL: URL?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var importMode: RecipeBookImportService.BookImportMode = .replace
    @State private var existingBook: Book?
    @State private var showSuccessAlert = false
    @State private var importResult: RecipeBookImportService.BookImportResult?
    @State private var isMultiBookImport = false
    @State private var multiBookCount = 0
    @State private var multiBookSummary: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let package = previewPackage {
                    previewContent(package)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Import Recipe Book")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                if previewPackage != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") {
                            Task {
                                await performImport()
                            }
                        }
                        .disabled(isImporting)
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "recipebook") ?? .data,
                    .zip  // Also allow .zip files for manual imports
                ],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .alert(alertTitle, isPresented: $showSuccessAlert) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                showFileImporter = true
            }
        }
    }
    
    // MARK: - Views
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "book.closed.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)
            
            // Title and description
            VStack(spacing: 8) {
                Text("Import Recipe Book")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Import a recipe book from a .recipebook file shared from another device")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Import button
            Button {
                showFileImporter = true
            } label: {
                Label("Choose File", systemImage: "folder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            
            // Info section
            VStack(alignment: .leading, spacing: 12) {
                InfoRow_RBIV(
                    icon: "book.pages",
                    title: "Complete Books",
                    description: "Import entire recipe collections with all recipes"
                )
                
                InfoRow_RBIV(
                    icon: "photo.on.rectangle",
                    title: "Images Included",
                    description: "All recipe photos and book covers are preserved"
                )
                
                InfoRow_RBIV(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Smart Merging",
                    description: "Choose to replace, merge, or keep both books"
                )
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.top, 40)
    }
    
    @ViewBuilder
    private func previewContent(_ package: RecipeBookImportService.BookExportPackage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Book info
                VStack(alignment: .leading, spacing: 12) {
                    Text("Book Information")
                        .font(.headline)
                    
                    InfoRow(label: "Name", value: package.book.name)
                    
                    if let description = package.book.bookDescription {
                        InfoRow(label: "Description", value: description)
                    }
                    
                    InfoRow(label: "Recipes", value: "\(package.recipes.count)")
                    InfoRow(label: "Images", value: "\(package.imageManifest.count)")
                    InfoRow(label: "Packaged", value: package.summary)
                }
                .padding()
                .background(Color.appGray6)
                .cornerRadius(12)
                
                // Conflict resolution
                if existingBook != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("A book with this name already exists", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(Color.appWarning)
                        
                        Text("Choose how to handle this:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Picker("Import Mode", selection: $importMode) {
                            Text("Keep Both").tag(RecipeBookImportService.BookImportMode.keepBoth)
                            Text("Replace Existing").tag(RecipeBookImportService.BookImportMode.replace)
                            Text("Merge Recipes").tag(RecipeBookImportService.BookImportMode.merge)
                        }
                        .pickerStyle(.segmented)
                        
                        Text(importModeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(.systemOrange).opacity(0.1))
                    .cornerRadius(12)
                }
                
                // Recipe list
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recipes to Import")
                        .font(.headline)
                    
                    ForEach(package.recipes, id: \.id) { recipe in
                        HStack {
                            Image(systemName: recipe.imageName != nil ? "photo" : "doc.text")
                                .foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading) {
                                Text(recipe.title)
                                    .font(.body)
                                
                                if let headerNotes = recipe.headerNotes {
                                    Text(headerNotes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        
                        if recipe.id != package.recipes.last?.id {
                            Divider()
                        }
                    }
                }
                .padding()
                .background(Color.appGray6)
                .cornerRadius(12)
            }
            .padding()
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("Importing Recipe Book...")
                            .font(.headline)
                            .foregroundStyle(Color.onTint)
                        
                        Text("This may take a moment...")
                            .font(.caption)
                            .foregroundStyle(Color.onTint.opacity(0.8))
                    }
                    .padding(32)
                    .background(.regularMaterial)
                    .cornerRadius(16)
                }
            }
        }
    }
    
    // MARK: - Helper Views
    
    private struct InfoRow: View {
        let label: String
        let value: String
        
        var body: some View {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .fontWeight(.medium)
            }
            .font(.subheadline)
        }
    }
    
    // MARK: - Computed Properties
    
    private var importModeDescription: String {
        switch importMode {
        case .keepBoth:
            return "Creates a new book with '(Imported)' appended to the name"
        case .replace:
            return "Deletes the existing book and replaces it with the imported version"
        case .merge:
            return "Adds recipes from the import to the existing book"
        }
    }
    
    private var alertTitle: String {
        if isMultiBookImport {
            // Parse success count from summary
            if let summary = multiBookSummary,
               let successCount = extractSuccessCount(from: summary),
               successCount > 0 {
                return successCount == multiBookCount ? "Import Successful" : "Import Partially Successful"
            } else {
                return "Import Failed"
            }
        } else {
            return importResult != nil ? "Import Successful" : "Import Failed"
        }
    }
    
    private var alertMessage: String {
        if isMultiBookImport {
            return multiBookSummary ?? "No books were imported"
        } else if let result = importResult {
            return "Imported '\(result.book.name ?? "Untitled")'\n\(result.recipesImported) recipes, \(result.imagesImported) images"
        } else {
            return "No books were imported"
        }
    }
    
    private func extractSuccessCount(from summary: String) -> Int? {
        // Extract number from "Imported X of Y books"
        let components = summary.components(separatedBy: " ")
        if let index = components.firstIndex(of: "Imported"),
           index + 1 < components.count,
           let count = Int(components[index + 1]) {
            return count
        }
        return nil
    }
    
    // MARK: - Actions
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Unable to access the selected file"
                showError = true
                return
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            // Copy to temp location since we need to access it later
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).recipebook")
            
            do {
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                try FileManager.default.copyItem(at: url, to: tempURL)
                importURL = tempURL
                
                // Preview the file
                Task {
                    await loadPreview(from: tempURL)
                }
            } catch {
                errorMessage = "Failed to load file: \(error.localizedDescription)"
                showError = true
            }
            
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func loadPreview(from url: URL) async {
        do {
            // First, detect what type of import this is
            let importType = try RecipeBookExportService.detectImportType(from: url)
            
            switch importType {
            case .singleBook:
                // Normal single book import
                let package = try await RecipeBookImportService.shared.previewBook(from: url)
                previewPackage = package
                isMultiBookImport = false
                
                // Check for existing book
                existingBook = try RecipeBookImportService.shared.checkForExistingBook(
                    bookID: package.book.id,
                    modelContext: modelContext
                )
                
            case .multipleBooks(let count):
                // Multi-book import - skip preview and go straight to import
                isMultiBookImport = true
                multiBookCount = count
                previewPackage = nil
                
                // Show confirmation and proceed
                await performMultiBookImport()
                
            case .unknown:
                throw NSError(domain: "RecipeBookImport", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Unable to determine the type of import file. Please make sure this is a valid recipe book export."
                ])
            }
            
        } catch {
            errorMessage = (error as? RecipeBookImportService.ImportError)?.errorDescription ?? error.localizedDescription
            showError = true
            dismiss()
        }
    }
    
    private func performImport() async {
        guard let url = importURL else { return }
        
        isImporting = true
        
        do {
            let result = try await RecipeBookImportService.shared.importBook(
                from: url,
                modelContext: modelContext,
                importMode: importMode
            )
            
            importResult = result
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: url)
            
            isImporting = false
            showSuccessAlert = true
            
            AppLog.info("Successfully imported book: \(result.book.name ?? "Untitled")", category: .batch)
            
        } catch {
            isImporting = false
            errorMessage = (error as? RecipeBookImportService.ImportError)?.errorDescription ?? error.localizedDescription
            showError = true
            AppLog.error("Import failed: \(error)", category: .batch)
        }
    }
    
    private func performMultiBookImport() async {
        guard let url = importURL else { return }
        
        isImporting = true
        
        do {
            let (books, summary) = try await RecipeBookExportService.importMultipleBooks(
                from: url,
                modelContext: modelContext,
                replaceExisting: importMode == .replace
            )
            
            multiBookSummary = summary
            multiBookCount = books.count
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: url)
            
            isImporting = false
            
            // Only show success alert if at least one book was imported
            if books.count > 0 {
                showSuccessAlert = true
                AppLog.info("Successfully imported \(books.count) books", category: .batch)
            } else {
                errorMessage = summary
                showError = true
                AppLog.error("No books were imported", category: .batch)
            }
            
        } catch {
            isImporting = false
            errorMessage = error.localizedDescription
            showError = true
            AppLog.error("Multi-book import failed: \(error)", category: .batch)
        }
    }
}

// MARK: - Info Row

private struct InfoRow_RBIV: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.appInfo)
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

#Preview {
    RecipeBookImportView()
        .modelContainer(for: [RecipeX.self, Book.self], inMemory: true)
}
