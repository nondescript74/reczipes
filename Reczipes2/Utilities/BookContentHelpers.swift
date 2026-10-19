//
//  BookContentHelpers.swift
//  Reczipes2
//
//  Created on 10/17/26.
//
//  Pure helpers for book content: the GENERATED index (never stored page
//  numbers), title normalisation for matching, image downscaling for book
//  pictures, and a tolerant glossary JSON decoder.
//

import UniformTypeIdentifiers
import ImageIO
import Foundation
import SwiftUI
import SwiftData

// MARK: - Generated index

/// One letter group of the generated index.
struct BookIndexSection: Identifiable, Equatable {
    let letter: String
    let entries: [BookIndexEntry]
    var id: String { letter }
}

struct BookIndexEntry: Identifiable, Equatable {
    let recipeID: UUID
    let title: String
    var id: UUID { recipeID }
}

enum BookIndexBuilder {

    /// Alphabetical index of the book's CURRENT recipes, built at view time.
    /// Titles are sorted with Finder-style comparison; titles that don't start
    /// with a letter go under "#". Duplicate ids are listed once.
    static func sections(from recipes: [(id: UUID, title: String)]) -> [BookIndexSection] {
        var seen = Set<UUID>()
        let entries = recipes.compactMap { item -> BookIndexEntry? in
            guard seen.insert(item.id).inserted else { return nil }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return BookIndexEntry(recipeID: item.id, title: title.isEmpty ? "Untitled" : title)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        var groups: [(String, [BookIndexEntry])] = []
        for entry in entries {
            let letter = indexLetter(for: entry.title)
            if let last = groups.last, last.0 == letter {
                groups[groups.count - 1].1.append(entry)
            } else {
                groups.append((letter, [entry]))
            }
        }
        // "#" first, like Contacts would put it last; keep it first for a book index
        let hash = groups.filter { $0.0 == "#" }
        let letters = groups.filter { $0.0 != "#" }
        return (hash + letters).map { BookIndexSection(letter: $0.0, entries: $0.1) }
    }

    static func indexLetter(for title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard let first = folded.unicodeScalars.first(where: { !CharacterSet.whitespaces.contains($0) }) else { return "#" }
        if CharacterSet.letters.contains(first), first.isASCII {
            return String(first).uppercased()
        }
        return "#"
    }
}

// MARK: - Title matching

enum BookTitleMatcher {

    /// Case-, accent- and punctuation-insensitive form: "Lassi (Yogurt Sherbet)!" -> "lassi yogurt sherbet"
    static func normalize(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
        var out = ""
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        // Arabic and Roman part numbers compare equal: "Gund Paak 1" == "Gund Paak I".
        // Common transliteration variants compare equal: Kabobs/Kebabs/Kababs.
        let roman = ["1": "i", "2": "ii", "3": "iii", "4": "iv", "5": "v",
                     "kabob": "kabab", "kebab": "kabab", "kabobs": "kababs", "kebabs": "kababs"]
        return out.trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map { roman[String($0)] ?? String($0) }
            .joined(separator: " ")
    }

    /// Normalised part before the first "(": "Lassi (Yogurt Sherbet)" -> "lassi". Nil when no parenthesis.
    static func baseTitle(_ title: String) -> String? {
        guard let paren = title.firstIndex(of: "(") else { return nil }
        let base = normalize(String(title[..<paren]))
        return base.isEmpty ? nil : base
    }

    /// Every normalised form a title can reasonably be known by:
    /// full title, the part before / inside a parenthesis, and the parts around a dash or colon.
    /// "Ghee (Clarified Butter)" -> {"ghee clarified butter", "ghee", "clarified butter"}
    /// "Thepla II – Jaggery Biscuits" -> {"thepla ii jaggery biscuits", "thepla ii", "jaggery biscuits"}
    static func variants(_ title: String) -> Set<String> {
        var out: Set<String> = [normalize(title)]
        if let open = title.firstIndex(of: "(") {
            out.insert(normalize(String(title[..<open])))
            let after = title[title.index(after: open)...]
            if let close = after.firstIndex(of: ")") { out.insert(normalize(String(after[..<close]))) }
        }
        for sep in [" - ", " – ", " — ", ": "] {
            let parts = title.components(separatedBy: sep)
            if parts.count == 2 {
                out.insert(normalize(parts[0]))
                out.insert(normalize(parts[1]))
            }
        }
        out.remove("")
        return out
    }

