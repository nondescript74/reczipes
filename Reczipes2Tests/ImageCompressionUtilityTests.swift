//
//  ImageCompressionUtilityTests.swift
//  Reczipes2Tests
//
//  Tests for image compression utility
//

import Testing
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import Reczipes2

/// Tests for the ImageCompressionUtility
struct ImageCompressionUtilityTests {

    /// Test that compression produces data under target size
    @MainActor @Test("Compress image under 100KB")
    func testCompressImageUnderTarget() throws {
        // Create a large test image
        let size = CGSize(width: 3000, height: 3000)
        let testImage = TestImageRenderer.image(size: size) { context in
            TestColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Add some detail
            TestColor.red.setFill()
            for i in 0..<100 {
                let rect = CGRect(x: CGFloat(i * 30), y: CGFloat(i * 30), width: 50, height: 50)
                context.fill(rect)
            }
        }

        // Compress the image
        guard let compressedData = ImageCompressionUtility.compressImage(testImage) else {
            throw TestError("Failed to compress image")
        }

        // Verify size is under 100KB
        #expect(compressedData.count <= 100_000, "Compressed image should be under 100KB, got \(compressedData.count) bytes")

        // Verify we can decode it back
        let decodedImage = PlatformImage(data: compressedData)
        #expect(decodedImage != nil, "Should be able to decode compressed image")
    }

    /// Test that small images are not unnecessarily compressed
    @MainActor @Test("Small image stays small")
    func testSmallImageStaysSmall() throws {
        // Create a small test image
        let size = CGSize(width: 200, height: 200)
        let testImage = TestImageRenderer.image(size: size) { context in
            TestColor.green.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        // Compress the image
        guard let compressedData = ImageCompressionUtility.compressImage(testImage) else {
            throw TestError("Failed to compress image")
        }

        // Small images should be well under target
        #expect(compressedData.count <= 100_000, "Compressed image should be under 100KB")
        print("Small image size: \(ImageCompressionUtility.formatSize(compressedData.count))")
    }

    /// Test thumbnail compression
    @MainActor @Test("Thumbnail compression under 50KB")
    func testThumbnailCompression() throws {
        // Create a test image
        let size = CGSize(width: 2000, height: 2000)
        let testImage = TestImageRenderer.image(size: size) { context in
            TestColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        // Compress as thumbnail
        guard let thumbnailData = ImageCompressionUtility.compressForThumbnail(testImage) else {
            throw TestError("Failed to compress thumbnail")
        }

        // Verify size is under 50KB
        #expect(thumbnailData.count <= 50_000, "Thumbnail should be under 50KB, got \(thumbnailData.count) bytes")
        print("Thumbnail size: \(ImageCompressionUtility.formatSize(thumbnailData.count))")
    }

    /// Test book cover compression
    @MainActor @Test("Book cover compression under 150KB")
    func testBookCoverCompression() throws {
        // Create a test image
        let size = CGSize(width: 2000, height: 2000)
        let testImage = TestImageRenderer.image(size: size) { context in
            TestColor.purple.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Add more detail for book covers
            TestColor.yellow.setFill()
            for i in 0..<200 {
                let rect = CGRect(x: CGFloat(i * 10), y: CGFloat(i * 10), width: 30, height: 30)
                context.fill(rect)
            }
        }

        // Compress as book cover
        guard let coverData = ImageCompressionUtility.compressForBookCover(testImage) else {
            throw TestError("Failed to compress book cover")
        }

        // Verify size is under 150KB
        #expect(coverData.count <= 150_000, "Book cover should be under 150KB, got \(coverData.count) bytes")
        print("Book cover size: \(ImageCompressionUtility.formatSize(coverData.count))")
    }

    /// Test resize if needed
    @MainActor @Test("Resize large image dimensions")
    func testResizeIfNeeded() throws {
        // Create a very large test image
        let size = CGSize(width: 5000, height: 3000)
        let testImage = TestImageRenderer.image(size: size) { context in
            TestColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        // Resize
        let resizedImage = ImageCompressionUtility.resizeIfNeeded(testImage, maxDimension: 2048)

        // Verify dimensions are within max
        #expect(resizedImage.size.width <= 2048, "Width should be at most 2048")
        #expect(resizedImage.size.height <= 2048, "Height should be at most 2048")

        // Verify aspect ratio is maintained (approximately)
        let originalRatio = size.width / size.height
        let resizedRatio = resizedImage.size.width / resizedImage.size.height
        let ratioDiff = abs(originalRatio - resizedRatio)
        #expect(ratioDiff < 0.01, "Aspect ratio should be maintained")
    }

    /// Test format size helper
    @MainActor @Test("Format size string")
    func testFormatSize() throws {
        let size1 = ImageCompressionUtility.formatSize(1024)
        #expect(size1.contains("KB") || size1.contains("bytes"))

        let size2 = ImageCompressionUtility.formatSize(100_000)
        #expect(size2.contains("KB"))

        let size3 = ImageCompressionUtility.formatSize(1_500_000)
        #expect(size3.contains("MB") || size3.contains("KB"))
    }
}

/// Custom error for testing
struct TestError: Error, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String {
        return message
    }
}
