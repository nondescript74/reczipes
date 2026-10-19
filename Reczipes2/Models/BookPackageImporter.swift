//
//  BookPackageImporter.swift
//  Reczipes2
//
//  Created on 10/17/26.
//
//  "Import Book Package…" — reads a folder laid out like NNimji_book1:
//
//    book_structure.json      sections (chapters → sub-headings → items) in book order
//    glossary.json            [{order, term, local_name, definition, book_page}]  (optional)
//    recipe_index.csv         title,page,id,chapter,note                          (optional)
//    Book_Images/captions.json [{file, title, faces, caption, recipes:[NN ids]}]    (optional)
//    Book_Images/*.jpg        pictures; 01_* and 07_* are covers, the rest interior
//
//  Package recipes are matched to library RecipeX by normalised title (book
//  members first, then the whole library). Matched recipes are ADDED to the
//  book in section order; existing members are never removed. The printed
//  index (page numbers) is NOT stored — the app generates its index live.
//

import Foundation
import SwiftData

// MARK: - Package file formats

/// Decodes a JSON value that may be a string, an integer or a number.
struct LossyString: Decodable, Equatable {
    let value: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = nil }
        else if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = String(i) }
        else if let d = try? c.decode(Double.self) { value = String(d) }
        else { value = nil }
    }
}

struct BookPackageStructure: Decodable {
    let book: String?
    let author: String?
    let published: String?
    let cover: String?
    let sections: [BookPackageSection]
    let missing: [BookPackageMissing]?
}

struct BookPackageSection: Decodable {
    let order: Int?
    let title: String
    let bookPage: LossyString?
    let items: [BookPackageItem]?
    let images: [BookPackageItem]?
    let subsections: [BookPackageSection]?
}

struct BookPackageItem: Decodable {
    let type: String
    let id: String?
    let title: String?
    let page: LossyString?
    let file: String?
}

struct BookPackageMissing: Decodable {
    let page: LossyString?
    let note: String?
}

struct BookPackageCaption: Decodable {
    let file: String
    let title: String?
    let faces: String?
    let caption: String?
    let recipes: [String]?
}

struct BookPackageIndexRow: Equatable {
    let title: String
    let page: String
    let id: String
    let chapter: String
}

// MARK: - Result

struct BookPackageImportSummary {
    var bookTitle: String?
    var matchedRecipes = 0
    var addedToBook = 0
    var sectionRows = 0
    var imagesStored = 0
    var coverCount = 0
    var glossaryEntries = 0
    var unmatchedTitles: [String] = []
    var missingNotes: [String] = []
    var warnings: [String] = []