    /// Word-set similarity (Jaccard) of two normalised titles.
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Set(a.split(separator: " ")), y = Set(b.split(separator: " "))
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        return Double(x.intersection(y).count) / Double(x.union(y).count)
    }

    /// Finds the best candidate for `packageTitle`, skipping ids in `excluding`.
    /// Order: exact normalised title; any shared variant (parenthesis / dash parts);
    /// then, only when `allowFuzzy`, the single best word-overlap match >= 0.75.
    /// Among equal candidates the first in `candidates` order wins.
    static func match(_ packageTitle: String, in candidates: [(id: UUID, title: String)],
                      excluding: Set<UUID> = [], allowFuzzy: Bool = false) -> UUID? {
        let full = normalize(packageTitle)
        guard !full.isEmpty else { return nil }
        let pool = candidates.filter { !excluding.contains($0.id) }
        if let hit = pool.first(where: { normalize($0.title) == full }) { return hit.id }

        let pkgVariants = variants(packageTitle)
        if let hit = pool.first(where: { !variants($0.title).isDisjoint(with: pkgVariants) }) { return hit.id }

        guard allowFuzzy else { return nil }
        var best: (id: UUID, score: Double)?
        var tie = false
        for c in pool {
            let score = variants(c.title).flatMap { cv in pkgVariants.map { similarity($0, cv) } }.max() ?? 0
            if score >= 0.75 {
                if let b = best, abs(b.score - score) < 0.0001 { tie = true }
                else if best == nil || score > best!.score { best = (c.id, score); tie = false }
            }
        }
        return tie ? nil : best?.id
    }
}

// MARK: - Book picture downscaling

nonisolated enum BookImageProcessing {
    /// Longest side of a stored book picture
    nonisolated static let maxLongSide: CGFloat = 1600
    /// JPEG quality for stored book pictures
    nonisolated static let jpegQuality: CGFloat = 0.7

    /// Downscale to at most 1600 px on the long side and re-encode as JPEG ~0.7.
    @MainActor static func prepare(_ image: PlatformImage) -> Data? {
        guard let full = image.jpegData(compressionQuality: 1.0) else { return nil }
        return downscaledJPEG(full, maxLongSide: maxLongSide, quality: jpegQuality)
    }

    static func prepare(data: Data) -> Data? {
        downscaledJPEG(data, maxLongSide: maxLongSide, quality: jpegQuality)
    }

    /// Thread-safe downscale + JPEG encode via ImageIO (no UIKit/AppKit, no main actor).
    /// Never upscales; honours EXIF orientation.
    static func downscaledJPEG(_ data: Data, maxLongSide: CGFloat, quality: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxLongSide)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Long side of `Book.coverImageData` (list thumbnails, older clients)
    nonisolated static let coverThumbnailLongSide: CGFloat = 800

    /// List-sized JPEG copy of a cover picture (≤800 px, JPEG 0.7)
    static func coverThumbnail(from data: Data) -> Data? {
        downscaledJPEG(data, maxLongSide: coverThumbnailLongSide, quality: jpegQuality)
    }

    /// Bytes to upload for a public picture record: stored pictures are already
    /// ≤1600 px / JPEG 0.7; anything bigger (older or foreign data) is re-prepared.
    static func publicUploadData(from data: Data) -> Data {
        guard data.count > 1_000_000 else { return data }
        return prepare(data: data) ?? data
    }

    /// Total bytes of picture data in a book's images.
    static func totalBytes(_ images: [BookImage]) -> Int {
        images.reduce(0) { $0 + $1.imageData.count }
    }
}

// MARK: - Tolerant glossary decoding

/// Decodes either the app's own `[BookGlossaryEntry]` JSON or a book package's
/// glossary.json (`term`, `local_name`, `definition`, `book_page`, `order`).
struct FlexibleGlossaryEntry: Decodable {
    let term: String
    let definition: String
    let localName: String?
    let page: String?
    let order: Int?

