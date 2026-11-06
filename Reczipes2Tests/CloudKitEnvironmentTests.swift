//
//  CloudKitEnvironmentTests.swift
//  Reczipes2Tests
//
//  The committed project must build for CloudKit Production. A build pointed at
//  Development reads a separate library (Lane 37, 2026-11-06), so Xcode Cloud fails
//  this test if RECZIPES_CLOUDKIT_ENVIRONMENT or the entitlement was committed
//  as Development. Priming a record type in Development is a local, uncommitted run.
//

import Testing
import Foundation
@testable import Reczipes2

@Suite("CloudKit environment")
@MainActor
struct CloudKitEnvironmentTests {

    @Test("App is built for CloudKit Production")
    func builtForProduction() {
        #expect(Bundle.main.infoDictionary?["ReczipesCloudKitEnvironment"] as? String == "Production")
        #expect(AppBuildInfo.isCloudKitDevelopment == false)
    }

    @Test("Production keeps the original store file; Development has its own")
    func storeFileName() {
        #expect(AppBuildInfo.localStoreFileName == "CloudKitModel.sqlite")
    }
}
