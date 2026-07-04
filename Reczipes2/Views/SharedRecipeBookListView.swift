//
//  SharedRecipeBookListView.swift
//  Reczipes2
//
//  Created on 1/25/26.
//

import SwiftUI
import SwiftData

/// View that displays recipe previews from a shared recipe book
/// Shows lightweight previews with thumbnails - full recipe downloads on-demand when tapped
struct SharedRecipeBookListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let book: Book
    let sharedEntry: SharedRecipeBook
    
    @Query private var allPreviews: [CloudKitRecipePreview]
    
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .original
    
    enum SortOrder {
        case original
        case alphabetical
        case yieldAscending
        case yieldDescending
    }
    
    // Filter previews to only those belonging to this book
    private var bookPreviews: [CloudKitRecipePreview] {
        let filtered = allPreviews.filter { $0.bookID == book.id }
        
        // Apply search filter
        let searchFiltered: [CloudKitRecipePreview]
        if searchText.isEmpty {
            searchFiltered = filtered
        } else {
            searchFiltered = filtered.filter { preview in
                preview.title.localizedCaseInsensitiveContains(searchText) ||
                (preview.headerNotes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Apply sort order
        switch sortOrder {
        case .original:
            // Maintain order from book.recipeIDs
            return book.recipeIDs?.compactMap { recipeID in
                searchFiltered.first { $0.id == recipeID }
            } ?? []
        case .alphabetical:
            return searchFiltered.sorted { $0.title < $1.title }
        case .yieldAscending:
            return searchFiltered.sorted { ($0.recipeYield ?? "") < ($1.recipeYield ?? "") }
        case .yieldDescending:
            return searchFiltered.sorted { ($0.recipeYield ?? "") > ($1.recipeYield ?? "") }
        }
    }
    
    private var bookColor: Color {
        if let colorHex = book.color {
            return Color(hex: colorHex) ?? .blue
        }
        return .blue
    }
    
    var body: some View {
        Group {
            if bookPreviews.isEmpty {
                emptyStateView
            } else {
                recipeListView
            }
        }
        .navigationTitle(book.name ?? "No Name")
        .platformNavigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search recipes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: $sortOrder) {
                        Label("Original Order", systemImage: "list.number")
                            .tag(SortOrder.original)
                        Label("Alphabetical", systemImage: "textformat.abc")
                            .tag(SortOrder.alphabetical)
                        Label("Yield (Low to High)", systemImage: "arrow.up")
                            .tag(SortOrder.yieldAscending)
                        Label("Yield (High to Low)", systemImage: "arrow.down")
                            .tag(SortOrder.yieldDescending)
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }
    
    // MARK: - Recipe List
    
    private var recipeListView: some View {
        List {
            // Book header section
            Section {
                bookHeaderView
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            
            // Recipe previews section
            Section {
                ForEach(bookPreviews) { preview in
                    NavigationLink {
                        SharedRecipeViewerView(preview: preview)
                    } label: {
                        RecipePreviewRow(preview: preview)
                    }
                }
            } header: {
                HStack {
                    Text("\(bookPreviews.count) Recipes")
                        .font(.headline)
                    Spacer()
                    if !searchText.isEmpty {
                        Text("(filtered)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .platformInsetGroupedListStyle()
    }
    
    // MARK: - Book Header
    
    private var bookHeaderView: some View {
        VStack(spacing: 16) {
            // Cover image
            if let coverImageName = book.coverImageName {
                AsyncImage(url: imageURL(for: coverImageName)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(bookColor.gradient)
                        .overlay {
                            Image(systemName: "book.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(Color.onTint.opacity(0.5))
                        }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(radius: 4)
            } else {
                Rectangle()
                    .fill(bookColor.gradient)
                    .overlay {
                        Image(systemName: "book.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.onTint.opacity(0.5))
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
            }
            
            // Book info
            VStack(spacing: 8) {
                if let description = book.bookDescription, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                HStack(spacing: 16) {
                    Label("\(String(describing: book.recipeIDs?.count))", systemImage: "list.bullet")
                    
                    if let sharedByName = sharedEntry.sharedByUserName {
                        Label(sharedByName, systemImage: "person.crop.circle")
                    }
                    
                    Label(sharedEntry.sharedDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 72))
                .foregroundStyle(bookColor)
            
            Text("No Recipes")
                .font(.title2)
                .fontWeight(.semibold)
            
            if !searchText.isEmpty {
                Text("No recipes match '\(searchText)'")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Clear Search") {
                    searchText = ""
                }
                .buttonStyle(.bordered)
            } else {
                Text("This book doesn't have any recipe previews yet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("The book owner may need to re-share it with the latest version.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
    
    // MARK: - Helper
    
    private func imageURL(for filename: String) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(filename)
    }
}

// MARK: - Recipe Preview Row

struct RecipePreviewRow: View {
    let preview: CloudKitRecipePreview
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let imageData = preview.imageData,
                   let uiImage = PlatformImage(data: imageData) {
                    Image(platformImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Recipe info
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if let headerNotes = preview.headerNotes, !headerNotes.isEmpty {
                    Text(headerNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 12) {
                    if let recipeYield = preview.recipeYield, !recipeYield.isEmpty {
                        Label(recipeYield, systemImage: "chart.bar.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let sharedByName = preview.sharedByUserName {
                        Label(sharedByName, systemImage: "person.crop.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("Shared Book with Previews") {
    let container = try! ModelContainer(for: Book.self, SharedRecipeBook.self, CloudKitRecipePreview.self)
    let context = container.mainContext
    
    // Create test book
    let book = Book(
        id: UUID(),
        name: "Italian Classics",
        bookDescription: "Traditional Italian recipes from my grandmother",
        coverImageName: nil,
        color: "#FF5733",
        recipeIDs: [UUID(), UUID(), UUID()],
        dateCreated: Date(),
        dateModified: Date()
    )
    
    let sharedEntry = SharedRecipeBook(
        bookID: book.id ?? UUID(),
        cloudRecordID: "test-record",
        sharedByUserID: "test-user",
        sharedByUserName: "Maria Rossi",
        sharedDate: Date(),
        bookName: book.name ?? "Italian Classics",
        bookDescription: book.bookDescription,
        coverImageName: nil
    )
    
    // Create test previews
    for (index, recipeID) in (book.recipeIDs ?? []).enumerated() {
        let preview = CloudKitRecipePreview(
            id: recipeID,
            title: ["Pasta Carbonara", "Margherita Pizza", "Tiramisu"][index],
            headerNotes: "A delicious classic recipe",
            imageName: nil,
            imageData: nil,
            sharedByUserID: "test-user",
            sharedByUserName: "Maria Rossi",
            recipeYield: ["4 servings", "8 slices", "6 servings"][index],
            bookID: book.id,
            cloudRecordID: nil
        )
        context.insert(preview)
    }
    
    context.insert(book)
    context.insert(sharedEntry)
    
    return NavigationStack {
        SharedRecipeBookListView(book: book, sharedEntry: sharedEntry)
    }
    .modelContainer(container)
}

#Preview("Empty Shared Book") {
    let container = try! ModelContainer(for: Book.self, SharedRecipeBook.self, CloudKitRecipePreview.self)
    let context = container.mainContext
    
    let book = Book(
        id: UUID(),
        name: "Empty Book",
        bookDescription: "This book has no recipes yet",
        coverImageName: nil,
        color: "#3498db",
        recipeIDs: [],
        dateCreated: Date(),
        dateModified: Date()
    )
    
    let sharedEntry = SharedRecipeBook(
        bookID: book.id ?? UUID(),
        cloudRecordID: "test-record",
        sharedByUserID: "test-user",
        sharedByUserName: "John Doe",
        sharedDate: Date(),
        bookName: book.name ?? "Empty Book",
        bookDescription: book.bookDescription,
        coverImageName: nil
    )
    
    context.insert(book)
    context.insert(sharedEntry)
    
    return NavigationStack {
        SharedRecipeBookListView(book: book, sharedEntry: sharedEntry)
    }
    .modelContainer(container)
}
