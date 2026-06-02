//
//  BookEditorView.swift
//  Reczipes2
//
//  Created on 1/28/26.
//

import SwiftUI
import SwiftData
import PhotosUI

struct BookEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var savedRecipes: [RecipeX]
    
    let book: Book?
    
    @State private var name: String
    @State private var bookDescription: String
    @State private var selectedColor: Color
    @State private var coverImageData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingImage = false
    @State private var showingRecipeManager = false
    @State private var category: String
    @State private var cuisine: String
    
    private let availableColors: [Color] = [
        .blue, .purple, .pink, .red, .orange,
        .yellow, .green, .teal, .indigo, .brown
    ]
    
    // Get recipes currently in the book (for editing existing book)
    private var bookRecipes: [RecipeX] {
        guard let book = book, let recipeIDs = book.recipeIDs else { return [] }
        return recipeIDs.compactMap { recipeID in
            savedRecipes.first { $0.id == recipeID }
        }
    }
    
    init(book: Book? = nil) {
        self.book = book
        _name = State(initialValue: book?.name ?? "")
        _bookDescription = State(initialValue: book?.bookDescription ?? "")
        _coverImageData = State(initialValue: book?.coverImageData)
        _category = State(initialValue: book?.category ?? "")
        _cuisine = State(initialValue: book?.cuisine ?? "")
        
        if let colorHex = book?.color, let color = Color(hex: colorHex) {
            _selectedColor = State(initialValue: color)
        } else {
            _selectedColor = State(initialValue: .blue)
        }
    }
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Book Details") {
                    TextField("Book Name", text: $name)
                    
                    TextField("Description (Optional)", text: $bookDescription, axis: .vertical)
                        .lineLimit(3...6)
                    
                    TextField("Category (Optional)", text: $category)
                        .textInputAutocapitalization(.words)
                    
                    TextField("Cuisine (Optional)", text: $cuisine)
                        .textInputAutocapitalization(.words)
                }
                
                Section("Cover Image") {
                    if let imageData = coverImageData, let uiImage = UIImage(data: imageData) {
                        HStack {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            Spacer()
                            
                            Button("Remove", role: .destructive) {
                                removeCoverImage()
                            }
                        }
                    }
                    
                    let hasCoverImage = coverImageData != nil
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(hasCoverImage ? "Change Cover Image" : "Add Cover Image",
                              systemImage: "photo")
                    }
                    .disabled(isProcessingImage)
                    
                    if isProcessingImage {
                        HStack {
                            ProgressView()
                            Text("Processing image...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Color Theme") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(availableColors, id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if colorMatches(color, selectedColor) {
                                        Circle()
                                            .strokeBorder(.white, lineWidth: 3)
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white)
                                            .fontWeight(.bold)
                                    }
                                }
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                }
                
                // Recipes section (only for existing books)
                if book != nil {
                    Section {
                        Button {
                            showingRecipeManager = true
                        } label: {
                            HStack {
                                Label("Manage Recipes", systemImage: "book.pages")
                                Spacer()
                                Text("\(bookRecipes.count)")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } header: {
                        Text("Recipes")
                    } footer: {
                        Text("Add or remove recipes from this book")
                    }
                }
            }
            .navigationTitle(book == nil ? "New Book" : "Edit Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(book == nil ? "Create" : "Save") {
                        saveBook()
                    }
                    .disabled(!isValid)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    await loadImage(from: newItem)
                }
            }
            .sheet(isPresented: $showingRecipeManager) {
                if let book = book {
                    BookRecipeManagerView(book: book)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func colorMatches(_ color1: Color, _ color2: Color) -> Bool {
        // Simple comparison using hex strings
        return color1.toHex() == color2.toHex()
    }
    
    private func loadImage(from photoItem: PhotosPickerItem?) async {
        guard let photoItem = photoItem else { return }
        
        isProcessingImage = true
        defer { isProcessingImage = false }
        
        do {
            guard let data = try await photoItem.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else {
                AppLog.error("Failed to load image data", category: .recipe)
                return
            }
            
            // Compress the image using centralized utility (slightly larger for book covers)
            guard let jpegData = ImageCompressionUtility.compressForBookCover(uiImage) else {
                AppLog.error("Failed to compress image", category: .recipe)
                return
            }

            await MainActor.run {
                coverImageData = jpegData
                // Update existing book if editing
                if let existingBook = book {
                    existingBook.coverImageData = jpegData
                    existingBook.coverImageHash = Book.calculateImageHash(from: jpegData)
                }
            }

            AppLog.info("Prepared book cover image - Size: \(ImageCompressionUtility.formatSize(jpegData.count))", category: .recipe)
        } catch {
            AppLog.error("Error loading image: \(error)", category: .recipe)
        }
    }
    
    private func removeCoverImage() {
        coverImageData = nil
        if let existingBook = book {
            existingBook.coverImageData = nil
            existingBook.coverImageHash = nil
        }
    }
    
    private func saveBook() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = bookDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCuisine = cuisine.trimmingCharacters(in: .whitespacesAndNewlines)
        let colorHex = selectedColor.toHex()
        
        if let book = book {
            // Update existing book
            book.name = trimmedName
            book.bookDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
            book.coverImageData = coverImageData
            book.coverImageHash = Book.calculateImageHash(from: coverImageData)
            book.color = colorHex
            book.category = trimmedCategory.isEmpty ? nil : trimmedCategory
            book.cuisine = trimmedCuisine.isEmpty ? nil : trimmedCuisine
            book.markModified()
            
            AppLog.info("Updated book: \(book.displayName)", category: .recipe)
        } else {
            // Create new book
            let newBook = Book(
                name: trimmedName,
                bookDescription: trimmedDescription.isEmpty ? nil : trimmedDescription,
                coverImageData: coverImageData,
                color: colorHex,
                recipeIDs: [],
                dateCreated: Date(),
                dateModified: Date(),
                version: 1,
                needsCloudSync: false,
                isShared: false,
                category: trimmedCategory.isEmpty ? nil : trimmedCategory,
                cuisine: trimmedCuisine.isEmpty ? nil : trimmedCuisine
            )
            
            // Calculate hashes
            newBook.coverImageHash = Book.calculateImageHash(from: coverImageData)
            newBook.recipeIDsHash = Book.calculateRecipeIDsHash(from: [])
            
            modelContext.insert(newBook)
            
            AppLog.info("Created new Book: \(newBook.displayName)", category: .recipe)
        }
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            AppLog.error("Failed to save book: \(error)", category: .recipe)
        }
    }
}

#Preview {
    BookEditorView()
        .modelContainer(for: Book.self, inMemory: true)
}
