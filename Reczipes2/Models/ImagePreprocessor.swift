//
//  ImagePreprocessor.swift
//  Reczipes2
//
//  Created for Claude-powered recipe extraction
//
//  Note: Uses global logging functions (logInfo, logDebug, etc.)
//  defined in DiagnosticLogger.swift
//
//  IMPORTANT: This file is shared into the App Clip and test targets, which do
//  NOT include PlatformCompat.swift. It must therefore be self-contained and
//  depend only on the `PlatformImage` typealias plus native UIKit/AppKit APIs —
//  never on the Platform* shims (PlatformImageRenderer, CIImage(platformImage:),
//  or the NSImage convenience extensions) defined in PlatformCompat.swift.
//

import Foundation

#if canImport(UIKit)
import UIKit
import SwiftUI
#elseif canImport(AppKit)
import AppKit
import SwiftUI
#endif
import CoreImage
import CoreImage.CIFilterBuiltins

class ImagePreprocessor {

    private let context = CIContext()

    // MARK: - Self-contained platform helpers (no PlatformCompat dependency)

    /// JPEG-encode a platform image.
    private func jpegData(_ image: PlatformImage, quality: CGFloat) -> Data? {
        #if canImport(UIKit)
        return image.jpegData(compressionQuality: quality)
        #elseif canImport(AppKit)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #else
        return nil
        #endif
    }

    /// Backing CGImage for a platform image.
    private func cgImage(_ image: PlatformImage) -> CGImage? {
        #if canImport(UIKit)
        return image.cgImage
        #elseif canImport(AppKit)
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        return nil
        #endif
    }

    /// Wrap a CGImage in a platform image.
    private func platformImage(_ cg: CGImage, size: CGSize) -> PlatformImage? {
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #elseif canImport(AppKit)
        return NSImage(cgImage: cg, size: size)
        #else
        return nil
        #endif
    }

    /// Build a CIImage from a platform image.
    private func ciImage(_ image: PlatformImage) -> CIImage? {
        #if canImport(UIKit)
        return CIImage(image: image)
        #elseif canImport(AppKit)
        guard let cg = cgImage(image) else { return nil }
        return CIImage(cgImage: cg)
        #else
        return nil
        #endif
    }

    /// Preprocess an image for optimal OCR results
    /// Applies: grayscale conversion, contrast enhancement, and sharpening
    func preprocessForOCR(_ image: PlatformImage, compressionQuality: CGFloat = 0.9) -> Data? {
        guard let inputImage = ciImage(image) else {
            return jpegData(image, quality: compressionQuality)
        }

        // Step 1: Convert to grayscale
        let grayscaleImage = applyGrayscale(to: inputImage)

        // Step 2: Enhance contrast
        let contrastedImage = enhanceContrast(grayscaleImage)

        // Step 3: Sharpen for better text recognition
        let sharpenedImage = sharpenImage(contrastedImage)

        // Step 4: Reduce noise
        let cleanedImage = reduceNoise(sharpenedImage)

        // Convert back to a platform image
        guard let cgOut = context.createCGImage(cleanedImage, from: cleanedImage.extent) else {
            return jpegData(image, quality: compressionQuality)
        }

        guard let processedImage = platformImage(cgOut, size: cleanedImage.extent.size) else {
            return jpegData(image, quality: compressionQuality)
        }
        return jpegData(processedImage, quality: compressionQuality)
    }

    /// Quick preprocessing with just contrast and sharpening (preserves color)
    func preprocessLightweight(_ image: PlatformImage, compressionQuality: CGFloat = 0.9) -> Data? {
        guard let inputImage = ciImage(image) else {
            return jpegData(image, quality: compressionQuality)
        }

        let contrastedImage = enhanceContrast(inputImage)
        let sharpenedImage = sharpenImage(contrastedImage)

        guard let cgOut = context.createCGImage(sharpenedImage, from: sharpenedImage.extent) else {
            return jpegData(image, quality: compressionQuality)
        }

        guard let processedImage = platformImage(cgOut, size: sharpenedImage.extent.size) else {
            return jpegData(image, quality: compressionQuality)
        }
        return jpegData(processedImage, quality: compressionQuality)
    }

    // MARK: - Individual Filters

    private func applyGrayscale(to image: CIImage) -> CIImage {
        let filter = CIFilter.photoEffectMono()
        filter.inputImage = image
        return filter.outputImage ?? image
    }

    private func enhanceContrast(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.contrast = 1.5  // Increase contrast significantly
        filter.brightness = 0.1
        return filter.outputImage ?? image
    }

    private func sharpenImage(_ image: CIImage) -> CIImage {
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = image
        filter.sharpness = 0.7
        return filter.outputImage ?? image
    }

    private func reduceNoise(_ image: CIImage) -> CIImage {
        let filter = CIFilter.noiseReduction()
        filter.inputImage = image
        filter.noiseLevel = 0.02
        filter.sharpness = 0.8
        return filter.outputImage ?? image
    }

