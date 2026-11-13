//
//  DiabeticBackfillTests.swift
//  Reczipes2Tests
//
//  Lane 37 (2026-11-13): the automatic Diabetic-Friendly Analysis pass. What it sends, what it
//  reads back, which recipes it asks about, and that it never pays twice for the same recipe.
//

import Testing
import Foundation
@testable import Reczipes2

@Suite("Diabetic analysis batch pass")
@MainActor
struct DiabeticBackfillTests {

    // MARK: Which recipes need what

    private func need(hasIngredients: Bool = true, hasStoredDate: Bool = true, publicHas: Bool = false,
                      current: Bool = false, publishable: Bool = true,
                      claimed: Bool = false, unusable: Bool = false) -> DiabeticBackfillPlan.Need {
        DiabeticBackfillPlan.need(hasIngredients: hasIngredients, hasStoredDate: hasStoredDate,
                                  publicHasAnalysis: publicHas, cachedIsCurrent: current,
                                  cachedIsPublishable: publishable, claimed: claimed,
                                  unusableForTheseIngredients: unusable)
    }

    @Test("A recipe with no analysis anywhere is analyzed")
    func analyzesTheMissing() { #expect(need() == .analyze) }

    @Test("A public copy that has an analysis is left alone")
    func publicHasIt() {
        #expect(need(publicHas: true) == .nothing)
        #expect(need(publicHas: true, current: true) == .nothing)
    }

    @Test("A current cached analysis is published, not paid for again")
    func cachedIsPublished() {
        #expect(need(current: true) == .publish)
        #expect(need(current: true, claimed: true) == .publish)
    }

    @Test("A current analysis too large to publish is not asked for again")
    func oversizeIsNotReasked() { #expect(need(current: true, publishable: false) == .nothing) }

    @Test("Claimed, unusable, ingredient-less and undated recipes are not sent")
    func skips() {
        #expect(need(claimed: true) == .nothing)
        #expect(need(unusable: true) == .nothing)
        #expect(need(hasIngredients: false) == .nothing)
        #expect(need(hasStoredDate: false) == .nothing)
    }

    // MARK: What is sent

    @Test("The batch body carries one request per recipe on Opus 5.5, keyed by recipe id")
    func requestBody() throws {
        let a = UUID(), b = UUID()
        let data = try DiabeticBackfillPlan.requestBody([(a, "prompt A"), (b, "prompt B")])
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let requests = try #require(object["requests"] as? [[String: Any]])
        #expect(requests.count == 2)
        let first = requests[0]
        let id = try #require(first["custom_id"] as? String)
        #expect(id == a.uuidString)
        #expect(id.range(of: "^[a-zA-Z0-9_-]{1,64}$", options: .regularExpression) != nil)
        let params = try #require(first["params"] as? [String: Any])
        #expect(params["model"] as? String == "claude-opus-5-5")
        #expect(params["max_tokens"] as? Int == 32_000)
        let messages = try #require(params["messages"] as? [[String: Any]])
        #expect(messages.first?["role"] as? String == "user")
        #expect(messages.first?["content"] as? String == "prompt A")
    }

    @Test("The prompt says Claude has no web access and no longer demands 2023-2025 sources")
    func promptSources() throws {
        let sections = [IngredientSection(ingredients: [Ingredient(quantity: "1", unit: "cup", name: "rice")])]
        let recipe = RecipeX(title: "Rice", ingredientSectionsData: try JSONEncoder().encode(sections))
        let prompt = DiabeticAnalysisService.shared.buildAnalysisPrompt(recipe)
        #expect(prompt.contains("NO web access"))
        #expect(prompt.contains("Never invent a URL"))
        #expect(!prompt.contains("2023-2025"))
        #expect(prompt.contains("rice"))
    }

    // MARK: What comes back

    @Test("Results are read by recipe id: answers, cut-off replies, errors and expiries")
    func readsResults() throws {
        let ok = UUID(), cut = UUID(), busy = UUID(), invalid = UUID(), expired = UUID()
        func message(_ text: String, stop: String) -> String {
            #"{"type":"succeeded","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","content":[{"type":"text","text":"\#(text)"}],"stop_reason":"\#(stop)","usage":{"input_tokens":1,"output_tokens":1}}}"#
        }
        let lines = [
            #"{"custom_id":"\#(ok.uuidString)","result":\#(message("{}", stop: "end_turn"))}"#,
            #"{"custom_id":"\#(cut.uuidString)","result":\#(message("{", stop: "max_tokens"))}"#,
            #"{"custom_id":"\#(busy.uuidString)","result":{"type":"errored","error":{"type":"error","error":{"type":"overloaded_error","message":"busy"}}}}"#,
            #"{"custom_id":"\#(invalid.uuidString)","result":{"type":"errored","error":{"type":"error","error":{"type":"invalid_request_error","message":"bad"}}}}"#,
            #"{"custom_id":"\#(expired.uuidString)","result":{"type":"expired"}}"#,
            "not json",
            #"{"custom_id":"not-a-uuid","result":{"type":"expired"}}"#,
        ]
        let outcomes = DiabeticBackfillPlan.outcomes(fromResults: Data(lines.joined(separator: "\n").utf8))
        #expect(outcomes.count == 5)
        #expect(outcomes[ok] == .answer("{}"))
        #expect(outcomes[cut] == .unusable("cut off at max_tokens"))
        #expect(outcomes[busy] == .retry("overloaded_error"))
        #expect(outcomes[invalid] == .unusable("invalid_request_error"))
        #expect(outcomes[expired] == .retry("expired"))
    }

    // MARK: Snapshots and claims

    @Test("An edit while Claude works is noticed; iCloud date rounding is not an edit")
    func snapshotMatching() {
        let id = UUID(), date = Date(timeIntervalSinceReferenceDate: 800_000_000.25)
        let sent = DiabeticBackfillPlan.Snapshot(id: id, version: 3, hash: "abc", lastModified: date)
        #expect(sent.matches(.init(id: id, version: 3, hash: "abc", lastModified: date.addingTimeInterval(0.2))))
        #expect(!sent.matches(.init(id: id, version: 4, hash: "abc", lastModified: date)))
        #expect(!sent.matches(.init(id: id, version: 3, hash: "abd", lastModified: date)))
        #expect(!sent.matches(.init(id: id, version: 3, hash: "abc", lastModified: date.addingTimeInterval(5))))
        #expect(sent.fingerprint == DiabeticBackfillPlan.Snapshot(id: id, version: 3, hash: "abc", lastModified: date).fingerprint)
    }

    @Test("A batch claim is marked, names its batch, and never counts as a current analysis")
    func claim() throws {
        let sections = [IngredientSection(ingredients: [Ingredient(quantity: "1", unit: "cup", name: "rice")])]
        let recipe = RecipeX(title: "Rice", ingredientSectionsData: try JSONEncoder().encode(sections))
        let claim = CachedDiabeticAnalysis.batchClaim(recipeId: recipe.safeID, batchID: "msgbatch_01")
        #expect(claim.isBatchClaim)
        #expect(claim.claimBatchID == "msgbatch_01")
        #expect(claim.analysisData.isEmpty)
        #expect(claim.isIngredientsOutdated(recipe: recipe))
        let real = CachedDiabeticAnalysis(recipeId: recipe.safeID, analysisData: Data("{}".utf8),
                                          recipeVersion: recipe.currentVersion,
                                          ingredientsHash: recipe.ingredientsHash ?? "",
                                          recipeLastModified: recipe.modificationDate)
        #expect(!real.isBatchClaim)
        #expect(real.claimBatchID == nil)
    }
}
