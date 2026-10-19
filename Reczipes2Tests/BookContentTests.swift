//
//  BookContentTests.swift
//  Reczipes2Tests
//
//  Pure-logic tests for book content: generated index, title matching,
//  glossary decoding, book-package planning and old-JSON compatibility.
//

import Testing
import Foundation
import SwiftData
@testable import Reczipes2

@Suite("Book Content")
struct BookContentTests {

    // MARK: - Generated index

    @Test("Index is alphabetical, grouped by letter, built from current recipes")
    @MainActor
    func indexIsGenerated() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let sections = BookIndexBuilder.sections(from: [
            (id: a, title: "Samosas"),
            (id: b, title: "Badam Paak (Almond Sweetmeat)"),
            (id: c, title: "ambli ni Chutney"),
            (id: d, title: "7-Up Cake")
        ])
        #expect(sections.map(\.letter) == ["#", "A", "B", "S"])
        #expect(sections.flatMap(\.entries).map(\.recipeID) == [d, c, b, a])
    }

    @Test("Removing a recipe removes it from the index")
    @MainActor
    func indexFollowsMembers() {
        let a = UUID(), b = UUID()
        let before = BookIndexBuilder.sections(from: [(id: a, title: "Dhokra"), (id: b, title: "Nan")])
        let after = BookIndexBuilder.sections(from: [(id: b, title: "Nan")])
        #expect(before.flatMap(\.entries).count == 2)
        #expect(after.flatMap(\.entries).map(\.recipeID) == [b])
    }

    // MARK: - Title matching

    @Test("Normalisation ignores case, accents and punctuation")
    @MainActor
    func normalize() {
        #expect(BookTitleMatcher.normalize("Lassi (Yogurt Sherbet)!") == "lassi yogurt sherbet")
        #expect(BookTitleMatcher.normalize("Crème  Brûlée") == "creme brulee")
        #expect(BookTitleMatcher.normalize("Fish, Meat & Poultry") == "fish meat and poultry")
    }

    @Test("Matching tries the full title, then the part before a parenthesis")
    @MainActor
    func matching() {
        let lassi = UUID(), kadho = UUID(), chai = UUID()
        let library: [(id: UUID, title: String)] = [
            (id: lassi, title: "Lassi"),
            (id: kadho, title: "Kadho (Saffron Milk)"),
            (id: chai, title: "Masala Chai")
        ]
        #expect(BookTitleMatcher.match("Lassi (Yogurt Sherbet)", in: library) == lassi)
        #expect(BookTitleMatcher.match("kadho (saffron milk)", in: library) == kadho)
        #expect(BookTitleMatcher.match("Kadho", in: library) == kadho)
        #expect(BookTitleMatcher.match("Sherbet (Milk Shake)", in: library) == nil)
    }

    // MARK: - Glossary

    @Test("Package glossary.json decodes with local names and int pages")
    @MainActor
    func glossaryDecoding() throws {
        let json = """
        [{"order": 2, "term": "Burghul", "local_name": "", "definition": "Crushed wheat.", "book_page": 6},
         {"order": 1, "term": "Agar Agar", "local_name": "Chinese grass", "definition": "Sets liquids.", "book_page": 6}]
        """
        let entries = try FlexibleGlossaryEntry.entries(from: Data(json.utf8))
        #expect(entries.map(\.term) == ["Agar Agar", "Burghul"])
        #expect(entries[0].localName == "Chinese grass")
        #expect(entries[1].localName == nil)
        #expect(entries[0].sourcePage == "6")
    }

    // MARK: - Backward compatibility

    @Test("BookImage JSON written before kind/sourcePage existed still decodes as interior")
    func oldImageJSON() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","title":"Old","caption":null,"imageData":"AAEC","order":0,"dateAdded":0}]
        """
        let images = try JSONDecoder().decode([BookImage].self, from: Data(json.utf8))
        #expect(images.count == 1)
        #expect(images[0].kind == nil)
        #expect(!images[0].isCover)
    }

    // MARK: - Package planning

    @Test("Package plan: headings, recipes in section order, covers, unmatched titles")
    @MainActor
    func packagePlan() throws {
        let structureJSON = """
        {"book":"A Spicy Touch","sections":[
          {"order":1,"title":"Front cover","items":[{"type":"image","file":"01_Front_Cover.jpg"}]},
          {"order":2,"title":"Chapter 1","book_page":9,"subsections":[
             {"title":"Drinks","items":[
                {"type":"recipe","id":"NN004","title":"Lassi (Yogurt Sherbet)","page":"11"},
                {"type":"recipe","id":"NN005","title":"Kadho (Saffron Milk)","page":"11"},
                {"type":"recipe","id":"NN099","title":"Unknown Drink","page":"12"}]}],
           "images":[{"type":"image","file":"02_Photo.jpg","page":"after 11"}]}
        ],"missing":[{"page":"14-16","note":"Not photographed yet"}]}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let structure = try decoder.decode(BookPackageStructure.self, from: Data(structureJSON.utf8))

        let lassi = UUID(), kadho = UUID(), existing = UUID()
        let library: [(id: UUID, title: String)] = [(id: kadho, title: "Kadho"), (id: lassi, title: "Lassi")]
        let captions = [
            BookPackageCaption(file: "01_Front_Cover.jpg", title: "Front cover", faces: "cover", caption: "1. Kuku Paka", recipes: []),
            BookPackageCaption(file: "02_Photo.jpg", title: "Drinks", faces: "page 16", caption: "1. Lassi", recipes: ["NN004"])
        ]
        let plan = BookPackagePlanner.plan(
            structure: structure,
            captions: captions,
            indexRows: [],
            glossary: [],
            imageFiles: ["01_Front_Cover.jpg", "02_Photo.jpg"],
            imageData: { _ in Data([1, 2, 3]) },
            existingImages: [],
            members: [],
            library: library
        )
        #expect(plan.orderedRecipeIDs == [lassi, kadho])
        #expect(plan.unmatchedTitles == ["Unknown Drink"])
        #expect(plan.images.first?.isCover == true)
        #expect(plan.images.first?.caption == "Front cover\n1. Kuku Paka")
        #expect(plan.images.last?.linkedRecipeIDs == [lassi])
        #expect(plan.sections.map(\.itemType) == ["heading", "image", "heading", "heading", "recipe", "recipe", "image"])
        #expect(plan.sections[2].level == 0 && plan.sections[3].level == 1)
        #expect(plan.missingNotes == ["p. 14-16: Not photographed yet"])

        // Existing members are kept (after the package order), never removed
        let merged = BookPackagePlanner.mergedRecipeIDs(existing: [existing, kadho], packageOrder: plan.orderedRecipeIDs)
        #expect(merged == [lassi, kadho, existing])
    }

    @Test("CSV index parser handles quoted commas")
    @MainActor
    func csvParser() {
        let csv = "title,page,id,chapter,note\nAlmond Brittle,98,NN104,Sweets & Desserts,\"variation — see Pistachio, Sesame\"\nKachumber,13,NN009,\"Soups, Drinks\",\n"
        let rows = BookPackagePlanner.parseIndexCSV(csv)
        #expect(rows.count == 2)
        #expect(rows[1].title == "Kachumber")
        #expect(rows[1].chapter == "Soups, Drinks")
    }

    @Test("Covers are files starting 01_ or 07_")
    @MainActor
    func coverFiles() {
        #expect(BookPackagePlanner.isCoverFile("01_Front_Cover.jpg"))
        #expect(BookPackagePlanner.isCoverFile("07_Back_Cover.jpg"))
        #expect(!BookPackagePlanner.isCoverFile("02_Photo_Snacks_and_Drinks.jpg"))
    }

    // MARK: - Pictures as records

    @MainActor
    private func picture(_ bytes: Int, kind: String? = nil, file: String? = nil, order: Int = 0) -> BookImage {
        BookImage(id: UUID(), title: "Picture \(order)", caption: "Caption \(order)",
                  imageData: Data(repeating: UInt8(order % 255), count: bytes),
                  order: order, dateAdded: Date(timeIntervalSinceReferenceDate: 0),
                  kind: kind, sourceFile: file)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Book.self, BookPicture.self, configurations: config)
    }

    @Test("Metadata-only picture JSON stays small and still decodes as [BookImage]")
    @MainActor
    func metadataJSONIsSmall() throws {
        let images = (0..<7).map { picture(400_000, kind: $0 < 2 ? BookImage.coverKind : nil, order: $0) }
        let inline = try JSONEncoder().encode(images)
        let metadata = try #require(BookPictureStore.metadataJSON(for: images))
        #expect(inline.count > 3_000_000)
        #expect(metadata.count < 4_000)
        let decoded = try JSONDecoder().decode([BookImage].self, from: metadata)
        #expect(decoded.map(\.id) == images.map(\.id))
        #expect(decoded.allSatisfy { $0.imageData.isEmpty })
        #expect(decoded.filter(\.isCover).count == 2)
    }

    @Test("Published picture metadata decodes with old [BookImage] decoders and names its record")
    @MainActor
    func publishedMetadataIsCompatible() throws {
        let bookID = UUID()
        let image = picture(1_000, kind: BookImage.coverKind)
        let name = BookPicturePublisher.recordName(bookID: bookID, pictureID: image.id)
        let meta = BookPictureMetadata(image: image, recordName: name)
        let data = try JSONEncoder().encode([meta])
        let old = try JSONDecoder().decode([BookImage].self, from: data)
        #expect(old.first?.id == image.id)
        #expect(old.first?.imageData.isEmpty == true)
        #expect(old.first?.isCover == true)
        #expect(String(decoding: data, as: UTF8.self).contains(name))
        #expect(data.count < 1_000)
    }

    @Test("Migration plan skips pictures that already have a row (by id or source file)")
    @MainActor
    func migrationPlanIsIdempotent() throws {
        let a = picture(10, order: 0), b = picture(10, file: "02_Photo.jpg", order: 1), c = picture(10, order: 2)
        let metaOnly = BookImage(id: UUID(), title: nil, caption: nil, imageData: Data(), order: 3, dateAdded: Date())
        let data = try JSONEncoder().encode([a, b, c, metaOnly])
        let plan = try #require(BookPictureMigration.plan(inline: data, existingIDs: [a.id], existingSourceFiles: ["02_Photo.jpg"]))
        #expect(plan.newRows.map(\.id) == [c.id])
        #expect(plan.metadata.count == 4)
        #expect(plan.metadata.allSatisfy { $0.imageData.isEmpty })
    }

    @Test("Undecodable picture JSON is left alone")
    @MainActor
    func migrationPlanRejectsGarbage() {
        #expect(BookPictureMigration.plan(inline: Data("not json".utf8), existingIDs: [], existingSourceFiles: []) == nil)
    }

    @Test("Launch migration moves inline pictures into records, once")
    @MainActor
    func migrationMovesInlinePictures() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let images = [picture(5_000, kind: BookImage.coverKind, order: 0), picture(6_000, order: 1)]
        let book = Book(name: "Inline Book")
        book.imagesData = try JSONEncoder().encode(images)
        context.insert(book)
        try context.save()

        let first = BookPictureMigration.migrateAll(in: context)
        #expect(first.picturesCreated == 2)
        #expect(first.undecodable == 0)
        let bookID = try #require(book.id)
        #expect(BookPictureStore.count(bookID: bookID, in: context) == 2)
        let stored = try JSONDecoder().decode([BookImage].self, from: try #require(book.imagesData))
        #expect(stored.allSatisfy { $0.imageData.isEmpty })
        #expect(book.images.map(\.imageData) == images.map(\.imageData))
        #expect(book.coverImages.count == 1)

        let second = BookPictureMigration.migrateAll(in: context)
        #expect(second.picturesCreated == 0)
        #expect(BookPictureStore.count(bookID: bookID, in: context) == 2)
    }

    @Test("Undecodable inline pictures are kept, not lost")
    @MainActor
    func migrationKeepsUndecodableData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let garbage = Data("{broken".utf8)
        let book = Book(name: "Broken")
        book.imagesData = garbage
        context.insert(book)
        try context.save()
        let result = BookPictureMigration.migrateAll(in: context)
        #expect(result.undecodable == 1)
        #expect(book.imagesData == garbage)
    }

    @Test("setImagesUpdatingPrimaryCover writes records; deleting the book deletes them, never recipes")
    @MainActor
    func pictureRecordsFollowTheBook() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let recipeID = UUID()
        let book = Book(name: "Records", recipeIDs: [recipeID])
        context.insert(book)
        let images = [picture(2_000, order: 0), picture(3_000, kind: BookImage.coverKind, order: 1)]
        book.setImagesUpdatingPrimaryCover(images, in: context)
        try context.save()
        let bookID = try #require(book.id)
        #expect(BookPictureStore.count(bookID: bookID, in: context) == 2)
        #expect((book.imagesData?.count ?? 0) < 2_000)

        // Edit: drop one picture, change a caption -> rows follow
        var edited = book.images.filter(\.isCover)
        edited[0].caption = "New caption"
        book.setImagesUpdatingPrimaryCover(edited, in: context)
        try context.save()
        #expect(BookPictureStore.count(bookID: bookID, in: context) == 1)
        #expect(book.images.first?.caption == "New caption")

        BookPictureStore.deleteBook(book, in: context)
        try context.save()
        #expect(BookPictureStore.count(bookID: bookID, in: context) == 0)
    }
}

