//
//  OwnershipAndErrorMessageTests.swift
//  Reczipes2Tests
//
//  The "Add to Book" menu offers only the user's own books (same rule as Books → Mine),
//  and an Anthropic 401 no longer claims the API key is the only possible cause.
//

import Testing
import Foundation
@testable import Reczipes2

@Suite("Book ownership rule")
struct BookOwnershipTests {

    @Test("No owner recorded counts as mine")
    func noOwner() {
        #expect(Book.isOwnedByCurrentUser(ownerUserID: nil, currentUserID: "_me"))
        #expect(Book.isOwnedByCurrentUser(ownerUserID: nil, currentUserID: nil))
    }

    @Test("My own user ID is mine; someone else's is not")
    func ownerMatch() {
        #expect(Book.isOwnedByCurrentUser(ownerUserID: "_me", currentUserID: "_me"))
        #expect(!Book.isOwnedByCurrentUser(ownerUserID: "_someoneElse", currentUserID: "_me"))
    }

    @Test("Before the iCloud user is known, other people's books are not offered")
    func unknownCurrentUser() {
        #expect(!Book.isOwnedByCurrentUser(ownerUserID: "_someoneElse", currentUserID: nil))
    }
}

@Suite("Extraction error messages")
struct ExtractionErrorMessageTests {

    private let model = "claude-test-model"

    @Test("401 names the usage limit as well as the key, and keeps Anthropic's text")
    func unauthorized() {
        let text = ClaudeAPIError.userMessage(statusCode: 401,
                                              apiMessage: "[authentication_error] invalid x-api-key",
                                              model: model)
        #expect(text.contains("API key"))
        #expect(text.contains("usage or spend limit"))
        #expect(text.contains("invalid x-api-key"))
    }

    @Test("429 talks about limits, not the key")
    func rateLimited() {
        let text = ClaudeAPIError.userMessage(statusCode: 429, apiMessage: "", model: model)
        #expect(text.contains("limit"))
        #expect(!text.contains("API key"))
    }

    @Test("Other statuses pass Anthropic's message through")
    func passThrough() {
        let msg = "[invalid_request_error] Your credit balance is too low"
        #expect(ClaudeAPIError.userMessage(statusCode: 400, apiMessage: msg, model: model) == msg)
        #expect(ClaudeAPIError.userMessage(statusCode: 404, apiMessage: "", model: model).contains(model))
    }
}
