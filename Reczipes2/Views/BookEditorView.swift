//
//  BookEditorView.swift
//  Reczipes2
//
//  Created on 1/28/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

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
    /// Covers + interior pictures (saved on Save)
    @State private var images: [BookImage]
    private let originalImages: [BookImage]
    @State private var selectedPictureItems: [PhotosPickerItem] = []
    @State private var newPictureKind: String = BookImage.interiorKind
    @State private var isProcessingPictures = false
    /// Glossary (optional; saved on Save)
    @State private var glossary: [BookGlossaryEntry]
    private let originalGlossary: [BookGlossaryEntry]
    @State private var showingGlossaryImporter = false
    @State private var glossaryMessage: String?
    
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
        let existingImages = book?.images ?? []
        _images = State(initialValue: existingImages)
        self.originalImages = existingImages
        let existingGlossary = book?.glossary ?? []
        _glossary = State(initialValue: existingGlossary)
        self.originalGlossary = existingGlossary
        
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
                        .platformTextInputAutocapitalization(.words)
                    
                    TextField("Cuisine (Optional)", text: $cuisine)
                        .platformTextInputAutocapitalization(.words)
                }
                
                Section("Cover Image") {
                    if let imageData = coverImageData, let uiImage = PlatformImage(data: imageData) {
                        HStack {
                            Image(platformImage: uiImage)
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
                
                picturesSection

                glossarySection

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
            .formStyle(.grouped)   // scrolls on macOS; the default column style does not
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
            .onChange(of: selectedPictureItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await addPictures(from: items) }
            }
            .fileImporter(isPresented: $showingGlossaryImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): importGlossary(from: url)
                case .failure(let error): glossaryMessage = "Couldn't open the file: \(error.localizedDescription)"
                }
            }
            .alert("Glossary", isPresented: Binding(
                get: { glossaryMessage != nil },
                set: { if !$0 { glossaryMessage = nil } }
            )) {
                Button("OK") { glossaryMessage = nil }
            } message: {
                Text(glossaryMessage ?? "")
            }
            .sheet(isPresented: $showingRecipeManager) {
                if let book = book {
                    BookRecipeManagerView(book: book)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, idealWidth: 760, minHeight: 480, idealHeight: 760)
        #endif
    }
    
    // MARK: - Pictures

    private var picturesSection: some View {
        Section {
            ForEach(images) { image in
                pictureRow(image)
            }

            Picker("Add as", selection: $newPictureKind) {
                Text("Cover").tag(BookImage.coverKind)
                Text("Interior").tag(BookImage.interiorKind)
            }
            PhotosPicker(selection: $selectedPictureItems, maxSelectionCount: 20, matching: .images) {
                Label("Add Pictures", systemImage: "photo.badge.plus")
            }
            .disabled(isProcessingPictures)
            if isProcessingPictures {
                HStack {
                    ProgressView()
                    Text("Processing pictures...")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Covers & Pictures (\(images.count))")
        } footer: {
            Text("Several covers are allowed; the first cover is the book's main cover. Pictures are stored at up to 1600 px, one iCloud record each.")
        }
    }

    private func pictureRow(_ image: BookImage) -> some View {
        let index = images.firstIndex(where: { $0.id == image.id })
        return HStack(alignment: .top, spacing: 12) {
            BookImageThumbnail(image: image, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Picker("Kind", selection: Binding(
                    get: { image.isCover ? BookImage.coverKind : BookImage.interiorKind },
                    set: { newKind in updateImage(image.id) { $0.kind = newKind } }
                )) {
                    Text("Cover").tag(BookImage.coverKind)
                    Text("Interior").tag(BookImage.interiorKind)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                TextField("Caption", text: Binding(
                    get: { image.caption ?? "" },
                    set: { text in updateImage(image.id) { $0.caption = text.isEmpty ? nil : text } }
                ), axis: .vertical)
                .lineLimit(1...4)
                .font(.caption)
                HStack(spacing: 16) {
                    Button {
                        moveImage(image.id, by: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(index == 0)
                    Button {
                        moveImage(image.id, by: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(index == images.count - 1)
                    Spacer()
                    Button(role: .destructive) {
                        images.removeAll { $0.id == image.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func updateImage(_ id: UUID, _ change: (inout BookImage) -> Void) {
        guard let i = images.firstIndex(where: { $0.id == id }) else { return }
        change(&images[i])
    }

    private func moveImage(_ id: UUID, by offset: Int) {
        guard let i = images.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard j >= 0, j < images.count else { return }
        images.swapAt(i, j)
    }

    private func addPictures(from items: [PhotosPickerItem]) async {
        isProcessingPictures = true
        defer {
            isProcessingPictures = false
            selectedPictureItems = []
        }
        let kind = newPictureKind
        for item in items {
            do {
                guard let raw = try await item.loadTransferable(type: Data.self),
                      let prepared = BookImageProcessing.prepare(data: raw) else {
                    AppLog.error("Failed to load book picture", category: .image)
                    continue
                }
                images.append(BookImage(
                    id: UUID(),
                    title: nil,
                    caption: nil,
                    imageData: prepared,
                    order: images.count,
                    dateAdded: Date(),
                    kind: kind
                ))
            } catch {
                AppLog.error("Error loading book picture: \(error)", category: .image)
            }
        }
    }

    // MARK: - Glossary

    private var glossarySection: some View {
        Section {
            if glossary.isEmpty {
                Text("No glossary")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(glossary.count) terms")
                Button("Remove Glossary", role: .destructive) {
                    glossary = []
                }
            }
            Button {
                #if os(macOS)
                if let url = MacFilePicker.pickFile(types: [.json], message: "Choose a glossary JSON file") {
                    importGlossary(from: url)
                }
                #else
                showingGlossaryImporter = true
                #endif
            } label: {
                Label(glossary.isEmpty ? "Import Glossary JSON…" : "Replace Glossary from JSON…",
                      systemImage: "character.book.closed")
            }
        } header: {
            Text("Glossary (Optional)")
        } footer: {
            Text("A JSON list of {term, local_name, definition, book_page}.")
        }
    }

    private func importGlossary(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let entries = try FlexibleGlossaryEntry.entries(from: Data(contentsOf: url))
            glossary = entries
            glossaryMessage = "Loaded \(entries.count) glossary terms. Tap Save to keep them."
        } catch {
            glossaryMessage = "That file isn't a glossary list: \(error.localizedDescription)"
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
            if images != originalImages {
                // Writes BookPicture records; also makes the first cover picture the main cover
                book.setImagesUpdatingPrimaryCover(images, in: modelContext)
            }
            if glossary != originalGlossary {
                if glossary.isEmpty {
                    book.glossaryData = nil
                } else {
                    book.setGlossary(glossary)
                }
            }
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
            
            if !glossary.isEmpty {
                newBook.setGlossary(glossary)
            }

            modelContext.insert(newBook)
            // After insert: pictures are written as BookPicture records for this book
            if !images.isEmpty {
                newBook.setImagesUpdatingPrimaryCover(images, in: modelContext)
            }
            
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