    private enum CodingKeys: String, CodingKey {
        case term, definition, order
        case localName, local_name
        case sourcePage, book_page, page
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        term = try c.decode(String.self, forKey: .term)
        definition = (try? c.decode(String.self, forKey: .definition)) ?? ""
        let ln = (try? c.decodeIfPresent(String.self, forKey: .local_name)) ?? (try? c.decodeIfPresent(String.self, forKey: .localName))
        localName = (ln?.isEmpty ?? true) ? nil : ln
        page = Self.stringOrInt(c, .book_page) ?? Self.stringOrInt(c, .sourcePage) ?? Self.stringOrInt(c, .page)
        order = try? c.decodeIfPresent(Int.self, forKey: .order)
    }

    private static func stringOrInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return String(i) }
        return nil
    }

    /// Parse a glossary file into book entries (sorted by `order`, then file order).
    static func entries(from data: Data, now: Date = Date()) throws -> [BookGlossaryEntry] {
        let raw = try JSONDecoder().decode([FlexibleGlossaryEntry].self, from: data)
        return raw.enumerated()
            .sorted { ($0.element.order ?? $0.offset) < ($1.element.order ?? $1.offset) }
            .enumerated()
            .map { index, pair in
                let e = pair.element
                return BookGlossaryEntry(
                    id: UUID(),
                    term: e.term,
                    definition: e.definition,
                    imageData: nil,
                    relatedTerms: nil,
                    order: index,
                    dateAdded: now,
                    localName: e.localName,
                    sourcePage: e.page
                )
            }
    }
}

// MARK: - Export / import transfer of book content

enum BookContentTransfer {

    /// Copies pictures, glossary and contents from an exported book onto `book`.
    /// `recipeIDMap` (old id -> new id) remaps recipe references when an import
    /// gave recipes new ids.
    /// Pass `context` (with `book` already inserted) so pictures become
    /// `BookPicture` rows; without it they stay inline until the launch migration.
    static func apply(_ exported: ExportableBook, to book: Book, recipeIDMap: [UUID: UUID] = [:], context: ModelContext? = nil) {
        applyContent(images: exported.images, glossary: exported.glossary, tableOfContents: exported.tableOfContents,
                     to: book, recipeIDMap: recipeIDMap, context: context)
    }

    /// Same, for the import service's nested package type.
    static func apply(_ exported: RecipeBookImportService.ExportableBook, to book: Book, recipeIDMap: [UUID: UUID] = [:], context: ModelContext? = nil) {
        applyContent(images: exported.images, glossary: exported.glossary, tableOfContents: exported.tableOfContents,
                     to: book, recipeIDMap: recipeIDMap, context: context)
    }

    static func applyContent(images exportedImages: [BookImage]?, glossary exportedGlossary: [BookGlossaryEntry]?,
                             tableOfContents exportedRows: [BookSection]?,
                             to book: Book, recipeIDMap: [UUID: UUID] = [:], context: ModelContext? = nil) {
        func remap(_ id: UUID) -> UUID { recipeIDMap[id] ?? id }
        let encoder = JSONEncoder()

        if let images = exportedImages, !images.isEmpty {
            let remapped = images.map { image -> BookImage in
                var copy = image
                copy.linkedRecipeIDs = image.linkedRecipeIDs?.map(remap)
                return copy
            }
            book.setImages(remapped.filter(\.hasBytes), in: context)
            if book.coverImageData == nil, let firstCover = remapped.first(where: { $0.isCover && $0.hasBytes }) {
                book.updatePrimaryCover(from: firstCover)
            }
        }
        if let glossary = exportedGlossary, !glossary.isEmpty {
            book.glossaryData = try? encoder.encode(glossary)
        }
        if let rows = exportedRows, !rows.isEmpty {
            let remapped = rows.map { row -> BookSection in
                guard row.itemType == BookSection.recipeType else { return row }
                var copy = row
                copy.itemID = remap(row.itemID)
                return copy
            }
            book.tableOfContentsData = try? encoder.encode(remapped)
        }
    }
}
