//
//  BookContentViews.swift
//  Reczipes2
//
//  Created on 10/17/26.
//
//  Book viewer tabs beside the recipe pager: Contents, Pictures, Glossary, Index.
//  The Index is generated from the book's CURRENT recipes every time it is shown
//  (alphabetical by title) — no stored page numbers.
//

import SwiftUI

/// Tabs of the book viewer
enum BookViewMode: String, CaseIterable, Identifiable {
    case recipes = "Recipes"
    case contents = "Contents"
    case pictures = "Pictures"
    case glossary = "Glossary"
    case index = "Index"
    var id: String { rawValue }
}

// MARK: - Contents

struct BookContentsView: View {
    let book: Book
    /// The book's current recipes, in member order
    let recipes: [RecipeX]
    let bookColor: Color
    let onOpenRecipe: (UUID) -> Void
    let onOpenMode: (BookViewMode) -> Void

    @State private var zoomImage: BookImage?

    private struct Row: Identifiable {
        let id: UUID
        let section: BookSection
    }

    /// Stored contents filtered to what is still in the book, plus any members the
    /// contents don't mention yet. Falls back to plain recipe order.
    private var rows: [Row] {
        let memberIDs = Set(recipes.compactMap(\.id))
        let imageIDs = Set(book.images.map(\.id))
        let stored = book.tableOfContents.sorted { $0.order < $1.order }
        var result: [BookSection] = stored.filter { s in
            switch s.itemType {
            case BookSection.recipeType: return memberIDs.contains(s.itemID)
            case BookSection.imageType:  return imageIDs.contains(s.itemID)
            case BookSection.glossaryType: return !book.glossary.isEmpty
            default: return true
            }
        }
        let listed = Set(result.filter { $0.itemType == BookSection.recipeType }.map(\.itemID))
        let unlisted = recipes.filter { r in r.id.map { !listed.contains($0) } ?? false }
        if !unlisted.isEmpty {
            if !result.isEmpty {
                result.append(BookSection(id: UUID(), title: "More Recipes", order: Int.max, itemType: BookSection.headingType, itemID: UUID(), level: 0))
            }
            for r in unlisted {
                result.append(BookSection(id: UUID(), title: r.title ?? "Untitled", order: Int.max, itemType: BookSection.recipeType, itemID: r.safeID))
            }
        }
        return result.map { Row(id: $0.id, section: $0) }
    }

    var body: some View {
        List {
            ForEach(rows) { row in
                rowView(row.section)
            }
        }
        .sheet(item: $zoomImage) { image in
            BookImageZoomView(image: image)
                .macOSSheetFrame()
        }
    }

    @ViewBuilder
    private func rowView(_ s: BookSection) -> some View {
        switch s.itemType {
        case BookSection.headingType:
            Text(s.title)
                .font((s.level ?? 0) == 0 ? Font.title3.weight(.bold) : Font.headline)
                .foregroundStyle((s.level ?? 0) == 0 ? bookColor : Color.primary)
                .padding(.top, (s.level ?? 0) == 0 ? 8 : 2)
                .padding(.leading, CGFloat(s.level ?? 0) * 12)
        case BookSection.recipeType:
            Button {
                onOpenRecipe(s.itemID)
            } label: {
                HStack {
                    Text(recipes.first(where: { $0.id == s.itemID })?.title ?? s.title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case BookSection.imageType:
            if let image = book.images.first(where: { $0.id == s.itemID }) {
                Button {
                    zoomImage = image
                } label: {
                    HStack(spacing: 12) {
                        BookImageThumbnail(image: image, size: 56)
                        Text(image.title ?? s.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                }
                .buttonStyle(.plain)
            }
        case BookSection.glossaryType:
            Button { onOpenMode(.glossary) } label: {
                Label(s.title, systemImage: "character.book.closed")
            }
        case BookSection.indexType:
            Button { onOpenMode(.index) } label: {
                Label(s.title, systemImage: "list.bullet.indent")
            }
        default:
            Text(s.title)
        }
    }
}

// MARK: - Pictures

struct BookPicturesView: View {
    let book: Book

    @State private var zoomImage: BookImage?

    var body: some View {
        let covers = book.coverImages
        let interior = book.interiorImages
        Group {
            if covers.isEmpty && interior.isEmpty {
                ContentUnavailableView("No Pictures", systemImage: "photo.on.rectangle",
                                       description: Text("Add covers and pictures in Edit Book."))
            } else {
                List {
                    if !covers.isEmpty {
                        Section("Covers") {
                            ForEach(covers) { pictureRow($0) }
                        }
                    }
                    if !interior.isEmpty {
                        Section("Pictures") {
                            ForEach(interior) { pictureRow($0) }
                        }
                    }
                }
            }
        }
        .sheet(item: $zoomImage) { image in
            BookImageZoomView(image: image)
                .macOSSheetFrame()
        }
    }

    private func pictureRow(_ image: BookImage) -> some View {
        Button {
            zoomImage = image
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let platformImage = PlatformImage(data: image.imageData) {
                    Image(platformImage: platformImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if let caption = image.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                } else if let title = image.title {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
                if let page = image.sourcePage, !page.isEmpty {
                    Text(page.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

/// Small square thumbnail of a book picture
struct BookImageThumbnail: View {
    let image: BookImage
    let size: CGFloat

    var body: some View {
        Group {
            if let platformImage = PlatformImage(data: image.imageData) {
                Image(platformImage: platformImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Full-screen picture with pinch / double-tap zoom and the caption below.
struct BookImageZoomView: View {
    let image: BookImage

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    if let platformImage = PlatformImage(data: image.imageData) {
                        Image(platformImage: platformImage)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { value in scale = max(1, min(6, lastScale * value.magnification)) }
                                    .onEnded { _ in lastScale = scale }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation {
                                    scale = scale > 1 ? 1 : 2.5
                                    lastScale = scale
                                }
                            }
                    }
                }
                if let caption = image.caption, !caption.isEmpty {
                    ScrollView {
                        Text(caption)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(maxHeight: 180)
                }
            }
            .navigationTitle(image.title ?? "Picture")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Glossary

struct BookGlossaryView: View {
    let entries: [BookGlossaryEntry]

    @State private var searchText = ""

    private var filtered: [BookGlossaryEntry] {
        let sorted = entries.sorted { $0.order < $1.order }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sorted }
        return sorted.filter {
            $0.term.localizedCaseInsensitiveContains(q) ||
            ($0.localName ?? "").localizedCaseInsensitiveContains(q) ||
            $0.definition.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        List {
            Section {
                TextField("Search glossary", text: $searchText)
                    .autocorrectionDisabled()
            }
            ForEach(filtered) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry.term)
                            .font(.headline)
                        if let local = entry.localName, !local.isEmpty {
                            Text("— \(local)")
                                .font(.subheadline)
                                .italic()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(entry.definition)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Index (generated)

struct BookIndexView: View {
    /// The book's current recipes; the index is rebuilt from these every time
    let recipes: [RecipeX]
    let onOpenRecipe: (UUID) -> Void

    private var sections: [BookIndexSection] {
        BookIndexBuilder.sections(from: recipes.compactMap { r in
            r.id.map { (id: $0, title: r.title ?? "") }
        })
    }

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(section.letter) {
                    ForEach(section.entries) { entry in
                        Button {
                            onOpenRecipe(entry.recipeID)
                        } label: {
                            Text(entry.title)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