    /// Create a side-by-side comparison of original and processed images
    func createComparisonImage(original: PlatformImage, processed: PlatformImage) -> PlatformImage? {
        let size = CGSize(width: original.size.width * 2, height: original.size.height)
        guard size.width > 0, size.height > 0 else { return nil }
        #if canImport(UIKit)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        original.draw(in: CGRect(x: 0, y: 0, width: original.size.width, height: original.size.height))
        processed.draw(in: CGRect(x: original.size.width, y: 0, width: original.size.width, height: original.size.height))
        return UIGraphicsGetImageFromCurrentImageContext()
        #elseif canImport(AppKit)
        let composite = NSImage(size: size)
        composite.lockFocus()
        original.draw(in: CGRect(x: 0, y: 0, width: original.size.width, height: original.size.height))
        processed.draw(in: CGRect(x: original.size.width, y: 0, width: original.size.width, height: original.size.height))
        composite.unlockFocus()
        return composite
        #else
        return nil
        #endif
    }

    /// Reduce image size to stay under a target size in bytes
    /// This uses progressive compression and resizing to meet the target
    /// Optimized for text extraction - prioritizes smaller file sizes
    /// - Parameters:
    ///   - image: The input image to reduce
    ///   - maxSizeBytes: Maximum size in bytes (default 20KB for text extraction)
    /// - Returns: Data representation of the reduced image, or nil if failed
    func reduceImageSize(_ image: PlatformImage, maxSizeBytes: Int = 20_000) -> Data? {
        AppLog.info("Reducing image size, target: \(maxSizeBytes) bytes (~\(maxSizeBytes / 1024)KB)", category: .image)
        AppLog.debug("Original image size: \(image.size.width) x \(image.size.height)", category: .image)

        // For small targets (like 10-20KB), we need aggressive resizing first
        // Text recognition works well even with heavily reduced images
        let maxDimension: CGFloat = 1024 // Maximum width or height
        var workingImage = image

        // First pass: Resize to reasonable dimensions if needed
        if image.size.width > maxDimension || image.size.height > maxDimension {
            let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            AppLog.debug("Initial resize to \(newSize.width) x \(newSize.height)", category: .image)

            if let resized = resizeImage(image, to: newSize) {
                workingImage = resized
            }
        }

        // Try aggressive compression first on resized image
        let compressionQualities: [CGFloat] = [0.5, 0.4, 0.3, 0.2, 0.15, 0.1]

        for quality in compressionQualities {
            if let data = jpegData(workingImage, quality: quality) {
                AppLog.debug("Compression quality \(quality): \(data.count) bytes (~\(data.count / 1024)KB)", category: .image)
                if data.count <= maxSizeBytes {
                    AppLog.info("Image reduced to \(data.count) bytes (~\(data.count / 1024)KB) with compression \(quality)", category: .image)
                    return data
                }
            }
        }

        // If still too large, progressively reduce dimensions
        AppLog.debug("Compression alone insufficient, applying progressive resizing", category: .image)

        // More aggressive resize factors for small file targets
        let resizeFactors: [CGFloat] = [0.8, 0.6, 0.5, 0.4, 0.35, 0.3, 0.25, 0.2]

        for factor in resizeFactors {
            let newSize = CGSize(
                width: workingImage.size.width * factor,
                height: workingImage.size.height * factor
            )

            AppLog.debug("Trying resize to \(Int(newSize.width)) x \(Int(newSize.height)) (factor: \(factor))", category: .image)

            guard let resizedImage = resizeImage(workingImage, to: newSize) else {
                AppLog.warning("Failed to resize image to \(newSize)", category: .image)
                continue
            }

            // Try multiple compression qualities on this size
            for quality in compressionQualities {
                if let data = jpegData(resizedImage, quality: quality) {
                    if data.count <= maxSizeBytes {
                        AppLog.info("Image reduced to \(data.count) bytes (~\(data.count / 1024)KB) with resize factor \(factor) and compression \(quality)", category: .image)
                        AppLog.debug("Final dimensions: \(Int(newSize.width)) x \(Int(newSize.height))", category: .image)
                        return data
                    }
                }
            }
        }

        // Last resort: Very small image with heavy compression
        // Even a 200x200 image is usually enough for text recognition
        AppLog.warning("Using last resort: minimal dimensions with heavy compression", category: .image)
        let minDimension = min(workingImage.size.width, workingImage.size.height)
        let targetMinDimension: CGFloat = 200
        let finalScale = targetMinDimension / minDimension

        let finalSize = CGSize(
            width: workingImage.size.width * finalScale,
            height: workingImage.size.height * finalScale
        )

        if let finalResize = resizeImage(workingImage, to: finalSize),
           let finalData = jpegData(finalResize, quality: 0.1) {
            AppLog.info("Final image size: \(finalData.count) bytes (~\(finalData.count / 1024)KB)", category: .image)
            AppLog.debug("Final dimensions: \(Int(finalSize.width)) x \(Int(finalSize.height))", category: .image)
            return finalData
        }

        AppLog.error("Failed to reduce image to target size", category: .image)
        return nil
    }

    /// Resize an image to a target size while maintaining aspect ratio
    private func resizeImage(_ image: PlatformImage, to targetSize: CGSize) -> PlatformImage? {
        let size = image.size

        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height

        // Use the smaller ratio to maintain aspect ratio
        let ratio = min(widthRatio, heightRatio)

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let rect = CGRect(origin: .zero, size: newSize)

        guard newSize.width > 0, newSize.height > 0 else { return nil }
        #if canImport(UIKit)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: rect)
        return UIGraphicsGetImageFromCurrentImageContext()
        #elseif canImport(AppKit)
        guard let cg = cgImage(image) else { return nil }
        let width = Int(newSize.width)
        let height = Int(newSize.height)
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: rect)
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: newSize)
        #else
        return nil
        #endif
    }
}
