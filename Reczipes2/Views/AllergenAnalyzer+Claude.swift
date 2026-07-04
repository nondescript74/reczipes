//
//  AllergenAnalyzer+Claude.swift
//  Reczipes2
//
//  Extension for Claude API integration
//  Created on 12/17/25.
//

import Foundation

// MARK: - Claude API Response Models

struct ClaudeAllergenAnalysis: Codable {
    let detectedAllergens: [ClaudeDetectedAllergen]
    let falsePositivesAvoided: [FalsePositiveInfo]?  // New: documents what wasn't flagged
    let overallSafetyScore: Double  // 0-10 scale
    let recommendation: RecommendationType
    let notes: String?
    let fodmapAnalysis: ClaudeFODMAPAnalysisData?  // Optional FODMAP data
    
    enum RecommendationType: String, Codable {
        case safe
        case caution
        case avoid
    }
}

struct FalsePositiveInfo: Codable {
    let ingredient: String
    let whyNotAnAllergen: String
}

struct ClaudeFODMAPAnalysisData: Codable {
    let overallLevel: String  // "low", "moderate", "high"
    let categoryBreakdown: [String: FODMAPCategoryData]
    let detectedFODMAPs: [ClaudeDetectedFODMAPItem]
    let modificationTips: [String]
    let monashGuidance: String?
}

struct FODMAPCategoryData: Codable {
    let level: String  // "low", "moderate", "high"
    let ingredients: [String]
}

struct ClaudeDetectedFODMAPItem: Codable {
    let ingredient: String
    let categories: [String]  // e.g. ["oligosaccharides", "polyols"]
    let portionMatters: Bool
    let lowFODMAPAlternative: String?
}

struct ClaudeDetectedAllergen: Codable {
    let name: String
    let foundIn: [String]
    let severity: String  // "mild", "moderate", "severe"
    let hidden: Bool  // true if not obvious from ingredient name
    let substitutions: [String]
    let confidenceScore: Double?  // Optional: 0.0-1.0 confidence
    let reasoning: String?  // Optional: explanation of the match
}

// MARK: - Enhanced Analysis Methods

extension AllergenAnalyzer {
    
    /// Analyze a recipe using Claude API for enhanced detection
    /// This method should be called from your ClaudeAPIClient
    func analyzeRecipeWithClaude(
        _ recipe: RecipeX,
        profile: UserAllergenProfile,
        apiKey: String
    ) async throws -> EnhancedAllergenScore {
        
        // 1. Get basic analysis first
        let basicScore = analyzeRecipe(recipe, profile: profile)
        
        // 2. Generate prompt for Claude
        let prompt = generateClaudeAnalysisPrompt(recipe: recipe, profile: profile)
        
        // 3. Call Claude API
        let claudeResponse = try await callClaudeAPI(prompt: prompt, apiKey: apiKey)
        
        // 4. Parse Claude's response
        guard let data = claudeResponse.data(using: .utf8),
              let analysis = try? JSONDecoder().decode(ClaudeAllergenAnalysis.self, from: data) else {
            throw AllergenAnalysisError.invalidResponse
        }
        
        // 5. Combine basic and Claude analysis
        return EnhancedAllergenScore(
            basicScore: basicScore,
            claudeAnalysis: analysis,
            recipe: recipe
        )
    }
    
    /// Call Claude API with the analysis prompt
    internal func callClaudeAPI(prompt: String, apiKey: String) async throws -> String {
        // Note: Integrate with your existing ClaudeAPIClient.swift
        // This is a placeholder showing the structure
        
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let body: [String: Any] = [
            "model": "claude-3-5-sonnet-20241022",
            "max_tokens": 1024,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AllergenAnalysisError.apiError
        }
        
        // Parse Claude's response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let content = json["content"] as? [[String: Any]],
           let text = content.first?["text"] as? String {
            return text
        }
        
        throw AllergenAnalysisError.invalidResponse
    }
    
    /// Extract structured allergen data from Claude's text response
    /// Call this if Claude returns markdown instead of JSON
    func parseClaudeTextResponse(_ text: String) -> ClaudeAllergenAnalysis? {
        // Extract JSON from markdown code blocks if present
        let jsonPattern = #"```json\s*(\{.*?\})\s*```"#
        if let regex = try? NSRegularExpression(pattern: jsonPattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let jsonRange = Range(match.range(at: 1), in: text) {
            let jsonString = String(text[jsonRange])
            if let data = jsonString.data(using: .utf8),
               let analysis = try? JSONDecoder().decode(ClaudeAllergenAnalysis.self, from: data) {
                return analysis
            }
        }
        
        // Try parsing the whole text as JSON
        if let data = text.data(using: .utf8),
           let analysis = try? JSONDecoder().decode(ClaudeAllergenAnalysis.self, from: data) {
            return analysis
        }
        
        return nil
    }
}

// MARK: - Enhanced Score Model

struct EnhancedAllergenScore: Identifiable {
    let id = UUID()
    let basicScore: RecipeAllergenScore
    let claudeAnalysis: ClaudeAllergenAnalysis
    let recipe: RecipeX
    
