//
//  Book.swift
//  Reczipes2
//
//  Created on 1/26/26.
//
//  UNIFIED BOOK MODEL - CloudKit Compatible
//  Combines RecipeBook, SharedRecipeBook, and CloudKitRecipeBook into a single model
//  with automatic iCloud sharing built-in.

import Foundation
import SwiftData
import CloudKit
import CryptoKit
import SwiftUI

/// Unified book model with automatic iCloud sharing
/// 
/// DESIGN PHILOSOPHY:
/// - Local-first: All books are stored locally in SwiftData
/// - Auto-sync: Books automatically sync to iCloud Public Database
/// - Always shared: No concept of "not sharing" - all books are public
/// - Simple: One model, one source of truth
///
/// SYNC STRATEGY:
/// - User creates/edits book → Saved to SwiftData
/// - Background sync service uploads to CloudKit Public DB
/// - Other users can discover books via CloudKit queries
/// - Books sync across user's devices via iCloud (CloudKit Private DB)
///
/// CLOUDKIT COMPATIBILITY:
/// - All properties are optional or have default values
/// - No @Attribute(.unique) constraints (CloudKit doesn't support this)
/// - Uses standard Swift/CloudKit types only
///
/// BOOK CONTENTS:
/// - Recipes (RecipeX references)
/// - Images (cover + additional images)
/// - Instructions/How-to guides
/// - Glossaries (cooking terms, ingredient definitions)
/// - Other custom content items
@Model
final class Book {
    
    // MARK: - Core Identity
    
    /// Unique identifier (stable across all sync operations)
    var id: UUID?
    
    /// Book name/title
    var name: String?
    
    /// Description of the book's contents and purpose
    var bookDescription: String?
    
    // MARK: - Visual Identity
    
    /// Cover image data (stored in SwiftData for CloudKit sync)
    @Attribute(.externalStorage) var coverImageData: Data?
    
    /// Legacy: File name of cover image (for backward compatibility)
    var coverImageName: String?
    
    /// Color theme for the book (hex string, e.g., "#FF5733")
    var color: String?
    
    // MARK: - Content Organization
    
    /// Recipe IDs in display order (references to RecipeX models)
    var recipeIDs: [UUID]?
    
    /// Recipe previews stored as JSON for quick access without loading full recipes
    /// Encodes [BookRecipePreview]
    var recipePreviewsData: Data?
    
    /// Image items stored as JSON
    /// Encodes [BookImage] for standalone images (not recipe photos)
    var imagesData: Data?
    
    /// Instruction/how-to items stored as JSON
    /// Encodes [BookInstruction] for cooking techniques, equipment guides, etc.
    var instructionsData: Data?
    
    /// Glossary entries stored as JSON
    /// Encodes [BookGlossaryEntry] for ingredient definitions, cooking terms, etc.
    var glossaryData: Data?
    
    /// Custom content items stored as JSON
    /// Encodes [BookContentItem] for any other content (notes, stories, tips, etc.)
    var customContentData: Data?
    
    /// Table of contents stored as JSON
    /// Encodes [BookSection] for organizing content into chapters/sections
    var tableOfContentsData: Data?
    
    // MARK: - Timestamps
    
    /// When the book was created
    var dateCreated: Date?
    
    /// Last modification timestamp (for conflict resolution)
    var dateModified: Date?
    
    /// When the book was last accessed/viewed
    var lastAccessedDate: Date?
    
    // MARK: - Versioning & Change Detection
    
    /// Version number (increments on each edit)
    var version: Int?
    
    /// Content fingerprint for change detection and duplicate prevention
    var contentFingerprint: String?
    
    /// Hash of recipe IDs (for efficient change detection)
    var recipeIDsHash: String?
    
    // MARK: - CloudKit Sync
    
    /// CloudKit record ID in Public Database (nil if not yet uploaded)
    var cloudRecordID: String?
    
