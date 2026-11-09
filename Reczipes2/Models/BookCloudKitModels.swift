//
//  BookCloudKitModels.swift
//  Reczipes2
//
//  Created on 1/26/26.
//
//  CloudKit-compatible representations and helpers for Book model

import Foundation
import SwiftUI
import CloudKit

// MARK: - CloudKit Record Type

extension CloudKitRecordType {
    static let book = "Book"
    static let bookContent = "BookContent"
}

// MARK: - CloudKit-Compatible Book

/// CloudKit-friendly representation of a book for sharing
struct CloudKitBook: Codable, Identifiable {
    let id: UUID
    let name: String
    let bookDescription: String?
    let color: String?
    let recipeIDs: [UUID]
    let recipePreviews: [BookRecipePreview]
    let images: [BookImage]
    let instructions: [BookInstruction]
    let glossary: [BookGlossaryEntry]
    let customContent: [BookContentItem]
    let tableOfContents: [BookSection]
    let category: String?
    let cuisine: String?
    let tags: [String]
    
    // Metadata
    let version: Int
    let dateCreated: Date
    let dateModified: Date
    
    // Sharing metadata
    let ownerUserID: String
    let ownerDisplayName: String?
    let sharedDate: Date
    let privacyLevel: String
    
    // Cover image is handled separately as CKAsset
    var coverImageRecordID: String?
}

/// Status of a book in CloudKit
struct CloudKitBookStatus: Identifiable {
    let id = UUID()
    let book: CloudKitBook
    let cloudRecordID: String
    let sharedDate: Date
    let localTrackingRecord: Book?
    let coverImageURL: URL?
    
    var isTracked: Bool {
        localTrackingRecord != nil
    }
    
    var isOrphaned: Bool {
        !isTracked
    }
    
    var statusIcon: String {
        if isTracked {
            if localTrackingRecord?.needsCloudSync == true {
                return "arrow.triangle.2.circlepath.circle.fill"
            }
            return "checkmark.circle.fill"
        }
        return "exclamationmark.triangle.fill"
    }
    
    var statusColor: Color {
        if isTracked {
            if localTrackingRecord?.needsCloudSync == true {
                return .blue
            }
            return .green
        }
        return .orange
    }
    
    var statusDescription: String {
        if isTracked {
            if localTrackingRecord?.needsCloudSync == true {
                return String(localized: "Needs Sync", bundle: .appLanguage)
            }
            return String(localized: "Synced", bundle: .appLanguage)
        }
        return String(localized: "Orphaned (not tracked locally)", bundle: .appLanguage)
    }
    
    var recipeCount: Int {
        book.recipeIDs.count
    }
    
    var contentItemsCount: Int {
        book.images.count + book.instructions.count + book.glossary.count + book.customContent.count
    }
}

/// Data for CloudKit Book Manager View
struct CloudKitBookManagerData {
    let books: [CloudKitBookStatus]
    
    var trackedBooks: [CloudKitBookStatus] {
        books.filter { $0.isTracked }
    }
    
    var orphanedBooks: [CloudKitBookStatus] {
        books.filter { $0.isOrphaned }
    }
    
    var needsSyncBooks: [CloudKitBookStatus] {
        books.filter { $0.localTrackingRecord?.needsCloudSync == true }
    }
    
    var trackedCount: Int {
        trackedBooks.count
    }
    
    var orphanedCount: Int {
        orphanedBooks.count
    }
    
    var needsSyncCount: Int {
        needsSyncBooks.count
    }
    
    var totalCount: Int {
        books.count
    }
    
    var totalRecipes: Int {
        books.reduce(0) { $0 + $1.recipeCount }
    }
    
    var totalContentItems: Int {
        books.reduce(0) { $0 + $1.contentItemsCount }
    }
}

// MARK: - Book Preview for Discovery

/// Lightweight book preview for discovery/browsing
struct BookPreview: Codable, Identifiable {
    let id: UUID
    let name: String
    let bookDescription: String?
    let coverImageThumbnail: Data?
    let color: String?
    let recipeCount: Int
    let contentItemsCount: Int
    let category: String?
    let cuisine: String?
    let tags: [String]
    
    let ownerUserID: String
    let ownerDisplayName: String?
    let sharedDate: Date
    let downloadCount: Int
    
    let cloudRecordID: String
}

// MARK: - Book Sync Result

enum BookSyncResult {
    case success(bookID: UUID, recordID: String)
    case failure(error: BookSyncError)
    case partialSuccess(synced: Int, failed: Int, errors: [BookSyncError])
}

enum BookSyncError: LocalizedError {
    case bookNotFound
    case notAuthenticated
    case cloudKitUnavailable
    case uploadFailed(Error)
    case downloadFailed(Error)
    case invalidData
    case coverImageUploadFailed(Error)
    case contentUploadFailed(contentType: String, error: Error)
    case quotaExceeded
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .bookNotFound:
            return String(localized: "The book was not found.", bundle: .appLanguage)
        case .notAuthenticated:
            return String(localized: "You must be signed in to iCloud to sync books.", bundle: .appLanguage)
        case .cloudKitUnavailable:
            return String(localized: "CloudKit is not available. Check your iCloud settings.", bundle: .appLanguage)
        case .uploadFailed(let error):
            return String(localized: "Failed to upload book: \(error.localizedDescription)", bundle: .appLanguage)
        case .downloadFailed(let error):
            return String(localized: "Failed to download book: \(error.localizedDescription)", bundle: .appLanguage)
        case .invalidData:
            return String(localized: "The book contains invalid data.", bundle: .appLanguage)
        case .coverImageUploadFailed(let error):
            return String(localized: "Failed to upload cover image: \(error.localizedDescription)", bundle: .appLanguage)
        case .contentUploadFailed(let contentType, let error):
            return String(localized: "Failed to upload \(contentType): \(error.localizedDescription)", bundle: .appLanguage)
        case .quotaExceeded:
            return String(localized: "iCloud storage quota exceeded. Free up space and try again.", bundle: .appLanguage)
        case .networkError:
            return String(localized: "Network connection error. Check your internet connection.", bundle: .appLanguage)
        }
    }
}

