//
//  DiabeticInfoPublishTests.swift
//  Reczipes2Tests
//
//  The Diabetic-Friendly Analysis travels inside CloudKitRecipe JSON so the web shows it.
//

import Testing
import Foundation
@testable import Reczipes2

@Suite("Diabetic analysis on the public recipe")
@MainActor
struct DiabeticInfoPublishTests {
    private func recipe(_ json: String? = nil) -> CloudKitRecipe {
        var r = CloudKitRecipe(
            id: UUID(), title: "Rice", headerNotes: nil, yield: nil,
            ingredientSections: [], instructionSections: [], notes: [],
            reference: nil, imageName: nil, additionalImageNames: nil,
            sharedByUserID: "u", sharedByUserName: "Z",
            sharedDate: Date(timeIntervalSinceReferenceDate: 1_000)
        )
        r.diabeticInfoJSON = json
        return r
    }

    @Test("The analysis JSON round-trips as a string field")
    func roundTrip() throws {
        let analysis = #"{"consensusLevel":"moderateConsensus","carbCount":{"totalCarbs":45,"netCarbs":41,"fiber":4}}"#
        let data = try JSONEncoder().encode(recipe(analysis))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["diabeticInfoJSON"] as? String == analysis)
        let decoded = try JSONDecoder().decode(CloudKitRecipe.self, from: data)
        #expect(decoded.diabeticInfoJSON == analysis)
    }

    @Test("Records written before the field existed still decode")
    func olderRecordsDecode() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe())) as? [String: Any])
        object.removeValue(forKey: "diabeticInfoJSON")
        let decoded = try JSONDecoder().decode(CloudKitRecipe.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.diabeticInfoJSON == nil)
        #expect(decoded.title == "Rice")
    }

    @Test("A recipe with no analysis writes no key")
    func absentWhenNil() throws {
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe())) as? [String: Any])
        #expect(object["diabeticInfoJSON"] == nil)
    }
}
