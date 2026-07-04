//
//  PlatformCompat.swift
//  Reczipes2
//
//  Cross-platform shims for iOS/macOS. Provides PlatformImage/PlatformColor
//  typealiases and small extensions that make NSImage/NSColor look enough
//  like UIImage/UIColor for the shared code paths in this project.
//

import Foundation
import CoreGraphics
import CoreImage
import SwiftUI

#if canImport(UIKit)
import UIKit

public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit

public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor

extension NSImage {
    /// Data initializer parity with UIImage(data:).
    convenience init?(data: Data, scale: CGFloat) {
        self.init(data: data)
    }

    /// Approximate parity with UIImage.jpegData(compressionQuality:).
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiff = self.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    /// Approximate parity with UIImage.pngData().
    func pngData() -> Data? {
        guard let tiff = self.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Underlying CGImage for pixel operations.
    var cgImage: CGImage? {
        var rect = NSRect(origin: .zero, size: self.size)
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Approximate parity with UIImage.scale (macOS is always 1.0 in points-vs-pixels API terms).
    var scale: CGFloat { 1.0 }

    /// Parity with UIImage(cgImage:) — NSImage requires an explicit size.
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
#endif

/// Cross-platform image renderer used to redraw PlatformImages into a new bitmap.
/// Mirrors the common iOS pattern of `UIGraphicsBeginImageContextWithOptions` / `UIGraphicsGetImageFromCurrentImageContext`.
enum PlatformImageRenderer {
    static func render(size: CGSize, opaque: Bool = false, draw: (CGContext) -> Void) -> PlatformImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = opaque
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            draw(ctx.cgContext)
        }
        #elseif canImport(AppKit)
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // NSGraphicsContext lets NSImage.draw(in:) work against our CGContext.
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        draw(context)
        NSGraphicsContext.current = previous

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: size)
        #else
        return nil
        #endif
    }
}

extension Image {
    /// Build a SwiftUI Image from a PlatformImage without caring about platform.
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

extension CIImage {
    /// Cross-platform `CIImage` from a `PlatformImage`. SwiftUI's `CIImage(image:)`
    /// only accepts `UIImage` (iOS-only); on macOS this routes through the backing
    /// CGImage so the same call works on both platforms.
    convenience init?(platformImage image: PlatformImage) {
        guard let cg = image.cgImage else { return nil }
        self.init(cgImage: cg)
    }
}

extension PlatformImage {
    /// Cross-platform SF Symbol image. `UIImage(systemName:)` on iOS,
    /// `NSImage(systemSymbolName:accessibilityDescription:)` on macOS.
    static func systemSymbol(_ name: String) -> PlatformImage? {
        #if canImport(UIKit)
        return UIImage(systemName: name)
        #elseif canImport(AppKit)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        #else
        return nil
        #endif
    }
}

extension View {
    /// Cross-platform full-screen cover. Uses `.fullScreenCover` on iOS,
    /// falls back to `.sheet` on macOS where the modifier is unavailable.
    @ViewBuilder
    func platformFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #else
        self.sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }
}

/// Cross-platform analogue of `NavigationBarItem.TitleDisplayMode`, which is a
/// UIKit-backed type unavailable on macOS. Used with `platformNavigationBarTitleDisplayMode`.
enum PlatformTitleDisplayMode {
    case automatic
    case inline
    case large
}

extension View {
    /// Cross-platform navigation bar title display mode. The SwiftUI
    /// `.platformNavigationBarTitleDisplayMode(_:)` modifier and its argument type are
    /// unavailable on macOS, so this shim applies the mode on iOS and is a
    /// no-op elsewhere.
    @ViewBuilder
    func platformNavigationBarTitleDisplayMode(_ mode: PlatformTitleDisplayMode) -> some View {
        #if os(iOS)
        switch mode {
        case .automatic:
            self.navigationBarTitleDisplayMode(.automatic)
        case .inline:
            self.navigationBarTitleDisplayMode(.inline)
        case .large:
            self.navigationBarTitleDisplayMode(.large)
        }
        #else
        self
        #endif
    }
}

