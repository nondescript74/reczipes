//
//  StoreSplitTests.swift
//  Reczipes2Tests
//
//  Δ-223: the community caches move to their own on-device store. These tests open a
//  real on-disk database in the old single-store layout, then reopen it with the
//  production two-store code (ModelContainerManager.makeSplitContainer, CloudKit off),
//  and check nothing of the library is lost — and that the old layout still opens
//  afterwards (the app's fallback when the two-store container cannot open).
//

import Testing
import Foundation
import SwiftData
@testable import Reczipes2

@Suite("Store split — library vs community caches", .serialized)
@MainActor
struct StoreSplitTests {

    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "StoreSplitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Today's layout: every model in one store (the app's single-store path, CloudKit off).
    private func openSingleStore(_ url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(ModelContainerManager.syncedModels + ModelContainerManager.communityCacheModels),
            migrationPlan: Reczipes2MigrationPlan.self,
            configurations: [ModelConfiguration(url: url, cloudKitDatabase: .none)]
        )
    }

    private func preview(_ title: String) -> CloudKitRecipePreview {
        CloudKitRecipePreview(id: UUID(), title: title, sharedByUserID: "someone")
    }

    @Test("An existing library survives the move to two stores")
    func libraryKept() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let libraryURL = folder.appending(path: "CloudKitModel.sqlite")
        let cacheURL = folder.appending(path: "CommunityCache.sqlite")

        // 1. Old layout: a recipe, a book and a cached community preview in one store.
        do {
            let old = try openSingleStore(libraryURL)
            let context = ModelContext(old)
            context.insert(RecipeX(title: "Kept Recipe"))
            context.insert(Book(name: "Kept Book"))
            context.insert(preview("Old Cache Entry"))
            try context.save()
        }

        // 2. New layout, production code: library intact, cache store starts empty.
        do {
            let split = try ModelContainerManager.makeSplitContainer(libraryURL: libraryURL, cacheURL: cacheURL,
                                                                     privateDatabase: nil)
            let context = ModelContext(split)
            let recipes = try context.fetch(FetchDescriptor<RecipeX>())
            #expect(recipes.map(\.title) == ["Kept Recipe"])
            #expect(try context.fetchCount(FetchDescriptor<Book>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<CloudKitRecipePreview>()) == 0)

            context.insert(preview("New Cache Entry"))
            context.insert(RecipeX(title: "Second Recipe"))
            try context.save()
        }
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))

        // 3. Reopen: each kind stayed in its own store.
        do {
            let split = try ModelContainerManager.makeSplitContainer(libraryURL: libraryURL, cacheURL: cacheURL,
                                                                     privateDatabase: nil)
            let context = ModelContext(split)
            #expect(try context.fetchCount(FetchDescriptor<RecipeX>()) == 2)
            #expect(try context.fetch(FetchDescriptor<CloudKitRecipePreview>()).map(\.title) == ["New Cache Entry"])
        }
    }

    @Test("After the move, the old single-store layout still opens (the app's fallback)")
    func fallbackStillOpens() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let libraryURL = folder.appending(path: "CloudKitModel.sqlite")
        let cacheURL = folder.appending(path: "CommunityCache.sqlite")

        do {
            let context = ModelContext(try openSingleStore(libraryURL))
            context.insert(RecipeX(title: "Kept Recipe"))
            try context.save()
        }
        do {
            _ = try ModelContainerManager.makeSplitContainer(libraryURL: libraryURL, cacheURL: cacheURL,
                                                             privateDatabase: nil)
        }
        do {
            let context = ModelContext(try openSingleStore(libraryURL))
            #expect(try context.fetch(FetchDescriptor<RecipeX>()).map(\.title) == ["Kept Recipe"])
        }
    }

    @Test("Caches and synced models do not overlap")
    func modelListsDisjoint() {
        let synced = Set(ModelContainerManager.syncedModels.map { ObjectIdentifier($0) })
        let caches = Set(ModelContainerManager.communityCacheModels.map { ObjectIdentifier($0) })
        #expect(synced.isDisjoint(with: caches))
        #expect(caches.count == 3)
    }
}
