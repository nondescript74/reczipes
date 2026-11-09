//
//  ClaudeServiceIssueTests.swift
//  Reczipes2Tests
//
//  Claude failures reach the user as plain words with a fix, never as a raw status code.
//

import Testing
import Foundation
@testable import Reczipes2

@Suite("Claude service issues")
@MainActor
struct ClaudeServiceIssueTests {
    @Test("Status codes map to plain-language issues")
    func statusCodes() {
        #expect(ClaudeServiceIssue.from(statusCode: 401) == .keyRejected)
        #expect(ClaudeServiceIssue.from(statusCode: 403) == .accessDenied)
        #expect(ClaudeServiceIssue.from(statusCode: 400, body: #"{"error":{"message":"Your credit balance is too low"}}"#) == .outOfCredit)
        #expect(ClaudeServiceIssue.from(statusCode: 400, body: "bad request") == .unexpected)
        #expect(ClaudeServiceIssue.from(statusCode: 404) == .modelUnavailable)
        #expect(ClaudeServiceIssue.from(statusCode: 429) == .rateLimited)
        #expect(ClaudeServiceIssue.from(statusCode: 529) == .busy)
        #expect(ClaudeServiceIssue.from(statusCode: 500) == .busy)
    }

    @Test("Each issue offers the action that fixes it")
    func fixes() {
        #expect(ClaudeServiceIssue.keyRejected.fix == .openClaudeKey)
        #expect(ClaudeServiceIssue.keyMissing.fix == .openClaudeKey)
        #expect(ClaudeServiceIssue.outOfCredit.fix == .openBilling)
        #expect(ClaudeServiceIssue.busy.fix == .tryAgain)
        #expect(ClaudeServiceIssue.tooLong.fix == .tryAgain)
    }

    @Test("No message shows a raw status code")
    func noRawCodes() {
        let all: [ClaudeServiceIssue] = [.keyMissing, .keyRejected, .accessDenied, .outOfCredit, .rateLimited,
                                         .busy, .modelUnavailable, .tooLong, .timedOut, .offline, .unexpected]
        for issue in all {
            let text = issue.title + " " + issue.message + " " + issue.fixLabel
            #expect(text.range(of: #"\b[1-5]\d\d\b"#, options: .regularExpression) == nil, "\(issue): \(text)")
            #expect(!text.lowercased().contains("code"), "\(issue): \(text)")
        }
    }

    @Test("Errors thrown by the Claude callers are recognised")
    func recognisesCallerErrors() {
        #expect(ClaudeServiceIssue(ClaudeAPIError.apiError(statusCode: 401, message: "invalid x-api-key")) == .keyRejected)
        #expect(ClaudeServiceIssue(ClaudeAPIError.timeout) == .timedOut)
        #expect(ClaudeServiceIssue(URLError(.notConnectedToInternet)) == .offline)
        #expect(ClaudeServiceIssue(URLError(.timedOut)) == .timedOut)
        #expect(ClaudeServiceIssue(ClaudeServiceIssue.keyMissing) == .keyMissing)
        #expect(ClaudeServiceIssue(ClaudeAPIError.noRecipeFound) == nil)
    }
}