    /// When the book was last successfully synced to CloudKit
    var lastSyncedToCloud: Date?
    
    /// Whether the book needs to be uploaded/updated in CloudKit
    var needsCloudSync: Bool?
    
    /// Number of sync retry attempts (for error handling)
    var syncRetryCount: Int?
    
    /// Last sync error message (for debugging)
    var lastSyncError: String?
    
    /// Whether this book is actively shared (can be toggled by user)
    var isShared: Bool?
    
    // MARK: - User Attribution
    
    /// CloudKit user ID who created this book
    var ownerUserID: String?
    
    /// Display name of the user who created this book
    var ownerDisplayName: String?
    
    /// Current user's device identifier (for tracking which device made changes)
    var lastModifiedDeviceID: String?
    
    // MARK: - Metadata
    
    /// Cover image hash for duplicate detection (SHA256)
    var coverImageHash: String?
    
    /// Tags for categorization (stored as JSON array)
    var tagsData: Data?
    
    /// Category (e.g., "Desserts", "Holiday Cooking", "Quick Meals")
    var category: String?
    
    /// Cuisine type (e.g., "Italian", "Mexican", "Asian Fusion")
    var cuisine: String?
    
    /// Privacy level: "public", "friends", "private" (for future use)
    var privacyLevel: String?
    
    /// Number of times this book has been viewed
    var viewCount: Int?
    
    /// Number of times this book has been downloaded by other users
    var downloadCount: Int?
    
    /// User's notes about the book (personal, not shared)
    var personalNotes: String?
    
    // MARK: - Sharing Metadata
    
    /// Date when this book was shared to CloudKit
    var sharedDate: Date?
    
    /// Whether this is a book imported from another user
    var isImported: Bool?
    
    /// Original book ID if this is a copy of someone else's book
    var originalBookID: UUID?
    
    /// Original owner's user ID if this is a copy
    var originalOwnerUserID: String?
    
    /// Original owner's display name if this is a copy
    var originalOwnerDisplayName: String?
    
    // MARK: - Initializer
    
    init(id: UUID? = UUID(),
         name: String? = nil,
         bookDescription: String? = nil,
         coverImageData: Data? = nil,
         coverImageName: String? = nil,
         color: String? = nil,
         recipeIDs: [UUID]? = [],
         recipePreviewsData: Data? = nil,
         imagesData: Data? = nil,
         instructionsData: Data? = nil,
         glossaryData: Data? = nil,
         customContentData: Data? = nil,
         tableOfContentsData: Data? = nil,
         dateCreated: Date? = Date(),
         dateModified: Date? = Date(),
         lastAccessedDate: Date? = nil,
         version: Int? = 1,
         contentFingerprint: String? = nil,
         recipeIDsHash: String? = nil,
         cloudRecordID: String? = nil,
         needsCloudSync: Bool? = true,
         isShared: Bool? = false,
         ownerUserID: String? = nil,
         ownerDisplayName: String? = nil,
         coverImageHash: String? = nil,
         tagsData: Data? = nil,
         category: String? = nil,
         cuisine: String? = nil,
         privacyLevel: String? = "public",
         viewCount: Int? = 0,
         downloadCount: Int? = 0,
         personalNotes: String? = nil,
         sharedDate: Date? = nil,
         isImported: Bool? = false,
         originalBookID: UUID? = nil,
         originalOwnerUserID: String? = nil,
         originalOwnerDisplayName: String? = nil) {
        
        self.id = id
        self.name = name
        self.bookDescription = bookDescription
        self.coverImageData = coverImageData
        self.coverImageName = coverImageName
        self.color = color
        self.recipeIDs = recipeIDs
        self.recipePreviewsData = recipePreviewsData
        self.imagesData = imagesData
        self.instructionsData = instructionsData
        self.glossaryData = glossaryData
        self.customContentData = customContentData
        self.tableOfContentsData = tableOfContentsData
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.lastAccessedDate = lastAccessedDate
        self.version = version
        self.contentFingerprint = contentFingerprint
        self.recipeIDsHash = recipeIDsHash ?? Self.calculateRecipeIDsHash(from: recipeIDs)
        self.cloudRecordID = cloudRecordID
        self.lastSyncedToCloud = nil
        self.needsCloudSync = needsCloudSync
        self.syncRetryCount = 0
        self.isShared = isShared
        self.ownerUserID = ownerUserID
        self.ownerDisplayName = ownerDisplayName
        self.lastModifiedDeviceID = nil
        self.coverImageHash = coverImageHash ?? Self.calculateImageHash(from: coverImageData)
        self.tagsData = tagsData
        self.category = category
        self.cuisine = cuisine
        self.privacyLevel = privacyLevel
        self.viewCount = viewCount
        self.downloadCount = downloadCount
        self.personalNotes = personalNotes
        self.sharedDate = sharedDate
        self.isImported = isImported
        self.originalBookID = originalBookID
        self.originalOwnerUserID = originalOwnerUserID
        self.originalOwnerDisplayName = originalOwnerDisplayName
    }
}

