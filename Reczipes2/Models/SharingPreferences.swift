//
//  SharingPreferences.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/20/26.
//


import Foundation
import SwiftData
import CloudKit
import SwiftUI


// MARK: - Sharing Preferences

/// User's sharing preferences
@Model
final class SharingPreferences {
    var id: UUID = UUID()
    var shareAllRecipes: Bool = false
    var shareAllBooks: Bool = false
    var shareAllMeals: Bool = false
    var allowOthersToSeeMyName: Bool = true
    var displayName: String?
    var dateModified: Date = Date()

    /// Consumer opt-in: participate in the communal recipe library.
    /// When true, the app hydrates every shared recipe (from all users, including the
    /// current user's own shared recipes) into the local cache on launch and refresh.
    /// Defaults to `true` (communal library on; publishing still requires `shareAllRecipes`).
    var browseCommunity: Bool = true

    init(shareAllRecipes: Bool = false,
         shareAllBooks: Bool = false,
         shareAllMeals: Bool = false,
         allowOthersToSeeMyName: Bool = true,
         displayName: String? = nil,
         browseCommunity: Bool = true) {
        self.shareAllRecipes = shareAllRecipes
        self.shareAllBooks = shareAllBooks
        self.shareAllMeals = shareAllMeals
        self.allowOthersToSeeMyName = allowOthersToSeeMyName
        self.displayName = displayName
        self.browseCommunity = browseCommunity
    }
}