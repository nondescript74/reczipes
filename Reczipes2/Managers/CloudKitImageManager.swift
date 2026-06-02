//
//  CloudKitImageManager.swift
//  Reczipes2
//
//  Created for CloudKit image sync support
//

import Foundation
import SwiftUI
import CloudKit

/// Manages recipe images with CloudKit sync support
/// Images are stored as CKAssets which can handle large files
class CloudKitImageManager {
    static let shared = CloudKitImageManager()
    
    private let imageDirectory: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let imageDir = documentsDirectory.appendingPathComponent("RecipeImages", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        
        return imageDir
    }()
    
    private init() {
        AppLog.info("📸 CloudKitImageManager initialized with directory: \(imageDirectory.path)", category: .image)
    }
    
    // MARK: - Image Storage
    
    /// Save an image and return a filename that can be synced
    func saveImage(_ image: UIImage, for recipeID: UUID) -> String? {
        // Generate a unique filename
        let filename = "\(recipeID.uuidString)_\(UUID().uuidString).jpg"
        let fileURL = imageDirectory.appendingPathComponent(filename)
        
        // Compress image for reasonable file size (adjust quality as needed)
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            AppLog.info("❌ Failed to convert image to JPEG data", category: .image)
            return nil
        }
        
        do {
            try imageData.write(to: fileURL)
            AppLog.info("✅ Saved image: \(filename)", category: .image)
            return filename
        } catch {
            AppLog.error("❌ Error saving image: \(error)", category: .image)
            return nil
        }
    }
    
    /// Load an image by filename
    func loadImage(named filename: String) -> UIImage? {
        let fileURL = imageDirectory.appendingPathComponent(filename)
        
        guard let imageData = try? Data(contentsOf: fileURL),
              let image = UIImage(data: imageData) else {
            AppLog.warning("⚠️ Could not load image: \(filename)", category: .image)
            return nil
        }
        
        return image
    }
    
    /// Delete an image by filename
    func deleteImage(named filename: String) {
        let fileURL = imageDirectory.appendingPathComponent(filename)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            AppLog.info("🗑️ Deleted image: \(filename)", category: .image)
        } catch {
            AppLog.warning("⚠️ Error deleting image: \(error)", category: .image)
        }
    }
    
    /// Delete all images for a recipe
    func deleteAllImages(for recipe: RecipeX) {
        // Delete main image
        if let imageName = recipe.imageName {
            deleteImage(named: imageName)
        }
        
        // Delete additional images
        recipe.additionalImageNames?.forEach { imageName in
            deleteImage(named: imageName)
        }
    }
    
    // MARK: - CloudKit Asset Support
    
    /// Get file URL for an image (needed for CloudKit CKAsset)
    func fileURL(for filename: String) -> URL {
        return imageDirectory.appendingPathComponent(filename)
    }
    
    /// Check if an image exists locally
    func imageExists(named filename: String) -> Bool {
        let fileURL = imageDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    /// Get the size of an image file in bytes
    func imageSize(named filename: String) -> Int64? {
        let fileURL = imageDirectory.appendingPathComponent(filename)
        
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? NSNumber else {
            return nil
        }
        
        return fileSize.int64Value
    }
    
    // MARK: - Bulk Operations
    
    /// Get total size of all recipe images
    func totalImageSize() -> Int64 {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: imageDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        return fileURLs.reduce(0) { total, url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return total
            }
            return total + Int64(size)
        }
    }
    
    /// Clean up orphaned images (images not referenced by any recipe)
    func cleanupOrphanedImages(validImageNames: Set<String>) {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: imageDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        
        var deletedCount = 0
        
        for fileURL in fileURLs {
            let filename = fileURL.lastPathComponent
            
            if !validImageNames.contains(filename) {
                try? FileManager.default.removeItem(at: fileURL)
                deletedCount += 1
            }
        }
        
        if deletedCount > 0 {
            AppLog.info("🧹 Cleaned up \(deletedCount) orphaned images", category: .image)
        }
    }
}

// MARK: - SwiftUI Image Loading

extension CloudKitImageManager {
    /// Load an image asynchronously for SwiftUI
    @MainActor
    func loadImageAsync(named filename: String) async -> UIImage? {
        return await Task.detached(priority: .userInitiated) {
            return await self.loadImage(named: filename)
        }.value
    }
}
