//
//  ClaudeServiceIssue.swift
//  Reczipes2
//
//  A failed call to Claude, in words a cook can act on, with the one action that fixes it.
//  Every string is localizable (String Catalog: Localizable.xcstrings). Raw status codes
//  never reach the screen; they stay in the log.
//

import SwiftUI

nonisolated enum ClaudeServiceIssue: Error, Equatable, Identifiable {
    case keyMissing
    case keyRejected
    case accessDenied
    case outOfCredit
    case rateLimited
    case busy
    case modelUnavailable
    case tooLong
    case timedOut
    case offline
    case unexpected

    var id: Self { self }

    /// What the button under the message does.
    enum Fix: Equatable {
        case openClaudeKey
        case openBilling
        case tryAgain
    }

    static let billingURL = URL(string: "https://console.anthropic.com/settings/billing")!

    /// Maps an Anthropic API status code (and its error body, when there is one).
    static func from(statusCode: Int, body: String? = nil) -> ClaudeServiceIssue {
        let text = (body ?? "").lowercased()
        switch statusCode {
        case 401: return .keyRejected
        case 403: return .accessDenied
        case 402: return .outOfCredit
        case 400 where text.contains("credit balance"): return .outOfCredit
        case 404: return .modelUnavailable
        case 408: return .timedOut
        case 429: return .rateLimited
        case 500...599: return .busy   // includes 529 overloaded
        default: return .unexpected
        }
    }

    /// Recognises the errors the Claude callers throw today; nil for anything else.
    init?(_ error: Error) {
        if let issue = error as? ClaudeServiceIssue { self = issue; return }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: self = .timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                self = .offline
            default: return nil
            }
            return
        }
        if let api = error as? ClaudeAPIError {
            switch api {
            case .apiError(let code, let message): self = .from(statusCode: code, body: message)
            case .timeout: self = .timedOut
            case .networkError(let underlying):
                guard let issue = ClaudeServiceIssue(underlying) else { return nil }
                self = issue
            default: return nil
            }
            return
        }
        return nil
    }

    var title: String {
        switch self {
        case .keyMissing:       String(localized: "Claude isn't set up yet", bundle: .appLanguage, comment: "Error title: no Claude API key saved")
        case .keyRejected:      String(localized: "Your Claude key was refused", bundle: .appLanguage, comment: "Error title: Anthropic rejected the API key (HTTP 401)")
        case .accessDenied:     String(localized: "This key can't use Claude", bundle: .appLanguage, comment: "Error title: API key lacks permission (HTTP 403)")
        case .outOfCredit:      String(localized: "Your Claude account is out of credit", bundle: .appLanguage, comment: "Error title: no API credit left")
        case .rateLimited:      String(localized: "Claude needs a short break", bundle: .appLanguage, comment: "Error title: too many requests (HTTP 429)")
        case .busy:             String(localized: "Claude is busy right now", bundle: .appLanguage, comment: "Error title: Anthropic overloaded or server error")
        case .modelUnavailable: String(localized: "This Claude model isn't available", bundle: .appLanguage, comment: "Error title: model not found (HTTP 404)")
        case .tooLong:          String(localized: "The answer was too long to finish", bundle: .appLanguage, comment: "Error title: Claude's reply was cut off")
        case .timedOut:         String(localized: "Claude took too long to answer", bundle: .appLanguage, comment: "Error title: request timed out")
        case .offline:          String(localized: "You're offline", bundle: .appLanguage, comment: "Error title: no internet connection")
        case .unexpected:       String(localized: "Something went wrong with Claude", bundle: .appLanguage, comment: "Error title: unrecognised Claude failure")
        }
    }

    var message: String {
        switch self {
        case .keyMissing:
            String(localized: "Add your Claude API key once and this will work everywhere in the app.", bundle: .appLanguage, comment: "Error message: no Claude key")
        case .keyRejected:
            String(localized: "The key saved in Reczipes is no longer accepted. It may have been removed or replaced. Paste a current key from your Anthropic account.", bundle: .appLanguage, comment: "Error message: key refused")
        case .accessDenied:
            String(localized: "Your Anthropic account doesn't allow this key to do that. Check the key's workspace in your Anthropic account, or paste a different key.", bundle: .appLanguage, comment: "Error message: key lacks permission")
        case .outOfCredit:
            String(localized: "Add credit to your Anthropic account, then try again.", bundle: .appLanguage, comment: "Error message: out of credit")
        case .rateLimited:
            String(localized: "Too many requests in a short time. Wait a minute and try again.", bundle: .appLanguage, comment: "Error message: rate limited")
        case .busy:
            String(localized: "Anthropic's service is overloaded or having trouble. Your recipe is fine. Try again in a few minutes.", bundle: .appLanguage, comment: "Error message: service busy")
        case .modelUnavailable:
            String(localized: "Reczipes asked for a Claude model your account can't use. Updating the app should fix this.", bundle: .appLanguage, comment: "Error message: model not found")
        case .tooLong:
            String(localized: "Claude's reply was cut off before it finished. Trying again usually works.", bundle: .appLanguage, comment: "Error message: reply truncated")
        case .timedOut:
            String(localized: "No answer arrived in time. Check your connection and try again.", bundle: .appLanguage, comment: "Error message: timed out")
        case .offline:
            String(localized: "Connect to the internet and try again.", bundle: .appLanguage, comment: "Error message: offline")
        case .unexpected:
            String(localized: "Try again. If it keeps happening, the Diagnostic Log in Settings has the details.", bundle: .appLanguage, comment: "Error message: unknown failure")
        }
    }

    var fix: Fix {
        switch self {
        case .keyMissing, .keyRejected, .accessDenied: .openClaudeKey
        case .outOfCredit: .openBilling
        default: .tryAgain
        }
    }

    var fixLabel: String {
        switch fix {
        case .openClaudeKey: String(localized: "Enter Claude Key", bundle: .appLanguage, comment: "Button: opens the Claude API key screen")
        case .openBilling:   String(localized: "Open Anthropic Billing", bundle: .appLanguage, comment: "Button: opens the Anthropic billing page")
        case .tryAgain:      String(localized: "Try Again", bundle: .appLanguage, comment: "Button: retries the failed request")
        }
    }
}

