//
//  RecipeBooksView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/28/25.
//

import SwiftUI
import SwiftData

struct RecipeBooksView: View {
    @Environment(\.modelContext) private var modelContext
    
    // New books (unified model)
    @Query(sort: \Book.dateModified, order: .reverse) private var books: [Book]
    @Query private var savedRecipesX: [RecipeX]
    
    @State private var showingEditor = false
    @State private var selectedBook: Book?
    @State private var editingBook: Book?
    @State private var searchText = ""
    @State private var showingImport = false
    @State private var refreshID = UUID()
    @State private var contentFilter: ContentFilterMode = .mine
    @State private var lastSyncDate: Date?
    
    // Sync interval: 5 minutes
    private let syncInterval: TimeInterval = 300
    
    // Grid layout
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]
    
    private var filteredBooks: [Book] {
        var result = books
        let currentUserID = CloudKitSharingService.shared.currentUserID
        
        // Apply content filter (mine/shared)
        switch contentFilter {
        case .mine:
            // For Book models, use ownerUserID
            result = result.filter { book in
                book.ownerUserID == nil || book.ownerUserID == currentUserID
            }
            
        case .shared:
            // Show books owned by others
            result = result.filter { book in
                book.ownerUserID != nil && book.ownerUserID != currentUserID
            }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { book in
                (book.name ?? "").localizedCaseInsensitiveContains(searchText) ||
                (book.bookDescription ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Deduplicate
        var seenIDs = Set<UUID>()
        result = result.filter { book in
            guard let bookID = book.id else { return false }
            if seenIDs.contains(bookID) {
                AppLog.warning("⚠️ Duplicate book ID detected: \(bookID) (\(book.name ?? "Untitled"))", category: .recipe)
                return false
            }
            seenIDs.insert(bookID)
            return true
        }
        
        return result
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Content filter picker (Mine/Shared)
                ContentFilterPicker(
                    selectedFilter: $contentFilter,
                    contentType: "Books"
                )
                .onChange(of: contentFilter) { oldValue, newValue in
                    // Sync community books when switching to "Shared" tab
                    if newValue == .shared {
                        Task {
                            await syncCommunityBooksIfNeeded()
                        }
                    }
                }
                
                // Main content
                if filteredBooks.isEmpty {
                    if books.isEmpty {
                        emptyStateView
                    } else {
                        // Books exist but none match the filter
                        emptyFilterStateView
                    }
                } else {
                    bookGridView
                }
            }
            .navigationTitle("Recipe Books")
            .searchable(text: $searchText, prompt: "Search books")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingEditor = true
                        } label: {
                            Label("New Book", systemImage: "plus")
                        }
                        
                        Button {
                            showingImport = true
                        } label: {
                            Label("Import Book", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                BookEditorView(book: editingBook)
                    .onDisappear {
                        editingBook = nil
                        refreshID = UUID()
                    }
            }
            .sheet(isPresented: $showingImport) {
                RecipeBookImportView()
            }
            .sheet(item: $selectedBook) { book in
                BookDetailView(book: book)
            }
            .onChange(of: refreshID) { oldValue, newValue in
                // Check if selected book still exists after refresh
                if let selected = selectedBook {
                    guard let selectedID = selected.id else { return }
                    let descriptor = FetchDescriptor<Book>(
                        predicate: #Predicate<Book> { book in
                            book.id == selectedID
                        }
                    )
                    
                    do {
                        let fetchedBooks = try modelContext.fetch(descriptor)
                        if fetchedBooks.isEmpty {
                            AppLog.info("📚 Dismissing sheet - book was deleted", category: .recipe)
                            selectedBook = nil
                        }
                    } catch {
                        AppLog.error("❌ Failed to verify book existence: \(error)", category: .recipe)
                        selectedBook = nil
                    }
                }
            }
            .onAppear {
                // Sync community books when view appears to catch any unshared books
                Task {
                    await syncCommunityBooksIfNeeded()
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack {
            Spacer()
            
            ContentUnavailableView {
                Label(emptyStateTitle, systemImage: "books.vertical")
            } description: {
                Text(emptyStateDescriptionText)
            } actions: {
                if contentFilter != .mine {
                    Button {
                        contentFilter = .mine
                    } label: {
                        Label("Show My Books", systemImage: "person.fill")
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                }
                
                if contentFilter != .mine {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Create Book", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Create Book", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            Spacer()
        }
    }
    
    private var emptyStateTitle: String {
        switch contentFilter {
        case .mine:
            return "No Recipe Books"
        case .shared:
            return "No Shared Books"
        }
    }
    
    private var emptyStateDescriptionText: String {
        switch contentFilter {
        case .mine:
            return "Create a book to organize your recipes"
        case .shared:
            return "No books have been shared by the community yet. Check back later or create and share your own books!"
        }
    }
    
    private var emptyFilterStateView: some View {
        VStack {
            Spacer()
            
            ContentUnavailableView {
                Label("No Books Found", systemImage: "books.vertical")
            } description: {
                Text(emptyFilterDescription)
            } actions: {
                Button {
                    contentFilter = .mine
                } label: {
                    Label("Show All Books", systemImage: "square.grid.2x2.fill")
                }
                .buttonStyle(BorderedProminentButtonStyle())
            }
            
            Spacer()
        }
    }
    
    private var emptyFilterDescription: String {
        if !searchText.isEmpty {
            return "No books match your search"
        }
        
        switch contentFilter {
        case .mine:
            return "You don't have any personal books yet"
        case .shared:
            return "No books have been shared with you"
        }
    }
    
    // MARK: - Book Grid View
    
    private var bookGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(filteredBooks.enumerated()), id: \.element.id) { index, book in
                    BookCardView(
                        book: book,
                        savedRecipes: savedRecipesX,
                        showSharedInfo: contentFilter != .mine
                    )
                        .id("\(book.id ?? UUID())-\(refreshID)-\(index)")
                        .onTapGesture {
                            selectedBook = book
                        }
                        .contextMenu {
                            Button {
                                editingBook = book
                                showingEditor = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                deleteBook(book)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Helper Methods
    
    private func deleteBook(_ book: Book) {
        withAnimation {
            // Delete all recipes in this book
            let recipeIDsToDelete = book.recipeIDs ?? []
            AppLog.info("Deleting book '\(book.name ?? "Untitled")' and \(recipeIDsToDelete.count) associated recipes", category: .recipe)
            
            // Fetch and delete each recipe
            for recipeID in recipeIDsToDelete {
                let descriptor = FetchDescriptor<RecipeX>(
                    predicate: #Predicate<RecipeX> { recipe in
                        recipe.id == recipeID
                    }
                )
                
                if let recipes = try? modelContext.fetch(descriptor),
                   let recipe = recipes.first {
                    AppLog.debug("Deleting recipe '\(recipe.title ?? "Untitled")' (ID: \(recipeID))", category: .recipe)
                    modelContext.delete(recipe)
                }
            }
            
            // Delete the book itself (cover image is stored as Data, not file)
            modelContext.delete(book)
            
            // Save changes
            do {
                try modelContext.save()
                AppLog.info("Successfully deleted book '\(book.name ?? "Untitled")' and its recipes", category: .recipe)
            } catch {
                AppLog.error("Failed to save after deleting book: \(error)", category: .recipe)
            }
        }
    }
    
    /// Sync community books from CloudKit to local SwiftData
    /// Only syncs if enough time has passed since the last sync
    private func syncCommunityBooksIfNeeded() async {
        // Check if we need to sync
        if let lastSync = lastSyncDate {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            if timeSinceLastSync < syncInterval {
                AppLog.info("📚 Skipping sync - last synced \(Int(timeSinceLastSync))s ago", category: .sharing)
                return
            }
        }
        
        AppLog.info("📚 Syncing community books to local SwiftData...", category: .sharing)
        
        do {
            try await CloudKitSharingService.shared.syncCommunityBooksToLocal(modelContext: modelContext)
            
            await MainActor.run {
                lastSyncDate = Date()
                refreshID = UUID() // Force UI refresh
                AppLog.info("✅ Community books sync completed successfully", category: .sharing)
            }
        } catch {
            AppLog.error("❌ Failed to sync community books: \(error)", category: .sharing)
            // Log the error but don't show it to the user
            // The sync will automatically retry next time they switch tabs
        }
    }
}

// MARK: - Book Card View

struct BookCardView: View {
    let book: Book
    let savedRecipes: [RecipeX]
    let showSharedInfo: Bool
    
    // Cache book data on init to avoid faults
    private let bookID: UUID?
    private let cachedCoverImageData: Data?
    private let cachedBookName: String
    private let cachedRecipeCount: Int
    private let cachedBookDescription: String?
    private let cachedBookColor: String?
    private let cachedOwnerDisplayName: String?
    private let cachedOwnerUserID: String?
    
    init(book: Book, savedRecipes: [RecipeX], showSharedInfo: Bool) {
        self.book = book
        self.savedRecipes = savedRecipes
        self.showSharedInfo = showSharedInfo
        
        // Cache book properties to avoid faults when object is deleted
        self.bookID = book.id
        self.cachedCoverImageData = book.coverImageData
        self.cachedBookName = book.name ?? "Untitled"
        self.cachedRecipeCount = book.recipeIDs?.count ?? 0
        self.cachedBookDescription = book.bookDescription
        self.cachedBookColor = book.color
        self.cachedOwnerDisplayName = book.ownerDisplayName
        self.cachedOwnerUserID = book.ownerUserID
    }
    
    private var bookColor: Color {
        if let colorHex = cachedBookColor {
            return Color(hex: colorHex) ?? .blue
        }
        return .blue
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image or placeholder
            ZStack {
                if let imageData = cachedCoverImageData, let uiImage = PlatformImage(data: imageData) {
                    Image(platformImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [bookColor, bookColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 220)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "book.closed.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(Color.onTint)
                                
                                Text(cachedBookName)
                                    .font(.headline)
                                    .foregroundStyle(Color.onTint)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .padding(.horizontal, 8)
                            }
                        }
                }
                
                // Recipe count badge
                VStack {
                    HStack {
                        Spacer()
                        Text("\(cachedRecipeCount)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.onTint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(8)
                    }
                    Spacer()
                }
            }
            .frame(height: 220)
            
            // Book name (if we have cover image)
            if cachedCoverImageData != nil {
                Text(cachedBookName)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            // Show who owns this book if it's shared
            if showSharedInfo, 
               let ownerName = cachedOwnerDisplayName,
               let ownerID = cachedOwnerUserID,
               ownerID != CloudKitSharingService.shared.currentUserID {
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.appInfo)
                    Text("By \(ownerName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Description
            if let description = cachedBookDescription, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


#Preview {
    RecipeBooksView()
        .modelContainer(for: [Book.self, RecipeX.self], inMemory: true)
}
