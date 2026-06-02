//
//  RecipeBookDocumentHandler.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/22/26.
//

import SwiftUI
import SwiftData
import Combine

/// Handles opening .recipebook files when tapped from Files app or AirDrop
@MainActor
final class RecipeBookDocumentHandler: ObservableObject {
    static let shared = RecipeBookDocumentHandler()
    
    @Published var pendingImportURL: URL?
    @Published var showImportSheet = false
    @Published var importError: Error?
    
    private init() {}
    
    /// Call this when a .recipebook file is opened
    func handleIncomingDocument(_ url: URL) {
        AppLog.info("Received recipe book document: \(url.lastPathComponent)", category: .batch)
        
        // Security-scoped resource access
        guard url.startAccessingSecurityScopedResource() else {
            AppLog.error("Failed to access security-scoped resource: \(url)", category: .batch)
            return
        }
        
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        
        // Copy to temp location for import
        do {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            
            // Remove any existing temp file
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            
            // Copy the file
            try FileManager.default.copyItem(at: url, to: tempURL)
            
            // Set pending import
            pendingImportURL = tempURL
            showImportSheet = true
            
            AppLog.info("Prepared recipe book for import: \(tempURL.lastPathComponent)", category: .batch)
            
        } catch {
            AppLog.error("Failed to prepare recipe book for import: \(error)", category: .batch)
            importError = error
        }
    }
    
    /// Clears the pending import
    func clearPendingImport() {
        if let url = pendingImportURL {
            try? FileManager.default.removeItem(at: url)
        }
        pendingImportURL = nil
        showImportSheet = false
        importError = nil
    }
}

// MARK: - Import Sheet View

struct RecipeBookImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var handler: RecipeBookDocumentHandler
    
    @State private var isImporting = false
    @State private var importedBook: Book?
    @State private var importError: Error?
    @State private var replaceExisting = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isImporting {
                    // Importing state
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    
                    Text("Importing Recipe Book...")
                        .font(.headline)
                    
                    Text("Please wait while we import your recipes and images.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                } else if let book = importedBook {
                    // Success state
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    
                    Text("Import Successful!")
                        .font(.title2)
                        .bold()
                    
                    Text("Imported **\(String(describing: book.name))** with \(book.recipeIDs!.count) recipes.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button {
                        dismiss()
                        handler.clearPendingImport()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                } else if let error = importError {
                    // Error state
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange)
                    
                    Text("Import Failed")
                        .font(.title2)
                        .bold()
                    
                    Text(error.localizedDescription)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    
                    Button {
                        dismiss()
                        handler.clearPendingImport()
                    } label: {
                        Text("Dismiss")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                } else {
                    // Ready to import state
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    
                    Text("Import Recipe Book")
                        .font(.title2)
                        .bold()
                    
                    if let url = handler.pendingImportURL {
                        Text(url.lastPathComponent)
                            .font(.headline)
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    Text("This will import all recipes and images from this recipe book.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    
                    Toggle("Replace existing book if duplicate", isOn: $replaceExisting)
                        .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        Button {
                            Task {
                                await performImport()
                            }
                        } label: {
                            Text("Import")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                        
                        Button {
                            dismiss()
                            handler.clearPendingImport()
                        } label: {
                            Text("Cancel")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.secondary.opacity(0.2))
                                .foregroundStyle(.primary)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("Recipe Book Import")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func performImport() async {
        guard let url = handler.pendingImportURL else { return }
        
        isImporting = true
        importError = nil
        
        do {
            let book = try await RecipeBookExportService.importBook(
                from: url,
                modelContext: modelContext,
                replaceExisting: replaceExisting
            )
            
            importedBook = book
            
            AppLog.info("Successfully imported recipe book: \(String(describing: book.name))", category: .batch)
            
            // Log user diagnostic
            logUserDiagnostic(
                .info,
                category: .sharing,
                title: "Recipe Book Imported",
                message: "Successfully imported \(String(describing: book.name)) with \(book.recipeIDs!.count) recipes.",
                technicalDetails: "Import completed from \(url.lastPathComponent)"
            )
            
        } catch {
            importError = error
            
            AppLog.error("Failed to import recipe book: \(error)", category: .batch)
            
            logUserDiagnostic(
                .error,
                category: .sharing,
                title: "Import Failed",
                message: "Couldn't import the recipe book.",
                technicalDetails: error.localizedDescription
            )
        }
        
        isImporting = false
    }
}