// MARK: - Book Download Options

struct BookDownloadOptions {
    /// Whether to download recipe previews only (lightweight) or full recipes
    var downloadFullRecipes: Bool = false
    
    /// Whether to download high-resolution images
    var downloadHighResImages: Bool = true
    
    /// Whether to download all content items (instructions, glossary, etc.)
    var downloadAllContent: Bool = true
    
    /// Maximum image size in bytes (nil = no limit)
    var maxImageSize: Int? = 10_000_000 // 10 MB default
    
    /// Create a local copy (true) or just preview/cache (false)
    var createLocalCopy: Bool = true
    
    static var preview: BookDownloadOptions {
        BookDownloadOptions(
            downloadFullRecipes: false,
            downloadHighResImages: false,
            downloadAllContent: false,
            createLocalCopy: false
        )
    }
    
    static var full: BookDownloadOptions {
        BookDownloadOptions(
            downloadFullRecipes: true,
            downloadHighResImages: true,
            downloadAllContent: true,
            createLocalCopy: true
        )
    }
    
    static var offline: BookDownloadOptions {
        BookDownloadOptions(
            downloadFullRecipes: true,
            downloadHighResImages: false,
            downloadAllContent: true,
            maxImageSize: 5_000_000, // 5 MB for offline
            createLocalCopy: true
        )
    }
}

// MARK: - Book Sharing Configuration

struct BookSharingConfiguration {
    /// Whether to share recipe previews or full recipes
    var shareFullRecipes: Bool = false
    
    /// Whether to include high-resolution cover image
    var includeHighResCover: Bool = true
    
    /// Whether to include all images in content items
    var includeContentImages: Bool = true
    
    /// Maximum image quality (0.0 - 1.0) for compression
    var imageQuality: Double = 0.8
    
    /// Whether to share personal notes
    var includePersonalNotes: Bool = false
    
    /// Privacy level
    var privacyLevel: BookPrivacyLevel = .public
    
    static var `public`: BookSharingConfiguration {
        BookSharingConfiguration(
            shareFullRecipes: false,
            includeHighResCover: true,
            includeContentImages: true,
            privacyLevel: .public
        )
    }
    
    static var friends: BookSharingConfiguration {
        BookSharingConfiguration(
            shareFullRecipes: true,
            includeHighResCover: true,
            includeContentImages: true,
            privacyLevel: .friends
        )
    }
    
    static var minimal: BookSharingConfiguration {
        BookSharingConfiguration(
            shareFullRecipes: false,
            includeHighResCover: false,
            includeContentImages: false,
            imageQuality: 0.5,
            privacyLevel: .public
        )
    }
}

enum BookPrivacyLevel: String, Codable, CaseIterable {
    case `public` = "public"
    case friends = "friends"
    case `private` = "private"
    
    var displayName: String {
        switch self {
        case .public: return String(localized: "Public", bundle: .appLanguage)
        case .friends: return String(localized: "Friends Only", bundle: .appLanguage)
        case .private: return String(localized: "Private", bundle: .appLanguage)
        }
    }
    
    var icon: String {
        switch self {
        case .public: return "globe"
        case .friends: return "person.2.fill"
        case .private: return "lock.fill"
        }
    }
    
    var description: String {
        switch self {
        case .public:
            return String(localized: "Anyone can discover and download this book", bundle: .appLanguage)
        case .friends:
            return String(localized: "Only people you share with can access this book", bundle: .appLanguage)
        case .private:
            return String(localized: "Only you can access this book", bundle: .appLanguage)
        }
    }
}

// MARK: - Book Statistics

struct BookStatistics {
    let totalRecipes: Int
    let totalImages: Int
    let totalInstructions: Int
    let totalGlossaryEntries: Int
    let totalCustomContent: Int
    let totalSections: Int
    
    let estimatedSize: Int // in bytes
    let createdDate: Date
    let lastModified: Date
    let viewCount: Int
    let downloadCount: Int
    
    var totalContentItems: Int {
        totalImages + totalInstructions + totalGlossaryEntries + totalCustomContent
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(estimatedSize), countStyle: .file)
    }
}

extension Book {
    /// Get statistics for this book
    var statistics: BookStatistics {
        let images = self.images
        let instructions = self.instructions
        let glossary = self.glossary
        let customContent = self.customContent
        let sections = self.tableOfContents
        
        // Estimate size
        var size = 0
        if let coverData = coverImageData {
            size += coverData.count
        }
        size += (recipePreviewsData?.count ?? 0)
        size += (imagesData?.count ?? 0)
        size += BookImageProcessing.totalBytes(images)   // picture records
        size += (instructionsData?.count ?? 0)
        size += (glossaryData?.count ?? 0)
        size += (customContentData?.count ?? 0)
        size += (tableOfContentsData?.count ?? 0)
        
        return BookStatistics(
            totalRecipes: recipeCount,
            totalImages: images.count,
            totalInstructions: instructions.count,
            totalGlossaryEntries: glossary.count,
            totalCustomContent: customContent.count,
            totalSections: sections.count,
            estimatedSize: size,
            createdDate: dateCreated ?? Date(),
            lastModified: dateModified ?? Date(),
            viewCount: viewCount ?? 0,
            downloadCount: downloadCount ?? 0
        )
    }
}