extension Color {
    /// Cross-platform system background — UIColor.systemBackground on iOS,
    /// NSColor.windowBackgroundColor on macOS.
    static var appSystemBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(.sRGB, white: 1.0, opacity: 1.0)
        #endif
    }

    /// Cross-platform secondary background (grouped table cell / control background).
    static var appSecondaryBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }

    /// Cross-platform tertiary background.
    static var appTertiaryBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.tertiarySystemBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.underPageBackgroundColor)
        #else
        return Color.gray.opacity(0.15)
        #endif
    }

    /// Cross-platform grouped background (grouped table view background).
    static var appGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }

    /// Cross-platform secondary grouped background (grouped table cell).
    static var appSecondaryGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color.gray.opacity(0.12)
        #endif
    }

    /// Cross-platform systemGray6 (lightest system gray fill).
    static var appGray6: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGray6)
        #elseif canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color.gray.opacity(0.12)
        #endif
    }

    /// Cross-platform systemGray5.
    static var appGray5: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGray5)
        #elseif canImport(AppKit)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color.gray.opacity(0.18)
        #endif
    }

    /// Cross-platform systemGray4.
    static var appGray4: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGray4)
        #elseif canImport(AppKit)
        return Color(NSColor.separatorColor)
        #else
        return Color.gray.opacity(0.24)
        #endif
    }
}

// MARK: - Cross-platform toolbar / control shims (iOS-only SwiftUI on macOS)

extension ToolbarItemPlacement {
    /// Leading nav-bar placement on iOS; `.automatic` on macOS (topBarLeading /
    /// navigationBarLeading are iOS-only).
    static var platformNavBarLeading: ToolbarItemPlacement {
        #if os(iOS)
        return .navigationBarLeading
        #else
        return .automatic
        #endif
    }

    /// Trailing nav-bar placement on iOS; `.automatic` on macOS.
    static var platformNavBarTrailing: ToolbarItemPlacement {
        #if os(iOS)
        return .navigationBarTrailing
        #else
        return .automatic
        #endif
    }
}

/// Cross-platform `EditButton` — iOS toggles edit mode; macOS has no equivalent,
/// so this renders nothing.
struct PlatformEditButton: View {
    var body: some View {
        #if os(iOS)
        EditButton()
        #else
        EmptyView()
        #endif
    }
}

extension View {
    /// Inset-grouped list style on iOS; `.inset` on macOS (`.insetGrouped` is iOS-only).
    @ViewBuilder
    func platformInsetGroupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    /// Navigation-link picker style on iOS; `.menu` on macOS (`.navigationLink` is iOS-only).
    @ViewBuilder
    func platformNavigationLinkPickerStyle() -> some View {
        #if os(iOS)
        self.pickerStyle(.navigationLink)
        #else
        self.pickerStyle(.menu)
        #endif
    }
}

/// Cross-platform device identifier for tagging recipe/book modifications.
/// On iOS this is `UIDevice.identifierForVendor`; on macOS a stable per-user UUID
/// persisted in UserDefaults (there is no direct equivalent).
enum PlatformDevice {
    static var identifier: String? {
        #if canImport(UIKit) && os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString
        #else
        let key = "com.reczipes.platformDeviceIdentifier"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
        #endif
    }
}

// MARK: - iOS-only SwiftUI modifier shims (no-ops on macOS)

/// Cross-platform keyboard type. `UIKeyboardType` and the `.platformKeyboardType(_:)`
/// modifier are unavailable on macOS.
enum PlatformKeyboardType {
    case `default`
    case URL
    case numberPad
    case decimalPad
    case emailAddress
    case numbersAndPunctuation
}

extension View {
    @ViewBuilder
    func platformKeyboardType(_ type: PlatformKeyboardType) -> some View {
        #if os(iOS)
        switch type {
        case .default:               self.keyboardType(.default)
        case .URL:                   self.keyboardType(.URL)
        case .numberPad:             self.keyboardType(.numberPad)
        case .decimalPad:            self.keyboardType(.decimalPad)
        case .emailAddress:          self.keyboardType(.emailAddress)
        case .numbersAndPunctuation: self.keyboardType(.numbersAndPunctuation)
        }
        #else
        self
        #endif
    }
}

/// Cross-platform text autocapitalization. The `.platformTextInputAutocapitalization(_:)`
/// modifier and its argument type are unavailable on macOS.
enum PlatformTextAutocapitalization {
    case never
    case words
    case sentences
    case characters
}

