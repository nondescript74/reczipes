//
//  VersionHistory.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/30/24.
//  Updated: 02/01/26 - Refactored to use SwiftData storage
//

import Foundation
import SwiftData

// MARK: - ⚠️ MIGRATION NOTICE ⚠️
//
// Version history is now stored in SwiftData (VersionHistoryRecord model).
// This file is only used to ADD NEW VERSION ENTRIES when you update the app.
//
// To view version history, use VersionHistoryView.
// Historical data has been migrated to VersionHistoryMigration.swift
//
// USAGE:
// 1. Update your app version/build in Xcode
// 2. Add a new entry below with your changes
// 3. The system will automatically check for duplicates before adding

// MARK: - Add New Version Entry Here

/// ADD YOUR NEW VERSION CHANGES HERE
/// This is the ONLY place you need to update when releasing a new version
///
/// Usage:
/// - Just add your changes to the array below
/// - Version and build number are automatically pulled from Info.plist
/// - The system checks for duplicates before inserting
///
@MainActor
func addCurrentVersionToHistory(modelContext: ModelContext) async {
    let service = VersionHistoryService.shared
    service.initialize(modelContext: modelContext)
    
    // ⚠️ UPDATE THIS ARRAY WITH YOUR NEW CHANGES ⚠️
    let currentVersionChanges: [String] = [
        "• 🌐 Enhanced: Web extraction now preserves embedded recipe data in scripts and keeps head+tail content for large pages",
        "• 🤖 Added: Auto-search similar recipes when ingredients or instructions are missing (URL and image extractions)",
        "• 🧩 Added: Apply ingredients, instructions, or notes from similar recipes directly to the extracted recipe",
        "• 🔗 Improved: Reference field now records original source and any supplemental ingredient/instruction sources",
        "• ⏳ Added: Spinner and banner to show when similar recipe search is in progress",
        "• 🎨 UI: Reduced extractor option button sizes to fit on smaller iPhone screens"
    ]
    
    // Only add if there are changes
    guard !currentVersionChanges.isEmpty else {
        print("⚠️ No changes to add for current version")
        return
    }
    
    do {
        try service.addCurrentVersion(changes: currentVersionChanges)
        print("✅ Successfully added/updated current version history")
    } catch {
        print("❌ Error adding version history: \(error.localizedDescription)")
    }
}

// MARK: - Emoji Prefix Guide

/*
 
 EMOJI GUIDE FOR VERSION HISTORY
 ================================
 
 Use these emoji prefixes to categorize changes:
 
 ✨ New Feature - Major new functionality
 🎨 UI/Design - Visual improvements, new design elements
 ⚡️ Performance - Speed improvements, optimization
 🐛 Bug Fix - Fixed bugs or issues
 🔒 Security - Security improvements
 📚 Documentation - Documentation updates
 🔄 Sync/Cloud - Sync, backup, cloud features
 🤖 AI/ML - AI or machine learning features
 🏷️ Organization - Tagging, categorization features
 ⚠️ Health - Health-related features (allergens, diabetes, etc.)
 🔍 Search - Search and filtering improvements
 📱 Platform - Platform-specific features
 🌐 Localization - Language and region support
 ♿️ Accessibility - Accessibility improvements
 📊 Analytics - Analytics and tracking
 🎯 Targeting - Personalization features
 💾 Data - Data management features
 🔗 Integration - Third-party integrations
 📸 Media - Photo and media features
 🎵 Audio - Audio features
 📹 Video - Video features
 🗺️ Maps - Location and maps
 📅 Calendar - Calendar integration
 👥 Social - Social and sharing features
 💰 Commerce - In-app purchases, payments
 🎮 Gamification - Game-like features
 📢 Notifications - Notification features
 🔧 Developer - Developer tools and debugging
 
 Examples:
 "• ✨ Added: Recipe Books Organization"
 "• 🐛 Fixed: Crash when importing large recipes"
 "• ⚡️ Enhanced: Recipe loading speed by 50%"
 "• 🎨 Redesigned: Launch screen with Liquid Glass"
 
 Note: Always prefix each change with a bullet point (•) for consistent formatting
 
 */