// MARK: - Convenience Initializers

extension Book {
    
    
    /// Create Book from SharedRecipeBook model
    convenience init(from sharedBook: SharedRecipeBook, isImported: Bool = true) {
        self.init(
            id: sharedBook.bookID ?? UUID(),
            name: sharedBook.bookName,
            bookDescription: sharedBook.bookDescription,
            coverImageName: sharedBook.coverImageName,
            cloudRecordID: sharedBook.cloudRecordID,
            needsCloudSync: false,
            isShared: sharedBook.isActive,
            ownerUserID: sharedBook.sharedByUserID,
            ownerDisplayName: sharedBook.sharedByUserName,
            sharedDate: sharedBook.sharedDate,
            isImported: isImported,
            originalOwnerUserID: sharedBook.sharedByUserID,
            originalOwnerDisplayName: sharedBook.sharedByUserName
        )
    }
}

// MARK: - Computed Properties

extension Book {
    
    /// Number of recipes in this book
    var recipeCount: Int {
        recipeIDs?.count ?? 0
    }
    
    /// Display title (fallback to "Untitled Book" if no name)
    var displayName: String {
        name ?? "Untitled Book"
    }
    
    /// Whether this book has any content
    var hasContent: Bool {
        recipeCount > 0 ||
        (imagesData != nil && !(try? JSONDecoder().decode([BookImage].self, from: imagesData!))!.isEmpty) ||
        (instructionsData != nil && !(try? JSONDecoder().decode([BookInstruction].self, from: instructionsData!))!.isEmpty) ||
        (glossaryData != nil && !(try? JSONDecoder().decode([BookGlossaryEntry].self, from: glossaryData!))!.isEmpty)
    }
    
    /// Whether this book is owned by the current user (not imported from someone else)
    var isOwnedByCurrentUser: Bool {
        !(isImported ?? false)
    }
    
    /// Whether this book is synced to CloudKit
    var isSynced: Bool {
        cloudRecordID != nil && lastSyncedToCloud != nil
    }
    
    /// Whether this book needs attention (has sync errors)
    var needsAttention: Bool {
        lastSyncError != nil || (syncRetryCount ?? 0) > 3
    }
}

// MARK: - Modification Helpers

extension Book {
    
    /// Add a recipe to the book
    func addRecipe(_ recipeID: UUID) {
        var recipes = recipeIDs ?? []
        if !recipes.contains(recipeID) {
            recipes.append(recipeID)
            recipeIDs = recipes
            markModified()
        }
    }
    
    /// Remove a recipe from the book
    func removeRecipe(_ recipeID: UUID) {
        recipeIDs?.removeAll { $0 == recipeID }
        markModified()
    }
    