    var text: String {
        var lines: [String] = []
        if let bookTitle { lines.append(bookTitle) }
        lines.append("Matched \(matchedRecipes) recipes (\(addedToBook) newly added to the book).")
        lines.append("Contents: \(sectionRows) rows. Pictures: \(imagesStored) (\(coverCount) covers).")
        lines.append(glossaryEntries > 0 ? "Glossary: \(glossaryEntries) terms." : "No glossary in package.")
        if !unmatchedTitles.isEmpty {
            lines.append("\nNot found in your library (\(unmatchedTitles.count)):\n" + unmatchedTitles.joined(separator: "\n"))
        }
        if !missingNotes.isEmpty {
            lines.append("\nPackage notes:\n" + missingNotes.joined(separator: "\n"))
        }
        if !warnings.isEmpty {
            lines.append("\nWarnings:\n" + warnings.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Pure planning

struct BookPackagePlan {
    var orderedRecipeIDs: [UUID] = []
    var sections: [BookSection] = []
    var images: [BookImage] = []
    var glossary: [BookGlossaryEntry] = []
    var unmatchedTitles: [String] = []
    var missingNotes: [String] = []
}

enum BookPackagePlanner {

    /// Covers are files whose name starts with 01_ or 07_.
    static func isCoverFile(_ fileName: String) -> Bool {
        fileName.hasPrefix("01_") || fileName.hasPrefix("07_")
    }

    /// First integer in a page string: "after 16" -> 16, "20-26" -> 20.
    static func firstPageNumber(_ page: String?) -> Int? {
        guard let page else { return nil }
        var digits = ""
        for ch in page {
            if ch.isNumber { digits.append(ch) } else if !digits.isEmpty { break }
        }
        return Int(digits)
    }

    /// Parse recipe_index.csv (title,page,id,chapter,note) with quoted fields.
    static func parseIndexCSV(_ text: String) -> [BookPackageIndexRow] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var chars = Array(text)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(ch) }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == "," {
                row.append(field); field = ""
            } else if ch == "\n" || ch == "\r\n" || ch == "\r" {
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else {
                field.append(ch)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) else { return [] }
        func col(_ name: String) -> Int? { header.firstIndex(of: name) }
        guard let t = col("title") else { return [] }
        let p = col("page"), d = col("id"), c = col("chapter")
        return rows.dropFirst().compactMap { r in
            func v(_ idx: Int?) -> String { guard let idx, idx < r.count else { return "" }; return r[idx] }
            let title = v(t).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return BookPackageIndexRow(title: title, page: v(p), id: v(d), chapter: v(c))
        }
    }

    /// Builds the plan. `imageData(file)` returns prepared (downscaled) JPEG data or nil.
    static func plan(
        structure: BookPackageStructure,
        captions: [BookPackageCaption],
        indexRows: [BookPackageIndexRow],
        glossary: [BookGlossaryEntry],
        imageFiles: [String],
        imageData: (String) -> Data?,
        existingImages: [BookImage],
        members: [(id: UUID, title: String)],
        library: [(id: UUID, title: String)],
        now: Date = Date()
    ) -> BookPackagePlan {
        var plan = BookPackagePlan()
        plan.glossary = glossary

        // --- recipe matching (book members first, then library) ---
        var matchedByPackageID: [String: UUID] = [:]
        var unmatched: [String] = []
        var usedIDs: Set<UUID> = []
        func resolve(packageID: String?, title: String) -> UUID? {
            if let packageID, let hit = matchedByPackageID[packageID] { return hit }
            let hit = BookTitleMatcher.match(title, in: members, excluding: usedIDs, allowFuzzy: true)
                ?? BookTitleMatcher.match(title, in: library, excluding: usedIDs)
            if let hit {
                usedIDs.insert(hit)
                if let packageID { matchedByPackageID[packageID] = hit }
            } else if !unmatched.contains(title) {
                unmatched.append(title)
            }
            return hit
        }

        // --- images ---
        let captionByFile = Dictionary(captions.map { ($0.file, $0) }, uniquingKeysWith: { a, _ in a })
        let titleByPackageID: [String: String] = {
            var map: [String: String] = [:]
            for row in indexRows where !row.id.isEmpty { map[row.id] = row.title }
            func walk(_ s: BookPackageSection) {
                for item in (s.items ?? []) where item.type == "recipe" {
                    if let id = item.id, let title = item.title { map[id] = title }
                }
                s.subsections?.forEach(walk)
            }
            structure.sections.forEach(walk)
            return map
        }()

        // Files to import: captions.json order when present, else every image file
        // except legend scans.
        let files: [String] = captions.isEmpty
            ? imageFiles.filter { !$0.lowercased().contains("_legend") }.sorted()
            : captions.map(\.file)

        var imageIDByFile: [String: UUID] = [:]
        // Resolve section recipes first so captions can link to them by id.
        func preResolve(_ s: BookPackageSection) {
            for item in (s.items ?? []) where item.type == "recipe" {
                if let title = item.title { _ = resolve(packageID: item.id, title: title) }
            }
            s.subsections?.forEach(preResolve)
        }
        structure.sections.sorted { ($0.order ?? 0) < ($1.order ?? 0) }.forEach(preResolve)

        for (index, file) in files.enumerated() {
            guard let data = imageData(file) else { continue }
            let cap = captionByFile[file]
            let title = cap?.title ?? (file as NSString).deletingPathExtension
            let captionText: String? = {
                guard let text = cap?.caption, !text.isEmpty else { return title }
                return "\(title)\n\(text)"
            }()
            let linked: [UUID] = (cap?.recipes ?? []).compactMap { ref in
                if ref.hasPrefix("missing:") { return nil }
                if let hit = matchedByPackageID[ref] { return hit }
                if let t = titleByPackageID[ref] { return resolve(packageID: ref, title: t) }
                return nil
            }
            let id = existingImages.first(where: { $0.sourceFile == file })?.id ?? UUID()
            imageIDByFile[file] = id
            plan.images.append(BookImage(
                id: id,
                title: title,
                caption: captionText,
                imageData: data,
                order: index,
                dateAdded: now,
                kind: isCoverFile(file) ? BookImage.coverKind : BookImage.interiorKind,
                sourcePage: cap?.faces,
                linkedRecipeIDs: linked.isEmpty ? nil : linked,
                sourceFile: file
            ))
        }
        // Covers first (01 front, 07 back), then interior in file order
        plan.images = plan.images.filter(\.isCover) + plan.images.filter { !$0.isCover }

        // --- sections ---
        var order = 0
        var ordered: [UUID] = []
        func row(_ title: String, _ type: String, _ itemID: UUID, level: Int? = nil, page: String? = nil) -> BookSection {
            defer { order += 1 }
            return BookSection(id: UUID(), title: title, order: order, itemType: type, itemID: itemID, level: level, sourcePage: page)
        }
        /// Rows for one list of items, each with its first page number (for image placement)
        func itemRows(_ items: [BookPackageItem]) -> [(BookSection, Int?)] {
            items.compactMap { item in
                switch item.type {
                case "recipe":
                    guard let title = item.title,
                          let rid = resolve(packageID: item.id, title: title) else { return nil }
                    if !ordered.contains(rid) { ordered.append(rid) }
                    let libTitle = (members + library).first(where: { $0.id == rid })?.title ?? title
                    return (row(libTitle, BookSection.recipeType, rid, page: item.page?.value), firstPageNumber(item.page?.value))
                case "image":
                    guard let file = item.file, let iid = imageIDByFile[file] else { return nil }
                    let t = captionByFile[file]?.title ?? file
                    return (row(t, BookSection.imageType, iid, page: item.page?.value), firstPageNumber(item.page?.value))
                case "glossary":
                    guard !glossary.isEmpty else { return nil }
                    return (row("Glossary", BookSection.glossaryType, UUID(), page: item.page?.value), nil)
                case "index":
                    return (row("Index", BookSection.indexType, UUID(), page: item.page?.value), nil)
                default:
                    return nil
                }
            }
        }

        for section in structure.sections.sorted(by: { ($0.order ?? 0) < ($1.order ?? 0) }) {
            var chapter: [(BookSection, Int?)] = []
            chapter.append((row(section.title, BookSection.headingType, UUID(), level: 0, page: section.bookPage?.value), nil))
            chapter += itemRows(section.items ?? [])
            for sub in section.subsections ?? [] {
                chapter.append((row(sub.title, BookSection.headingType, UUID(), level: 1, page: sub.bookPage?.value), nil))
                chapter += itemRows(sub.items ?? [])
            }
            // Chapter pictures go after the last row on or before their page
            for imageItem in section.images ?? [] {
                guard let rowPair = itemRows([imageItem]).first else { continue }
                let page = firstPageNumber(imageItem.page?.value)
                var insertAt = chapter.count
                if let page, let last = chapter.lastIndex(where: { ($0.1 ?? Int.min) <= page && $0.1 != nil }) {
                    insertAt = last + 1
                }
                chapter.insert(rowPair, at: insertAt)
            }
            plan.sections += chapter.map { $0.0 }
        }
        // Re-number after insertions
        plan.sections = plan.sections.enumerated().map { i, s in var c = s; c.order = i; return c }

        plan.orderedRecipeIDs = ordered
        plan.unmatchedTitles = unmatched
        plan.missingNotes = (structure.missing ?? []).compactMap { m in
            guard let note = m.note else { return nil }
            if let p = m.page?.value { return "p. \(p): \(note)" }
            return note
        }
        return plan
    }

    /// New member order: package recipes in section order, then any existing
    /// members the package did not mention (never removed).
    static func mergedRecipeIDs(existing: [UUID], packageOrder: [UUID]) -> [UUID] {
        var result: [UUID] = []
        for id in packageOrder where !result.contains(id) { result.append(id) }
        for id in existing where !result.contains(id) { result.append(id) }
        return result
    }

    /// Package images replace earlier imports of the same file; other pictures are kept after them.
    static func mergedImages(existing: [BookImage], package: [BookImage]) -> [BookImage] {
        let files = Set(package.compactMap(\.sourceFile))
        let kept = existing.filter { img in
            guard let f = img.sourceFile else { return true }
            return !files.contains(f)
        }
        let all = package + kept
        return all.filter(\.isCover) + all.filter { !$0.isCover }
    }
}

// MARK: - Import from a folder

enum BookPackageImporter {

    enum ImportError: LocalizedError {
        case missingStructure
        var errorDescription: String? {
            "This folder has no book_structure.json, so it is not a book package."
        }
    }

    /// Reads the package at `folder` and applies it to `book`. Caller has security-scoped access.
    static func importPackage(at folder: URL, into book: Book, context: ModelContext) throws -> BookPackageImportSummary {
        let fm = FileManager.default
        let structureURL = folder.appendingPathComponent("book_structure.json")
        guard fm.fileExists(atPath: structureURL.path) else { throw ImportError.missingStructure }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let structure = try decoder.decode(BookPackageStructure.self, from: Data(contentsOf: structureURL))

        var summary = BookPackageImportSummary(bookTitle: structure.book)

        // Glossary (optional)
        var glossary: [BookGlossaryEntry] = []
        let glossaryURL = folder.appendingPathComponent("glossary.json")
        if fm.fileExists(atPath: glossaryURL.path) {
            do { glossary = try FlexibleGlossaryEntry.entries(from: Data(contentsOf: glossaryURL)) }
            catch { summary.warnings.append("glossary.json could not be read: \(error.localizedDescription)") }
        }

        // Index CSV (optional; only used to map ids to titles — the app's index is generated)
        var indexRows: [BookPackageIndexRow] = []
        let csvURL = folder.appendingPathComponent("recipe_index.csv")
        if let text = try? String(contentsOf: csvURL, encoding: .utf8) {
            indexRows = BookPackagePlanner.parseIndexCSV(text)
        }

        // Images + captions (optional)
        let imagesDir = folder.appendingPathComponent("Book_Images")
        var captions: [BookPackageCaption] = []
        let captionsURL = imagesDir.appendingPathComponent("captions.json")
        if fm.fileExists(atPath: captionsURL.path) {
            do { captions = try JSONDecoder().decode([BookPackageCaption].self, from: Data(contentsOf: captionsURL)) }
            catch { summary.warnings.append("captions.json could not be read: \(error.localizedDescription)") }
        }
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
        let imageFiles = ((try? fm.contentsOfDirectory(atPath: imagesDir.path)) ?? [])
            .filter { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }

        // Library
        let allRecipes = try context.fetch(FetchDescriptor<RecipeX>(sortBy: [SortDescriptor(\.dateAdded)]))
        let library: [(id: UUID, title: String)] = allRecipes.compactMap { r in
            guard let id = r.id else { return nil }
            return (id: id, title: r.title ?? "")
        }
        let memberSet = Set(book.recipeIDs ?? [])
        let members = (book.recipeIDs ?? []).compactMap { id in library.first(where: { $0.id == id }) }

        var failedImages: [String] = []
        let plan = BookPackagePlanner.plan(
            structure: structure,
            captions: captions,
            indexRows: indexRows,
            glossary: glossary,
            imageFiles: imageFiles,
            imageData: { file in
                let url = imagesDir.appendingPathComponent(file)
                guard let raw = try? Data(contentsOf: url),
                      let prepared = BookImageProcessing.prepare(data: raw) else {
                    failedImages.append(file)
                    return nil
                }
                return prepared
            },
            existingImages: book.pictures(in: context),
            members: members,
            library: library
        )

        // Apply — members are only ever added / reordered, never removed
        let merged = BookPackagePlanner.mergedRecipeIDs(existing: book.recipeIDs ?? [], packageOrder: plan.orderedRecipeIDs)
        book.recipeIDs = merged
        if !plan.images.isEmpty {
            // Pictures are BookPicture records; a re-import replaces the same source files
            book.setImagesUpdatingPrimaryCover(
                BookPackagePlanner.mergedImages(existing: book.pictures(in: context), package: plan.images),
                in: context
            )
        }
        if !plan.glossary.isEmpty {
            book.setGlossary(plan.glossary)
        }
        book.setTableOfContents(plan.sections)
        if (book.bookDescription ?? "").isEmpty {
            let parts = [structure.author, structure.published].compactMap { $0 }.filter { !$0.isEmpty }
            if !parts.isEmpty { book.bookDescription = parts.joined(separator: " · ") }
        }
        book.markModified()
        try context.save()

        summary.matchedRecipes = plan.orderedRecipeIDs.count
        summary.addedToBook = plan.orderedRecipeIDs.filter { !memberSet.contains($0) }.count
        summary.sectionRows = plan.sections.count
        summary.imagesStored = plan.images.count
        summary.coverCount = plan.images.filter(\.isCover).count
        summary.glossaryEntries = plan.glossary.count
        summary.unmatchedTitles = plan.unmatchedTitles
        summary.missingNotes = plan.missingNotes
        if !failedImages.isEmpty { summary.warnings.append("Could not read pictures: \(failedImages.joined(separator: ", "))") }
        AppLog.info("📚 Imported book package into '\(book.displayName)': \(summary.matchedRecipes) recipes, \(summary.imagesStored) pictures, \(summary.glossaryEntries) glossary terms, \(summary.unmatchedTitles.count) unmatched", category: .recipe)
        return summary
    }
}

enum BookContentLimits {
    /// Bytes of picture data above which a single CloudKit record (1 MB limit for
    /// non-asset fields) can no longer carry the pictures inline.
    nonisolated static let cloudKitPictureBudget = 600_000
}
