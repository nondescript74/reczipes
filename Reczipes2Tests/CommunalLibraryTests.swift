//
//  CommunalLibraryTests.swift
//  Reczipes2Tests
//
//  Tests for the communal recipe library opt-in (SharingPreferences.browseCommunity).
//  See Docs/COMMUNAL_LIBRARY_SPEC.md.
//  Created on 2026-07-01.
//

import Testing
import Foundation
import SwiftData
@testable import Reczipes2

/// Validates the consumer opt-in contract added for the communal recipe library.
@Suite("Communal Library Tests")
@MainActor
struct CommunalLibraryTests {

    // MARK: - Helpers

    private func createTestModelContainer() throws -> ModelContainer {
        let schema = Schema([
            RecipeX.self,
            Book.self,
            SharedRecipe.self,
            SharedRecipeBook.self,
            SharingPreferences.self,
            CachedSharedRecipe.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: - Opt-in default

    @Test("browseCommunity defaults to true (communal library on)")
    func browseCommunityDefaultsOn() throws {
        let prefs = SharingPreferences()
        #expect(prefs.browseCommunity == true, "Communal library should be opt-out (default on)")
    }

    @Test("browseCommunity is independent of publishing consent")
    func browseCommunityIndependentOfPublishing() throws {
        // Consuming the communal library must not imply publishing your own recipes.
        let prefs = SharingPreferences()
        #expect(prefs.browseCommunity == true)
        #expect(prefs.shareAllRecipes == false, "Publishing stays opt-in even when browsing is on")
    }

    // MARK: - Init parameter

    @Test("browseCommunity can be set via initializer")
    func browseCommunityInitParameter() throws {
        let optedOut = SharingPreferences(browseCommunity: false)
        #expect(optedOut.browseCommunity == false)

        let optedIn = SharingPreferences(browseCommunity: true)
        #expect(optedIn.browseCommunity == true)
    }

    // MARK: - Persistence round-trip

    @Test("browseCommunity persists through SwiftData")
    func browseCommunityPersists() throws {
        let container = try createTestModelContainer()
        let context = container.mainContext

        let prefs = SharingPreferences()
        prefs.browseCommunity = false
        prefs.dateModified = Date()
        context.insert(prefs)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SharingPreferences>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.browseCommunity == false, "Toggled opt-out should persist")
    }

    @Test("browseCommunity toggle round-trips on/off")
    func browseCommunityToggleRoundTrip() throws {
        let container = try createTestModelContainer()
        let context = container.mainContext

        let prefs = SharingPreferences()
        context.insert(prefs)
        try context.save()

        prefs.browseCommunity = false
        try context.save()
        #expect(try context.fetch(FetchDescriptor<SharingPreferences>()).first?.browseCommunity == false)

        prefs.browseCommunity = true
        try context.save()
        #expect(try context.fetch(FetchDescriptor<SharingPreferences>()).first?.browseCommunity == true)
    }

    // MARK: - Launch-gate semantics

    /// Mirrors the launch-hydration gate in Reczipes2App.hydrateCommunityLibraryIfOptedIn:
    /// `prefs?.browseCommunity ?? true` — absence of a prefs record means opted-in.
    @Test("Launch gate treats missing preferences as opted-in")
    func launchGateDefaultsToOptedInWhenNoPrefs() throws {
        let container = try createTestModelContainer()
        let context = container.mainContext

        let prefs = try context.fetch(FetchDescriptor<SharingPreferences>()).first
        let optedIn = prefs?.browseCommunity ?? true
        #expect(optedIn == true, "No preferences record should default to opted-in hydration")
    }

    @Test("Launch gate honors explicit opt-out")
    func launchGateHonorsOptOut() throws {
        let container = try createTestModelContainer()
        let context = container.mainContext

        let prefs = SharingPreferences(browseCommunity: false)
        context.insert(prefs)
        try context.save()

        let stored = try context.fetch(FetchDescriptor<SharingPreferences>()).first
        let optedIn = stored?.browseCommunity ?? true
        #expect(optedIn == false, "Explicit opt-out must disable launch hydration")
    }
}