    /// Reorder recipes in the book
    func moveRecipe(from source: IndexSet, to destination: Int) {
        var recipes = recipeIDs ?? []
        recipes.move(fromOffsets: source, toOffset: destination)
        recipeIDs = recipes
        markModified()
    }
    
    /// Mark the book as modified (updates timestamps and version)
    func markModified() {
        dateModified = Date()
        version = (version ?? 1) + 1
        needsCloudSync = isShared ?? false
        recipeIDsHash = Self.calculateRecipeIDsHash(from: recipeIDs)
    }
    
    /// Mark the book as accessed (updates last accessed date)
    func markAccessed() {
        lastAccessedDate = Date()
    }
    
    /// Toggle sharing status
    func toggleSharing() {
        let newSharedStatus = !(isShared ?? false)
        isShared = newSharedStatus
        needsCloudSync = newSharedStatus
        if newSharedStatus && sharedDate == nil {
            sharedDate = Date()
        }
    }
}

// MARK: - Content Accessors

extension Book {
    
    /// Get recipe previews
    var recipePreviews: [BookRecipePreview] {
        get {
            guard let data = recipePreviewsData else { return [] }
            return (try? JSONDecoder().decode([BookRecipePreview].self, from: data)) ?? []
        }
    }
    
    /// Set recipe previews
    func setRecipePreviews(_ previews: [BookRecipePreview]) {
        recipePreviewsData = try? JSONEncoder().encode(previews)
        markModified()
    }
    
    /// Get images
    var images: [BookImage] {
        get {
            guard let data = imagesData else { return [] }
            return (try? JSONDecoder().decode([BookImage].self, from: data)) ?? []
        }
    }
    
    /// Set images
    func setImages(_ images: [BookImage]) {
        imagesData = try? JSONEncoder().encode(images)
        markModified()
    }
    
    /// Get instructions
    var instructions: [BookInstruction] {
        get {
            guard let data = instructionsData else { return [] }
            return (try? JSONDecoder().decode([BookInstruction].self, from: data)) ?? []
        }
    }
    
    /// Set instructions
    func setInstructions(_ instructions: [BookInstruction]) {
        instructionsData = try? JSONEncoder().encode(instructions)
        markModified()
    }
    
    /// Get glossary entries
    var glossary: [BookGlossaryEntry] {
        get {
            guard let data = glossaryData else { return [] }
            return (try? JSONDecoder().decode([BookGlossaryEntry].self, from: data)) ?? []
        }
    }
    
    /// Set glossary entries
    func setGlossary(_ entries: [BookGlossaryEntry]) {
        glossaryData = try? JSONEncoder().encode(entries)
        markModified()
    }
    
    /// Get custom content items
    var customContent: [BookContentItem] {
        get {
            guard let data = customContentData else { return [] }
            return (try? JSONDecoder().decode([BookContentItem].self, from: data)) ?? []
        }
    }
    
    /// Set custom content items
    func setCustomContent(_ items: [BookContentItem]) {
        customContentData = try? JSONEncoder().encode(items)
        markModified()
    }
    
    /// Get table of contents
    var tableOfContents: [BookSection] {
        get {
            guard let data = tableOfContentsData else { return [] }
            return (try? JSONDecoder().decode([BookSection].self, from: data)) ?? []
        }
    }
    
    /// Set table of contents
    func setTableOfContents(_ sections: [BookSection]) {
        tableOfContentsData = try? JSONEncoder().encode(sections)
        markModified()
    }
    
    /// Get tags
    var tags: [String] {
        get {
            guard let data = tagsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
    }
    
    /// Set tags
    func setTags(_ tags: [String]) {
        tagsData = try? JSONEncoder().encode(tags)
        markModified()
    }
}

// MARK: - Hash Calculation Helpers

extension Book {
    
