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

    /// "20.0 (214)" for an Xcode Cloud build; a local Xcode build says so instead of showing a stale number.
    static var statusLine: String {
        isXcodeCloudBuild
            ? "Version \(version) (\(build))"
            : "Version \(version) · local Xcode build — no App Store Connect build number"
    }
}