extension View {
    @ViewBuilder
    func platformTextInputAutocapitalization(_ mode: PlatformTextAutocapitalization) -> some View {
        #if os(iOS)
        switch mode {
        case .never:      self.textInputAutocapitalization(.never)
        case .words:      self.textInputAutocapitalization(.words)
        case .sentences:  self.textInputAutocapitalization(.sentences)
        case .characters: self.textInputAutocapitalization(.characters)
        }
        #else
        self
        #endif
    }
}

/// Cross-platform paged `TabView` style. `PageTabViewStyle` / `IndexDisplayMode`
/// are iOS-only; on macOS this falls back to the default tab style.
enum PlatformIndexDisplayMode {
    case always
    case never
    case automatic
}

extension View {
    @ViewBuilder
    func platformPageTabViewStyle(indexDisplayMode: PlatformIndexDisplayMode) -> some View {
        #if os(iOS)
        switch indexDisplayMode {
        case .always:    self.tabViewStyle(.page(indexDisplayMode: .always))
        case .never:     self.tabViewStyle(.page(indexDisplayMode: .never))
        case .automatic: self.tabViewStyle(.page(indexDisplayMode: .automatic))
        }
        #else
        self
        #endif
    }
}

/// Cross-platform paged index view style (the dots for a paged TabView). iOS-only.
enum PlatformIndexViewBackgroundDisplayMode {
    case always
    case never
    case interactive
    case automatic
}

extension View {
    @ViewBuilder
    func platformPageIndexViewStyle(backgroundDisplayMode: PlatformIndexViewBackgroundDisplayMode) -> some View {
        #if os(iOS)
        switch backgroundDisplayMode {
        case .always:      self.indexViewStyle(.page(backgroundDisplayMode: .always))
        case .never:       self.indexViewStyle(.page(backgroundDisplayMode: .never))
        case .interactive: self.indexViewStyle(.page(backgroundDisplayMode: .interactive))
        case .automatic:   self.indexViewStyle(.page(backgroundDisplayMode: .automatic))
        }
        #else
        self
        #endif
    }
}

/// Cross-platform sheet presentation detents. `.platformPresentationDetents(_:)` requires
/// iOS 16+ and is unavailable on macOS.
enum PlatformPresentationDetent {
    case medium
    case large
}

extension View {
    @ViewBuilder
    func platformPresentationDetents(_ detents: Set<PlatformPresentationDetent>) -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            var mapped: Set<PresentationDetent> = []
            if detents.contains(.medium) { mapped.insert(.medium) }
            if detents.contains(.large) { mapped.insert(.large) }
            self.presentationDetents(mapped)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Cross-platform `.platformNavigationBarHidden(_:)` — iOS-only modifier; no-op on macOS.
    @ViewBuilder
    func platformNavigationBarHidden(_ hidden: Bool) -> some View {
        #if os(iOS)
        self.navigationBarHidden(hidden)
        #else
        self
        #endif
    }
}

// MARK: - Cross-platform image / document / share helpers

/// Cross-platform analogue of `UIImagePickerController.SourceType` (which is
/// UIKit-only). Used by the shared `ImagePicker` on both platforms.
enum ImagePickerSourceType {
    case photoLibrary
    case camera
}

/// Cross-platform clipboard access. `UIPasteboard` on iOS, `NSPasteboard` on macOS.
enum PlatformPasteboard {
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    static var string: String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}

/// Cross-platform URL opening. `UIApplication.shared.open` on iOS,
/// `NSWorkspace.shared.open` on macOS.
enum PlatformURLOpener {
    static func open(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    /// URL string for the system/app settings. iOS opens the app's settings
    /// pane; macOS opens System Settings (no per-app deep link exists).
    #if os(iOS)
    static let settingsURLString = UIApplication.openSettingsURLString
    #elseif os(macOS)
    static let settingsURLString = "x-apple.systempreferences:"
    #else
    static let settingsURLString = ""
    #endif
}

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// macOS file-picking helpers backed by `NSOpenPanel`.
enum MacFilePicker {
    /// Present an open panel and return the chosen images. Runs modally.
    @MainActor
    static func pickImages(allowsMultiple: Bool) -> [PlatformImage] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { NSImage(contentsOf: $0) }
    }
}

/// macOS share affordance backed by `NSSharingServicePicker`. Presents the
/// standard share menu anchored to itself when it appears.
struct MacShareView: NSViewRepresentable {
    let items: [Any]

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        DispatchQueue.main.async {
            guard !items.isEmpty else { return }
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: container.bounds, of: container, preferredEdge: .minY)
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
