//
//  ImageHashService.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/20/26.
//


import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import CryptoKit

class ImageHashService {

    /// Generate perceptual hash for duplicate detection
    func generateHash(for image: PlatformImage) -> String? {
        guard let resized = resizeImage(image, to: CGSize(width: 8, height: 8)),
              let pixels = getGrayscalePixels(from: resized) else {
            return nil
        }

        let average = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        let hash = pixels.map { $0 > average ? "1" : "0" }.joined()

        return hash
    }

    /// Calculate similarity between two hashes (0.0 to 1.0)
    func similarity(hash1: String, hash2: String) -> Double {
        guard hash1.count == hash2.count else { return 0.0 }

        let matches = zip(hash1, hash2).filter { $0 == $1 }.count
        return Double(matches) / Double(hash1.count)
    }

    // MARK: - Private Helpers

    private func resizeImage(_ image: PlatformImage, to size: CGSize) -> PlatformImage? {
        #if canImport(UIKit)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resized
        #elseif canImport(AppKit)
        guard let cgImage = image.cgImage else { return nil }
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        guard let resizedCG = context.makeImage() else { return nil }
        return NSImage(cgImage: resizedCG, size: size)
        #else
        return nil
        #endif
    }

    private func getGrayscalePixels(from image: PlatformImage) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 1
        let bytesPerRow = bytesPerPixel * width
        let totalBytes = bytesPerRow * height

        var pixels = [UInt8](repeating: 0, count: totalBytes)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return pixels
    }
}