    /// Calculate SHA256 hash of recipe IDs for change detection
    static func calculateRecipeIDsHash(from recipeIDs: [UUID]?) -> String? {
        guard let recipeIDs = recipeIDs, !recipeIDs.isEmpty else { return nil }
        
        let idsString = recipeIDs.map { $0.uuidString }.sorted().joined(separator: ",")
        guard let data = idsString.data(using: .utf8) else { return nil }
        
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Calculate SHA256 hash of image data for duplicate detection
    static func calculateImageHash(from imageData: Data?) -> String? {
        guard let data = imageData, !data.isEmpty else { return nil }
        
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Calculate content fingerprint for duplicate detection
    static func calculateContentFingerprint(name: String?, description: String?, recipeIDsHash: String?) -> String {
        let components = [
            name ?? "",
            description ?? "",
            recipeIDsHash ?? ""
        ].joined(separator: "||")
        
        guard let data = components.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - CloudKit Conversion

extension Book {
    
    /// Convert to CloudKit-compatible dictionary
    func toCloudKitRecord() -> [String: Any] {
        var record: [String: Any] = [:]
        
        record["id"] = (id ?? UUID()).uuidString
        record["name"] = name ?? ""
        record["bookDescription"] = bookDescription
        record["color"] = color
        record["recipeIDs"] = (recipeIDs ?? []).map { $0.uuidString }
        record["version"] = version ?? 1
        record["dateCreated"] = dateCreated ?? Date()
        record["dateModified"] = dateModified ?? Date()
        record["ownerUserID"] = ownerUserID
        record["ownerDisplayName"] = ownerDisplayName
        record["sharedDate"] = sharedDate ?? Date()
        record["category"] = category
        record["cuisine"] = cuisine
        record["privacyLevel"] = privacyLevel ?? "public"
        
        // Store content as JSON strings for CloudKit
        if let data = recipePreviewsData, let jsonString = String(data: data, encoding: .utf8) {
            record["recipePreviewsJSON"] = jsonString
        }
        if let data = imagesData, let jsonString = String(data: data, encoding: .utf8) {
            record["imagesJSON"] = jsonString
        }
        if let data = instructionsData, let jsonString = String(data: data, encoding: .utf8) {
            record["instructionsJSON"] = jsonString
        }
        if let data = glossaryData, let jsonString = String(data: data, encoding: .utf8) {
            record["glossaryJSON"] = jsonString
        }
        if let data = tableOfContentsData, let jsonString = String(data: data, encoding: .utf8) {
            record["tableOfContentsJSON"] = jsonString
        }
        
        // Handle cover image as CKAsset (CloudKit's way of storing large files)
        if let imageData = coverImageData {
            record["coverImageData"] = imageData
        }
        
        return record
    }
}

// MARK: - Supporting Data Structures

/// Lightweight recipe preview for book display
struct BookRecipePreview: Codable, Identifiable {
    let id: UUID
    let title: String
    let thumbnailData: Data?
    let yield: String?
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
}

/// Image item in a book
struct BookImage: Codable, Identifiable {
    let id: UUID
    let title: String?
    let caption: String?
    let imageData: Data
    let order: Int
    let dateAdded: Date
}

/// Instruction/how-to item in a book
struct BookInstruction: Codable, Identifiable {
    let id: UUID
    let title: String
    let content: String
    let imageData: Data?
    let order: Int
    let category: String? // e.g., "Techniques", "Equipment", "Tips"
    let dateAdded: Date
}

/// Glossary entry in a book
struct BookGlossaryEntry: Codable, Identifiable {
    let id: UUID
    let term: String
    let definition: String
    let imageData: Data?
    let relatedTerms: [String]?
    let order: Int
    let dateAdded: Date
}

/// Custom content item in a book
struct BookContentItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let contentType: String // e.g., "note", "story", "tip", "warning"
    let content: String
    let imageData: Data?
    let order: Int
    let dateAdded: Date
}

/// Section in table of contents
struct BookSection: Codable, Identifiable {
    let id: UUID
    let title: String
    let order: Int
    let itemType: String // "recipe", "image", "instruction", "glossary", "custom"
    let itemID: UUID
}
