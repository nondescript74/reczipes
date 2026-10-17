//
//  BookDetailView.swift
//  Reczipes2
//
//  Created on 1/28/26.
//

import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var savedRecipes: [RecipeX]
    @Query private var sharedBooks: [SharedRecipeBook]
    
    let book: Book
    
    @State private var currentPage = 0
    @State private var showingBookEditor = false
    @State private var showingExportOptions = false
    @State private var isExporting = false
    @State private var exportedFileURL: URL?
    @State private var showingShareSheet = false
    @State private var exportError: Error?
    @State private var showingExportError = false
    @State private var isUpdatingPublicCopy = false
    @State private var publicCopyMessage: String?
    @State private var showingRemoveMissing = false

    /// True when this book has an active public share (shown on the community/web catalogue).
    private var isPubliclyShared: Bool {
        sharedBooks.contains { $0.bookID == book.id && $0.isActive }
    }
    
    private var isPad: Bool {
        horizontalSizeClass == .regular
    }
    
    // Get recipes in the book, maintaining order
    private var bookRecipes: [RecipeX] {
        guard let recipeIDs = book.recipeIDs else { return [] }
        return recipeIDs.compactMap { recipeID in
            savedRecipes.first { $0.id == recipeID }
        }
    }
    
    /// Recipe ids this book lists that no longer match any recipe in the library
    /// (left behind when a recipe was deleted or merged away). Empty while the
    /// library hasn't loaded, so an empty store never looks like "all missing".
    private var missingRecipeIDs: [UUID] {
        guard let recipeIDs = book.recipeIDs, !savedRecipes.isEmpty else { return [] }
        let existing = Set(savedRecipes.compactMap(\.id))
        return recipeIDs.filter { !existing.contains($0) }
    }

    private var bookColor: Color {
        if let colorHex = book.color {
            return Color(hex: colorHex) ?? .blue
        }
        return .blue
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if bookRecipes.isEmpty {
                    emptyBookView
                } else {
                    recipePageView
                }
            }
            .navigationTitle(book.displayName)
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingBookEditor = true
                        } label: {
                            Label("Edit Book", systemImage: "pencil")
                        }
                        
                        if isPubliclyShared {
                            Button {
                                Task { await updatePublicCopy() }
                            } label: {
                                Label(isUpdatingPublicCopy ? "Updating Public Copy…" : "Update Public Copy",
                                      systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(isUpdatingPublicCopy)
                        }

                        if !missingRecipeIDs.isEmpty {
                            Button {
                                showingRemoveMissing = true
                            } label: {
                                Label("Remove \(missingRecipeIDs.count) Missing Recipe Link\(missingRecipeIDs.count == 1 ? "" : "s")…",
                                      systemImage: "scissors")
                            }
                        }

                        Divider()
                        
                        Button {
                            showingExportOptions = true
                        } label: {
                            Label("Export Book", systemImage: "square.and.arrow.up")
                        }
                        .disabled(bookRecipes.isEmpty)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingBookEditor) {
                BookEditorView(book: book)
            }
            .confirmationDialog("Remove Missing Recipe Links?", isPresented: $showingRemoveMissing, titleVisibility: .visible) {
                Button("Remove \(missingRecipeIDs.count) Link\(missingRecipeIDs.count == 1 ? "" : "s")", role: .destructive) {
                    Task { await removeMissingRecipeLinks() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(missingLinksMessage)
            }
            .confirmationDialog("Export Recipe Book", isPresented: $showingExportOptions) {
                Button("Export with Images") {
                    Task {
                        await exportBook(includeImages: true)
                    }
                }
                
                Button("Export without Images") {
                    Task {
                        await exportBook(includeImages: false)
                    }
                }
                
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Choose whether to include images in the export. Files with images will be larger but more complete.")
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet_BDV(activityItems: [url])
                }
            }
            .alert("Public Copy", isPresented: Binding(
                get: { publicCopyMessage != nil },
                set: { if !$0 { publicCopyMessage = nil } }
            )) {
                Button("OK", role: .cancel) { publicCopyMessage = nil }
            } message: {
                Text(publicCopyMessage ?? "")
            }
            .alert("Export Failed", isPresented: $showingExportError) {
                Button("OK") { }
            } message: {
                if let error = exportError {
                    Text(error.localizedDescription)
                }
            }
            .overlay {
                if isExporting {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Exporting Recipe Book...")
                                .font(.headline)
                        }
                        .padding(32)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }
    
    // MARK: - Empty Book View
    
    private var emptyBookView: some View {
        ContentUnavailableView {
            Label("Empty Book", systemImage: "book.closed")
        } description: {
            Text("This book doesn't have any recipes yet")
        } actions: {
            Button {
                dismiss()
            } label: {
                Label("Back to Library", systemImage: "arrow.left")
            }
            .buttonStyle(.borderedProminent)
            .tint(bookColor)
        }
    }
    
    // MARK: - Recipe Page View
    
    private var recipePageView: some View {
        VStack(spacing: 0) {
            // Page indicator
            HStack {
                Text("Recipe \(currentPage + 1) of \(bookRecipes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Quick navigation
                if bookRecipes.count > 1 {
                    Button {
                        withAnimation {
                            currentPage = max(0, currentPage - 1)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                    }
                    .disabled(currentPage == 0)
                    
                    Button {
                        withAnimation {
                            currentPage = min(bookRecipes.count - 1, currentPage + 1)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .disabled(currentPage == bookRecipes.count - 1)
                }
            }
            .padding()
            .background(Color.appSystemBackground)
            
            // Page turning view
            TabView(selection: $currentPage) {
                ForEach(Array(bookRecipes.enumerated()), id: \.element.id) { index, recipe in
                    BookRecipePageView(
                        recipe: recipe, 
                        pageNumber: index + 1, 
                        bookColor: bookColor,
                        savedRecipes: savedRecipes
                    )
                    .tag(index)
                }
            }
            .platformPageTabViewStyle(indexDisplayMode: .never)
            .platformPageIndexViewStyle(backgroundDisplayMode: .never)
        }
    }
    
    // MARK: - Export
    
    /// Overwrites this book's public record with its current recipe list, in place.
    /// Nothing is unshared or deleted; the web reader picks it up within its cache window.
    private func updatePublicCopy() async {
        isUpdatingPublicCopy = true
        defer { isUpdatingPublicCopy = false }
        do {
            _ = try await CloudKitSharingService.shared.shareRecipeBook(book, modelContext: modelContext, refreshExisting: true)
            publicCopyMessage = "Updated the public copy of '\(book.displayName)' with \(bookRecipes.count) recipes."
        } catch {
            AppLog.error("Failed to update public copy of book '\(book.displayName)': \(error)", category: .sharing)
            publicCopyMessage = "Couldn't update the public copy: \(error.localizedDescription)"
        }
    }

    /// Names the missing entries from the book's stored previews where it can.
    private var missingLinksMessage: String {
        let titles = Dictionary(book.recipePreviews.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        let names = missingRecipeIDs.map { titles[$0] ?? "Untitled (\($0.uuidString.prefix(8)))" }
        return "This book lists \(names.count) recipe\(names.count == 1 ? "" : "s") that no longer exist in your library: "
            + names.joined(separator: ", ")
            + ". Only the links are removed from the book; no recipe is deleted."
            + (isPubliclyShared ? " The book's public copy is updated afterwards." : "")
    }

    /// Drops recipe ids that match no recipe in the library. Never deletes a recipe.
    private func removeMissingRecipeLinks() async {
        let missing = missingRecipeIDs
        guard !missing.isEmpty else { return }
        for id in missing { book.removeRecipe(id) }
        do {
            try modelContext.save()
            AppLog.info("Removed \(missing.count) missing recipe links from book '\(book.displayName)': \(missing.map(\.uuidString))", category: .recipe)
        } catch {
            AppLog.error("Failed to save after removing missing links from '\(book.displayName)': \(error)", category: .recipe)
            publicCopyMessage = "Couldn't save the book: \(error.localizedDescription)"
            return
        }
        if isPubliclyShared {
            await updatePublicCopy()
        } else {
            publicCopyMessage = "Removed \(missing.count) missing recipe link\(missing.count == 1 ? "" : "s") from '\(book.displayName)'."
        }
    }

    private func exportBook(includeImages: Bool) async {
        isExporting = true
        exportError = nil
        
        // TODO: Create export service for new Book model
        // For now, show a message
        await MainActor.run {
            isExporting = false
            AppLog.info("Book export not yet implemented for new Book model", category: .backup)
        }
    }
}

// MARK: - Book Recipe Page View

struct BookRecipePageView: View {
    let recipe: RecipeX
    let pageNumber: Int
    let bookColor: Color
    let savedRecipes: [RecipeX]
    
    @State private var showingFullDetail = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var recipeXEntities: [RecipeX] // Query for RecipeX to get imageData
    
    private var isSaved: Bool {
        savedRecipes.contains { $0.id == recipe.id }
    }
    
    // Get RecipeX entity for this recipe to access imageData
    private var recipeX: RecipeX? {
        recipeXEntities.first { $0.id == recipe.id }
    }
    
    // On iPad (regular width), use fullScreenCover; on iPhone use sheet
    private var isPad: Bool {
        horizontalSizeClass == .regular
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Recipe image
                    if recipeX?.imageData != nil || recipe.imageName != nil {
                        RecipeImageView(
                            imageName: recipe.imageName,
                            imageData: recipeX?.imageData, // Pass imageData from RecipeX!
                            size: CGSize(width: geometry.size.width, height: 300),
                            cornerRadius: 0
                        )
                        .frame(height: 300)
                        .clipped()
                    } else {
                        // Placeholder image
                        Rectangle()
                            .fill(bookColor.opacity(0.3))
                            .frame(height: 300)
                            .overlay {
                                VStack(spacing: 12) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.secondary)
                                    Text("No Image")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        // Page number decoration
                        HStack {
                            Rectangle()
                                .fill(bookColor)
                                .frame(width: 4, height: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Page \(pageNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text(recipe.title ?? "No title")
                                    .font(.title)
                                    .fontWeight(.bold)
                            }
                            
                            Spacer()
                        }
                        
                        // View Full Recipe button
                        Button {
                            showingFullDetail = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass")
                                Text("View Full Recipe")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(bookColor.opacity(0.1))
                            .foregroundStyle(bookColor)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.bottom, 8)
                        
                        // Header notes
                        if let headerNotes = recipe.headerNotes {
                            Text(headerNotes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Yield
                        if let recipeYield = recipe.yield {
                            HStack {
                                Image(systemName: "person.2")
                                    .foregroundStyle(bookColor)
                                Text(recipeYield)
                                    .font(.subheadline)
                            }
                        }
                        
                        Divider()
                        
                        // Ingredients
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Ingredients", systemImage: "list.bullet")
                                .font(.headline)
                                .foregroundStyle(bookColor)
                            
                            ForEach(recipe.ingredientSections, id: \.id) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    if let title = section.title {
                                        Text(title)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    ForEach(section.ingredients, id: \.id) { ingredient in
                                        HStack(alignment: .top, spacing: 8) {
                                            Circle()
                                                .fill(bookColor.opacity(0.3))
                                                .frame(width: 6, height: 6)
                                                .padding(.top, 6)
                                            
                                            Text(ingredient.displayText)
                                                .font(.body)
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Instructions
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Instructions", systemImage: "text.alignleft")
                                .font(.headline)
                                .foregroundStyle(bookColor)
                            
                            ForEach(recipe.instructionSections, id: \.id) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    if let title = section.title {
                                        Text(title)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    ForEach(Array(section.steps.enumerated()), id: \.element.id) { index, step in
                                        HStack(alignment: .top, spacing: 12) {
                                            Text("\(index + 1)")
                                                .font(.body)
                                                .fontWeight(.bold)
                                                .foregroundStyle(Color.onTint)
                                                .frame(width: 28, height: 28)
                                                .background(bookColor, in: Circle())
                                            
                                            Text(step.text)
                                                .font(.body)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Notes
                        if !recipe.notes.isEmpty {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Notes", systemImage: "note.text")
                                    .font(.headline)
                                    .foregroundStyle(bookColor)
                                
                                ForEach(recipe.notes, id: \.id) { note in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(note.type.rawValue.capitalized)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text(note.text)
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        
                        // Reference
                        if let reference = recipe.reference {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Source", systemImage: "link")
                                    .font(.headline)
                                    .foregroundStyle(bookColor)
                                
                                Text(reference)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .platformFullScreenCover(isPresented: $showingFullDetail) {
            if let recipeXEntity = recipeX {
                NavigationStack {
                    RecipeDetailView(recipe: recipeXEntity)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    showingFullDetail = false
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.hierarchical)
                                        Text("Close")
                                            .font(.body)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                }
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Book.self, RecipeX.self, VersionHistoryRecord.self, configurations: config)
    
    // Create a sample book
    let book = Book(
        name: "Favorites",
        bookDescription: "My favorite recipes",
        color: "FF6B6B"
    )
    
    container.mainContext.insert(book)
    
    return BookDetailView(book: book)
        .modelContainer(container)
}

// MARK: - Share Sheet

#if os(iOS)
import UIKit
#endif

#if os(iOS)
struct ShareSheet_BDV: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}
#else
struct ShareSheet_BDV: View {
    let activityItems: [Any]
    var body: some View { MacShareView(items: activityItems) }
}
#endif


