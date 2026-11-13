//
//  AccountChangeDecisionTests.swift
//  Reczipes2Tests
//
//  An iCloud account-change notice may switch the store only on a definite answer.
//  Transient statuses (common around wake and app activation) must change nothing.
//

import Testing
import CloudKit
@testable import Reczipes2

@Suite("iCloud account-change decision")
struct AccountChangeDecisionTests {

    @Test("available turns iCloud on")
    func available() {
        #expect(ModelContainerManager.definiteAvailability(for: .available) == true)
    }

    @Test("no account and restricted turn iCloud off")
    func definitelyOff() {
        #expect(ModelContainerManager.definiteAvailability(for: .noAccount) == false)
        #expect(ModelContainerManager.definiteAvailability(for: .restricted) == false)
    }

    @Test("transient statuses leave the store alone")
    func transientIsNoChange() {
        #expect(ModelContainerManager.definiteAvailability(for: .couldNotDetermine) == nil)
        #expect(ModelContainerManager.definiteAvailability(for: .temporarilyUnavailable) == nil)
    }
}