    /// Combined safety assessment
    var overallSafety: SafetyLevel {
        // Combine local and Claude analysis
        let basicRisk = basicScore.score
        let claudeRisk = claudeAnalysis.overallSafetyScore
        
        // Average the two scores (you can adjust weighting)
        let combinedScore = (basicRisk + claudeRisk) / 2.0
        
        if combinedScore == 0 { return .safe }
        if combinedScore < 5 { return .lowRisk }
        if combinedScore < 10 { return .mediumRisk }
        return .highRisk
    }
    
    /// Hidden allergens detected only by Claude
    var hiddenAllergens: [ClaudeDetectedAllergen] {
        claudeAnalysis.detectedAllergens.filter { $0.hidden }
    }
    
    /// All allergens (basic + Claude)
    var allDetectedAllergens: [String] {
        var allergens = Set<String>()
        
        // From basic analysis
        basicScore.detectedAllergens.forEach { detected in
            allergens.insert(detected.sensitivity.name)
        }
        
        // From Claude
        claudeAnalysis.detectedAllergens.forEach { detected in
            allergens.insert(detected.name)
        }
        
        return Array(allergens).sorted()
    }
    
    /// Suggested substitutions from Claude
    var substitutions: [String: [String]] {
        var subs: [String: [String]] = [:]
        for allergen in claudeAnalysis.detectedAllergens {
            if !allergen.substitutions.isEmpty {
                subs[allergen.name] = allergen.substitutions
            }
        }
        return subs
    }
    
    enum SafetyLevel {
        case safe
        case lowRisk
        case mediumRisk
        case highRisk
        
        var color: String {
            switch self {
            case .safe: return "green"
            case .lowRisk: return "yellow"
            case .mediumRisk: return "orange"
            case .highRisk: return "red"
            }
        }
        
        var label: String {
            switch self {
            case .safe: return "Safe"
            case .lowRisk: return "Low Risk"
            case .mediumRisk: return "Medium Risk"
            case .highRisk: return "High Risk"
            }
        }
    }
}

// MARK: - Errors

enum AllergenAnalysisError: LocalizedError {
    case invalidResponse
    case apiError
    case networkError
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Could not parse allergen analysis response"
        case .apiError:
            return "API request failed"
        case .networkError:
            return "Network connection error"
        case .decodingError:
            return "Failed to decode response data"
        }
    }
}

// MARK: - Enhanced UI View (Example)

#if canImport(SwiftUI)
import SwiftUI

struct EnhancedAllergenDetailView: View {
    let score: EnhancedAllergenScore
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // Overall assessment
                Section("Overall Safety") {
                    HStack {
                        Circle()
                            .fill(colorForSafety(score.overallSafety))
                            .frame(width: 12, height: 12)
                        Text(score.overallSafety.label)
                            .font(.headline)
                    }
                    
                    Text(score.claudeAnalysis.notes ?? "No additional notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // Basic detection results
                Section("Detected by Keyword Matching") {
                    if score.basicScore.detectedAllergens.isEmpty {
                        Text("No allergens detected by keyword matching")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(score.basicScore.detectedAllergens) { detected in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(detected.sensitivity.name)
                                    .font(.headline)
                                Text("Found in: \(detected.matchedIngredients.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // Hidden allergens (Claude only)
                if !score.hiddenAllergens.isEmpty {
                    Section("Hidden Allergens (AI-Detected)") {
                        ForEach(score.hiddenAllergens, id: \.name) { allergen in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(allergen.name)
                                        .font(.headline)
                                    Spacer()
                                    Text("Hidden")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.orange.opacity(0.2))
                                        .foregroundStyle(Color.appWarning)
                                        .clipShape(Capsule())
                                }
                                
                                Text("Found in: \(allergen.foundIn.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                if !allergen.substitutions.isEmpty {
                                    Text("Substitutions: \(allergen.substitutions.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(Color.appInfo)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                // Substitution suggestions
                if !score.substitutions.isEmpty {
                    Section("Suggested Substitutions") {
                        ForEach(Array(score.substitutions.keys.sorted()), id: \.self) { allergen in
                            if let subs = score.substitutions[allergen] {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Instead of \(allergen):")
                                        .font(.headline)
                                    ForEach(subs, id: \.self) { sub in
                                        HStack {
                                            Image(systemName: "arrow.right")
                                                .font(.caption)
                                                .foregroundStyle(Color.appSuccess)
                                            Text(sub)
                                                .font(.subheadline)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Recommendation
                Section("Recommendation") {
                    Text(recommendationText)
                        .font(.body)
                }
            }
            .navigationTitle("Enhanced Analysis")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func colorForSafety(_ level: EnhancedAllergenScore.SafetyLevel) -> Color {
        switch level.color {
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
    
    private var recommendationText: String {
        switch score.claudeAnalysis.recommendation {
        case .safe:
            return "This recipe appears safe for your dietary needs. Always verify ingredient labels."
        case .caution:
            return "This recipe contains some concerning ingredients. Consider the suggested substitutions or consult with a healthcare professional."
        case .avoid:
            return "This recipe is not recommended for your dietary profile. Please find an alternative recipe."
        }
    }
}
#endif

