//
//  RecipeBookDetailView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/28/25.
//

import SwiftUI
import SwiftData

struct RecipeBookDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var savedRecipes: [RecipeX]  // ✅ Changed from Recipe to RecipeX
    
    let book: Book
    
    @State private var currentPage = 0
    @State private var showingRecipeSelector = false
    @State private var showingBookEditor = false
    
    private var isPad: Bool {
        horizontalSizeClass == .regular
    }
    
    // Get recipes in the book, maintaining order
    private var bookRecipes: [RecipeX] {  // ✅ Changed from RecipeModel to RecipeX
        book.recipeIDs?.compactMap { recipeID in
            savedRecipes.first { $0.id == recipeID }  // ✅ Return RecipeX directly
        } ?? []
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
            .navigationTitle(book.name ?? "No Name")
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
                            showingRecipeSelector = true
                        } label: {
                            Label("Add Recipes", systemImage: "plus")
                        }
                        
                        Button {
                            showingBookEditor = true
                        } label: {
                            Label("Edit Book", systemImage: "pencil")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingRecipeSelector) {
                NavigationStack {
                    RecipeBookRecipeSelectorView(book: book)
                }
                .platformPresentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingBookEditor) {
                NavigationStack {
                    RecipeBookEditorView(book: book)
                }
                .platformPresentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
    
    // MARK: - Empty Book View
    
    private var emptyBookView: some View {
        ContentUnavailableView {
            Label("Empty Book", systemImage: "book.closed")
        } description: {
            Text("Add recipes to \"\(String(describing: book.name))\" to get started")
        } actions: {
            Button {
                showingRecipeSelector = true
            } label: {
                Label("Add Recipes", systemImage: "plus.circle.fill")
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
                    RecipePageView(
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
}

// MARK: - Recipe Page View

struct RecipePageView: View {
    let recipe: RecipeX  // ✅ Changed from RecipeModel to RecipeX
    let pageNumber: Int
    let bookColor: Color
    let savedRecipes: [RecipeX]  // ✅ Changed from Recipe to RecipeX
    
    @State private var showingFullDetail = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isSaved: Bool {
        savedRecipes.contains { $0.id == recipe.id }
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
                    if recipe.imageData != nil || recipe.imageName != nil {  // ✅ Access directly from RecipeX
                        RecipeImageView(
                            imageName: recipe.imageName,
                            imageData: recipe.imageData,  // ✅ Access directly from RecipeX
                            size: CGSize(width: geometry.size.width, height: 300),
                            cornerRadius: 0
                        )
                        .frame(height: 300)
                        .clipped()
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
                                
                                Text(recipe.title ?? "Untitled")  // ✅ Handle optional title
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
                        if let recipeYield = recipe.recipeYield {  // ✅ Use recipeYield instead of yield
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
            .platformFullScreenCover(isPresented: $showingFullDetail) {
                NavigationStack {
                    RecipeDetailView(recipe: recipe)
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
            .sheet(isPresented: $showingFullDetail) {
                NavigationStack {
                    RecipeDetailView(recipe: recipe)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    showingFullDetail = false
                                }
                            }
                        }
                }
                .platformPresentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}



#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let schema = Schema([Book.self, RecipeX.self, VersionHistoryRecord.self])
    let container = try! ModelContainer(for: schema, configurations: config)
    
    // Create a sample book
    let book = Book(
        name: "Favorites",
        bookDescription: "My favorite recipes",
        color: "FF6B6B"
    )
    
    container.mainContext.insert(book)
    
    return RecipeBookDetailView(book: book)
        .modelContainer(container)
}

