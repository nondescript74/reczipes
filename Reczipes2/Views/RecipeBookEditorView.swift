//
//  RecipeBookEditorView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/28/25.
//

import SwiftUI
import SwiftData
import PhotosUI

struct RecipeBookEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var savedRecipes: [RecipeX]
    
    let book: Book?
    
    @State private var name: String
    @State private var bookDescription: String
    @State private var selectedColor: Color
    @State private var coverImageName: String?
    @State private var coverImageData: Data? // NEW: Hold image data
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingImage = false
    @State private var showingRecipeManager = false
    
    private let availableColors: [Color] = [
        .blue, .purple, .pink, .red, .orange,
        .yellow, .green, .teal, .indigo, .brown
    ]
    
    // Get recipes currently in the book (for editing existing book)
    private var bookRecipes: [RecipeX] {
        guard let book = book else { return [] }
        return book.recipeIDs?.compactMap { recipeID in
            savedRecipes.first { $0.id == recipeID }
        } ?? []
    }
    
    private var hasCoverImage: Bool {
        coverImageName != nil || coverImageData != nil
    }
    
    @ViewBuilder
    private var coverImageSection: some View {
        if hasCoverImage {
            HStack {
                RecipeImageView(
                    imageName: coverImageName,
                    imageData: coverImageData,
                    size: CGSize(width: 120, height: 160),
                    cornerRadius: 8
                )
                
                Spacer()
                
                Button("Remove", role: .destructive) {
                    removeCoverImage()
                }
            }
        }
        
        let hasImage = hasCoverImage
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Label(hasImage ? "Change Cover Image" : "Add Cover Image",
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
    
    init(book: Book? = nil) {
        self.book = book
        _name = State(initialValue: book?.name ?? "")
        _bookDescription = State(initialValue: book?.bookDescription ?? "")
        _coverImageName = State(initialValue: book?.coverImageName)
        _coverImageData = State(initialValue: book?.coverImageData)
        
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
                }
                
                Section("Cover Image") {
                    coverImageSection
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
                                            .foregroundStyle(Color.onTint)
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
            .platformNavigationBarTitleDisplayMode(.inline)
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
                    RecipeBookRecipeManagerView(book: book)
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
                  let uiImage = PlatformImage(data: data) else {
                AppLog.error("Failed to load image data", category: .recipe)
                return
            }
            
            // Compress the image using centralized utility (slightly larger for book covers)
            guard let jpegData = ImageCompressionUtility.compressForBookCover(uiImage) else {
                AppLog.error("Failed to compress image", category: .recipe)
                return
            }

            // Generate a name for reference
            let imageName = "book_cover_\(UUID().uuidString).jpg"

            await MainActor.run {
                coverImageName = imageName
                coverImageData = jpegData
                // Store image data directly in the model - this will save to SwiftData
                if let existingBook = book {
                    existingBook.coverImageData = jpegData
                    existingBook.coverImageName = imageName
                }
            }

            AppLog.info("Prepared book cover image: \(imageName) - Size: \(ImageCompressionUtility.formatSize(jpegData.count))", category: .recipe)
        } catch {
            AppLog.error("Error loading image: \(error)", category: .recipe)
        }
    }
    
    private func removeCoverImage() {
        coverImageName = nil
        coverImageData = nil
    }
    
    private func saveBook() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = bookDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let colorHex = selectedColor.toHex()
        
        if let book = book {
            // Update existing book
            book.name = trimmedName
            book.bookDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
            book.coverImageName = coverImageName
            book.coverImageData = coverImageData
            book.color = colorHex
            book.dateModified = Date()
            
            AppLog.info("Updated book: \(String(describing: book.name))", category: .recipe)
        } else {
            // Create new book
            let newBook = Book(
                name: trimmedName,
                bookDescription: trimmedDescription.isEmpty ? nil : trimmedDescription,
                coverImageData: coverImageData,
                coverImageName: coverImageName,
                color: colorHex
            )
            modelContext.insert(newBook)
            
            AppLog.info("Created new book: \(String(describing: newBook.name))", category: .recipe)
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
    RecipeBookEditorView()
        .modelContainer(for: Book.self, inMemory: true)
}