extension ClaudeServiceIssue: LocalizedError {
    var errorDescription: String? { title }
    var failureReason: String? { message }
}

// MARK: - Alert with the fix one tap away

private struct ClaudeIssueAlert: ViewModifier {
    @Binding var issue: ClaudeServiceIssue?
    /// Runs the failed action again: after "Try Again", or once a key has been saved.
    let retry: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var keyIssue: ClaudeServiceIssue?
    @State private var keyBefore: String?
    @State private var showKeyManager = false

    func body(content: Content) -> some View {
        content
            .alert(issue?.title ?? "", isPresented: Binding(
                get: { issue != nil },
                set: { if !$0 { issue = nil } }
            ), presenting: issue) { current in
                Button(current.fixLabel) {
                    switch current.fix {
                    case .openClaudeKey:
                        keyIssue = current
                        keyBefore = APIKeyHelper.getAPIKey()
                        showKeyManager = true
                    case .openBilling:
                        openURL(ClaudeServiceIssue.billingURL)
                    case .tryAgain:
                        retry()
                    }
                }
                Button(String(localized: "Not Now", bundle: .appLanguage, comment: "Button: dismisses an error"), role: .cancel) { }
            } message: { current in
                Text(current.message)
            }
            .platformFullScreenCover(isPresented: $showKeyManager, onDismiss: {
                // The action was waiting on the key: run it as soon as a new one is saved
                // (closing the screen without changing the key does not retry).
                let keyNow = APIKeyHelper.getAPIKey()
                if keyIssue != nil, APIKeyHelper.isConfigured, keyNow != keyBefore { retry() }
                keyIssue = nil
                keyBefore = nil
            }) {
                APIKeyManagerView(reason: keyIssue?.title)
            }
    }
}

extension View {
    /// Shows a Claude failure in plain words with the button that fixes it.
    func claudeIssueAlert(_ issue: Binding<ClaudeServiceIssue?>, retry: @escaping () -> Void) -> some View {
        modifier(ClaudeIssueAlert(issue: issue, retry: retry))
    }
}
