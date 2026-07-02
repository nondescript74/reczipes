//
//  RecipeAPIClient.swift
//  Reczipes2
//
//  Lightweight client for recipe-api.com endpoints.
//

import Foundation

struct RecipeAPIHealthResponse: Decodable {
    let status: String
    let timestamp: String?
}

struct RecipeAPICategory: Decodable, Hashable {
    let name: String
    let count: Int
}

struct RecipeAPICategoryListResponse: Decodable {
    let data: [RecipeAPICategory]
}

struct RecipeAPIDinnerRecipe: Decodable {
    let id: String
    let name: String
    let description: String?
    let category: String?
    let cuisine: String?
    let difficulty: String?
}

private struct RecipeAPIErrorEnvelope: Decodable {
    let error: RecipeAPIErrorPayload
}

private struct RecipeAPIErrorPayload: Decodable {
    let code: String
    let message: String
}

enum RecipeAPIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(code: Int, message: String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Recipe API key is missing."
        case .invalidResponse:
            return "Invalid response from recipe-api.com."
        case .requestFailed(let code, let message):
            return "Recipe API request failed (\(code)): \(message)"
        case .decodingFailed:
            return "Could not decode recipe-api.com response."
        }
    }
}

class RecipeAPIClient {
    private let apiKey: String?
    private let baseURL = URL(string: "https://recipe-api.com")!

    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    func validateAPIKey() async -> Bool {
        do {
            _ = try await fetchCategories()
            return true
        } catch {
            return false
        }
    }

    func fetchHealth() async throws -> RecipeAPIHealthResponse {
        try await request(path: "/health", requiresKey: false)
    }

    func fetchDinnerRecipe() async throws -> RecipeAPIDinnerRecipe {
        try await request(path: "/api/v1/dinner", requiresKey: false)
    }

    func fetchCategories() async throws -> [RecipeAPICategory] {
        let response: RecipeAPICategoryListResponse = try await request(path: "/api/v1/categories", requiresKey: true)
        return response.data
    }

    private func request<T: Decodable>(path: String, requiresKey: Bool) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw RecipeAPIError.invalidResponse
        }

        if requiresKey, (apiKey?.isEmpty != false) {
            throw RecipeAPIError.missingAPIKey
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if requiresKey, let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecipeAPIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message: String
            if let decoded = try? JSONDecoder().decode(RecipeAPIErrorEnvelope.self, from: data) {
                message = decoded.error.message
            } else {
                message = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            }
            throw RecipeAPIError.requestFailed(code: httpResponse.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RecipeAPIError.decodingFailed
        }
    }
}
