//
//  ImageCompressionUtility.swift
//  Reczipes2
//
//  Created for optimized image compression with size constraints
//

import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Utility for compressing images to a target file size while maintaining quality
enum ImageCompressionUtility {

    /// Target maximum file size in bytes (100KB)
    static let targetMaxSize: Int = 100_000 // 100KB

    /// Minimum acceptable image quality
    static let minQuality: CGFloat = 0.5

    /// Maximum dimension for images (to prevent extremely large images)
    static let maxDimension: CGFloat = 2048

    /// Compress an image to stay under target size
    /// - Parameters:
    ///   - image: The source image to compress
    ///   - targetSize: Target maximum file size in bytes (default: 100KB)
    ///   - maintainAspectRatio: Whether to maintain aspect ratio when resizing (default: true)
    /// - Returns: Compressed image data, or nil if compression fails
    static func compressImage(_ image: PlatformImage, targetSize: Int = targetMaxSize, maintainAspectRatio: Bool = true) -> Data? {
        AppLog.info("Starting compression for image size: \(image.size), scale: \(image.scale), target: \(formatSize(targetSize))", category: .image)

        // First, resize if image is too large
        let resizedImage = resizeIfNeeded(image, maxDimension: maxDimension)
        if resizedImage.size != image.size {
            AppLog.info("Resized image from \(image.size) to \(resizedImage.size)", category: .image)
        }

        // Try progressive compression with quality reduction
        let compressionQuality: CGFloat = 0.85
        var imageData = resizedImage.jpegData(compressionQuality: compressionQuality)

        guard let initialData = imageData else {
            AppLog.error("Failed to create initial JPEG data from image", category: .image)
            return nil
        }

        // If already under target, return it
        if initialData.count <= targetSize {
            AppLog.info("Image fits target at quality \(compressionQuality): \(formatSize(initialData.count))", category: .image)
            return initialData
        }

        // Progressive quality reduction
        let qualitySteps: [CGFloat] = [0.80, 0.75, 0.70, 0.65, 0.60, 0.55, 0.50]

        for quality in qualitySteps {
            if let data = resizedImage.jpegData(compressionQuality: quality) {
                imageData = data
                if data.count <= targetSize {
                    AppLog.info("Compressed to \(formatSize(data.count)) at quality \(quality)", category: .image)
                    return data
                }
            }
        }

        // If still too large, progressively resize
        AppLog.info("Quality reduction insufficient, starting progressive resize", category: .image)
        var scaleFactor: CGFloat = 0.9
        var currentImage = resizedImage

        while scaleFactor >= 0.5 {
            let targetWidth = currentImage.size.width * scaleFactor
            let targetHeight = currentImage.size.height * scaleFactor

            if let downsized = resize(currentImage, to: CGSize(width: targetWidth, height: targetHeight)) {
                currentImage = downsized

                // Try with reasonable quality on resized image
                for quality in [0.75, 0.70, 0.65, 0.60, 0.55, 0.50] {
                    if let data = currentImage.jpegData(compressionQuality: quality) {
                        if data.count <= targetSize {
                            AppLog.info("Compressed to \(formatSize(data.count)) at scale \(scaleFactor) and quality \(quality)", category: .image)
                            return data
                        }
                    }
                }
            }

            scaleFactor -= 0.1
        }

        // Last resort: use minimum quality on current image
        let finalData = currentImage.jpegData(compressionQuality: minQuality)
        if let data = finalData {
            AppLog.warning("Using last resort compression: \(formatSize(data.count)) (may exceed target)", category: .image)
        } else {
            AppLog.error("Last resort compression failed to create JPEG data", category: .image)
        }
        return finalData
    }

    /// Resize image if it exceeds maximum dimension
    /// - Parameters:
    ///   - image: Source image
    ///   - maxDimension: Maximum allowed dimension
    /// - Returns: Resized image if needed, original if within limits
    static func resizeIfNeeded(_ image: PlatformImage, maxDimension: CGFloat) -> PlatformImage {
        let size = image.size

        // Check if resizing is needed
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }

        // Calculate new size maintaining aspect ratio
        let aspectRatio = size.width / size.height
        var newSize: CGSize

        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        return resize(image, to: newSize) ?? image
    }

    /// Resize image to specific size
    /// - Parameters:
    ///   - image: Source image
    ///   - size: Target size
    /// - Returns: Resized image or nil on failure
    static func resize(_ image: PlatformImage, to size: CGSize) -> PlatformImage? {
        #if canImport(UIKit)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
        #elseif canImport(AppKit)
        // Redraw into a CGContext then wrap in NSImage.
        guard let cgImage = image.cgImage else { return nil }
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return nil }

        let bitsPerComponent = 8
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        guard let resizedCGImage = context.makeImage() else { return nil }
        return NSImage(cgImage: resizedCGImage, size: size)
        #else
        return nil
        #endif
    }

    /// Get human-readable size string
    /// - Parameter bytes: Size in bytes
    /// - Returns: Formatted string (e.g., "85.3 KB")
    static func formatSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Compress image for thumbnail use (smaller target size)
    /// - Parameter image: Source image
    /// - Returns: Compressed thumbnail data
    static func compressForThumbnail(_ image: PlatformImage) -> Data? {
        return compressImage(image, targetSize: 50_000) // 50KB for thumbnails
    }

    /// Compress image for book cover (slightly larger allowed)
    /// - Parameter image: Source image
    /// - Returns: Compressed book cover data
    static func compressForBookCover(_ image: PlatformImage) -> Data? {
        return compressImage(image, targetSize: 150_000) // 150KB for book covers (more detail)
    }
}
