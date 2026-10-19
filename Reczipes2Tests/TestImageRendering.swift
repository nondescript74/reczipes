//
//  TestImageRendering.swift
//  Reczipes2Tests
//
//  Cross-platform image drawing for tests, so image tests run on iOS and macOS.
//  UIKit: UIGraphicsImageRenderer. AppKit: NSImage drawing handler (flipped, so
//  y grows downward exactly as in UIKit and text/rects land in the same place).
//

import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
typealias TestColor = UIColor
typealias TestFont = UIFont
#elseif canImport(AppKit)
import AppKit
typealias TestColor = NSColor
typealias TestFont = NSFont
#endif
@testable import Reczipes2

/// Minimal drawing context passed to `TestImageRenderer.image` closures.
/// Mirrors the subset of `UIGraphicsImageRendererContext` the tests use.
struct TestDrawingContext {
    let cgContext: CGContext

    /// Fills `rect` with the current fill color (set via `TestColor.setFill()`).
    func fill(_ rect: CGRect) {
        cgContext.fill(rect)
    }
}

enum TestImageRenderer {
    /// Draws an image of `size` points on the current platform.
    static func image(size: CGSize, _ draw: (TestDrawingContext) -> Void) -> PlatformImage {
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(TestDrawingContext(cgContext: context.cgContext))
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        if let cg = NSGraphicsContext.current?.cgContext {
            draw(TestDrawingContext(cgContext: cg))
        }
        image.unlockFocus()
        return image
        #endif
    }
}
