//
//  AppBuildInfo.swift
//  Reczipes2
//
//  The build number App Store Connect shows is assigned by Xcode Cloud (CI_BUILD_NUMBER) and written into the
//  binary by ci_scripts/ci_post_clone.sh, which also marks Info.plist with ReczipesBuildSource = "xcode-cloud".
//  A build run from Xcode on a Mac carries whatever CURRENT_PROJECT_VERSION the project file last stored; that
//  is not an App Store Connect build number and is never shown as one.
//

import Foundation
#if os(macOS)
import Security
#endif

enum AppBuildInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    /// True when Xcode Cloud built this binary, so `build` is the App Store Connect build number.
    static var isXcodeCloudBuild: Bool {
        (Bundle.main.infoDictionary?["ReczipesBuildSource"] as? String) == "xcode-cloud"
    }

    /// The CloudKit environment this binary was signed for. One build setting,
    /// RECZIPES_CLOUDKIT_ENVIRONMENT (app target), feeds both the entitlement and this
    /// Info.plist key, so they cannot disagree. Production unless deliberately changed
    /// (e.g. to prime a new record type in Development; see Lane 37 Δ-113).
    static var cloudKitEnvironment: String {
        #if os(macOS)
        // On the Mac the signed entitlement itself can be read; it wins if the
        // entitlements file was edited by hand instead of the build setting.
        if let signed = signedCloudKitEnvironment { return signed }
        #endif
        let value = Bundle.main.infoDictionary?["ReczipesCloudKitEnvironment"] as? String ?? ""
        return value == "Development" ? "Development" : "Production"
    }

    #if os(macOS)
    private static let signedCloudKitEnvironment: String? = {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-environment" as CFString, nil)
                as? String else { return nil }
        return value == "Development" ? "Development" : "Production"
    }()
    #endif

    static var isCloudKitDevelopment: Bool { cloudKitEnvironment == "Development" }

    /// Local store file for this environment. Production keeps the original name (no
    /// migration); Development gets its own file, so switching environments never mixes
    /// the two databases in one store (the mixed library of 2026-11-06).
    static var localStoreFileName: String {
        isCloudKitDevelopment ? "CloudKitModel-Development.sqlite" : "CloudKitModel.sqlite"
    }

    /// "20.0 (214)" for an Xcode Cloud build; a local Xcode build says so instead of showing a stale number.
    static var statusLine: String {
        isXcodeCloudBuild
            ? "Version \(version) (\(build))"
            : "Version \(version) · local Xcode build — no App Store Connect build number"
    }

    /// Shown under the version in Settings → Status.
    static var cloudKitLine: String {
        isCloudKitDevelopment
            ? "iCloud: DEVELOPMENT database — separate library; set RECZIPES_CLOUDKIT_ENVIRONMENT back to Production before release"
            : "iCloud: Production"
    }
}
