//
//  DiabeticAnalysisService.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/24/25.
//
import SwiftUI
import SwiftData

// MARK: - Model Actor for SwiftData Operations

@ModelActor
actor DiabeticAnalysisModelActor {
    /// Sendable representation of cached data
    struct CachedData: Sendable {
        let analysisData: Data
        let cachedAt: Date
        let recipeVersion: Int
        let ingredientsHash: String
        let recipeLastModified: Date
        
        var isStale: Bool {
            let expirationInterval: TimeInterval = 30 * 24 * 60 * 60 // 30 days
            return Date().timeIntervalSince(cachedAt) > expirationInterval
        }
        
        func isIngredientsOutdated(recipeVersion: Int, recipeHash: String?, recipeModificationDate: Date) -> Bool {
            if recipeVersion != self.recipeVersion {
                return true
            }
            if let hash = recipeHash, hash != self.ingredientsHash {
                return true
            }
            if recipeModificationDate > self.recipeLastModified {
                return true
            }
            return false
        }
        
        func isValid(recipeVersion: Int, recipeHash: String?, recipeModificationDate: Date) -> Bool {
            return !isStale && !isIngredientsOutdated(
                recipeVersion: recipeVersion,
                recipeHash: recipeHash,
                recipeModificationDate: recipeModificationDate
            )
        }
    }
    
    /// Fetch cached analysis from SwiftData and return sendable data
    func fetchCachedAnalysis(recipeId: UUID) throws -> CachedData? {
        let fetchDescriptor = FetchDescriptor<CachedDiabeticAnalysis>(
            predicate: #Predicate { $0.recipeId == recipeId }
        )
        guard let cached = try modelContext.fetch(fetchDescriptor).first else {
            return nil
        }
        
        return CachedData(
            analysisData: cached.analysisData,
            cachedAt: cached.cachedAt,
            recipeVersion: cached.recipeVersion,
            ingredientsHash: cached.ingredientsHash,
            recipeLastModified: cached.recipeLastModified
        )
    }
    
    /// Save new analysis to SwiftData
    func saveCachedAnalysis(
        recipeId: UUID,
        analysisData: Data,
        recipeVersion: Int,
        ingredientsHash: String,
        recipeLastModified: Date
    ) throws {
        let cached = CachedDiabeticAnalysis(
            recipeId: recipeId,
            analysisData: analysisData,
            cachedAt: Date(),
            recipeVersion: recipeVersion,
            ingredientsHash: ingredientsHash,
            recipeLastModified: recipeLastModified
        )
        modelContext.insert(cached)
        try modelContext.save()
    }
    
    /// Delete cached analysis for a specific recipe
    func deleteCachedAnalysis(recipeId: UUID) throws {
        let fetchDescriptor = FetchDescriptor<CachedDiabeticAnalysis>(
            predicate: #Predicate { $0.recipeId == recipeId }
        )
        guard let cached = try modelContext.fetch(fetchDescriptor).first else {
            return
        }
        modelContext.delete(cached)
        try modelContext.save()
    }
    
    /// Clean up expired cache entries
    func cleanupExpiredCache() throws {
        let fetchDescriptor = FetchDescriptor<CachedDiabeticAnalysis>()
        let allCached = try modelContext.fetch(fetchDescriptor)
        
        for cached in allCached where cached.isStale {
            modelContext.delete(cached)
        }
        try modelContext.save()
    }
}

// MARK: - Main Service

actor DiabeticAnalysisService {
    static let shared = DiabeticAnalysisService()
    
    private init() {
    }
    
    /// Get the API key for making requests
    private func getAPIKey() async -> String {
        return await MainActor.run {
            APIKeyHelper.getAPIKey() ?? ""
        }
    }
    
    /// Analyze a recipe for diabetic-friendly information
    /// - Parameters:
    ///   - recipe: The recipe to analyze
    ///   - modelContainer: SwiftData container for cache persistence
    ///   - forceRefresh: Whether to bypass cache and force a fresh analysis
    /// - Returns: Diabetic analysis information
    @MainActor
    func analyzeDiabeticImpact(
        recipe: RecipeX,
        modelContainer: ModelContainer,
        forceRefresh: Bool = false
    ) async throws -> DiabeticInfo {
        guard let recipeId = recipe.id else {
            throw DiabeticAnalysisError.invalidRecipe
        }
        
        // Check SwiftData cache first (with ingredient change detection)
        if !forceRefresh {
            let modelActor = DiabeticAnalysisModelActor(modelContainer: modelContainer)
            if let cachedData = try await modelActor.fetchCachedAnalysis(recipeId: recipeId) {
                // Validate cache against current recipe state
                if cachedData.isValid(
                    recipeVersion: recipe.currentVersion,
                    recipeHash: recipe.ingredientsHash,
                    recipeModificationDate: recipe.modificationDate
                ) {
                    print("✅ Using cached diabetic analysis for recipe: \(String(describing: recipe.title))")
                    print("   Version: \(cachedData.recipeVersion), Hash: \(String(cachedData.ingredientsHash.prefix(8)))...")
                    
                    // Decode the analysis on MainActor
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    return try decoder.decode(DiabeticInfo.self, from: cachedData.analysisData)
                } else {
                    // Cache is invalid - log why
                    if cachedData.isStale {
                        print("⚠️ Cache expired (>30 days) for recipe: \(String(describing: recipe.title))")
                    } else if cachedData.isIngredientsOutdated(
                        recipeVersion: recipe.currentVersion,
                        recipeHash: recipe.ingredientsHash,
                        recipeModificationDate: recipe.modificationDate
                    ) {
                        print("⚠️ Ingredients changed for recipe: \(String(describing: recipe.title))")
                        print("   Cached version: \(cachedData.recipeVersion) vs current: \(recipe.currentVersion)")
                        print("   Cached hash: \(String(cachedData.ingredientsHash.prefix(8)))... vs current: \(String((recipe.ingredientsHash ?? "").prefix(8)))...")
                    }
                }
            }
        } else {
            print("🔄 Force refresh requested for recipe: \(String(describing: recipe.title))")
        }
        
        
        // Build comprehensive prompt following guidelines
        let prompt = buildAnalysisPrompt(recipe)
        
        // Request Claude analysis using existing extractRecipe method pattern
        let response = try await callClaudeAPI(with: prompt)
        
        // Parse and validate response
        let diabeticInfo = try parseAndValidate(response, recipeId: recipeId)
        
        // Cache result in SwiftData with current recipe state
        print("💾 Caching new analysis for recipe: \(String(describing: recipe.title))")
        print("   Version: \(recipe.currentVersion), Hash: \(String((recipe.ingredientsHash ?? "").prefix(8)))...")
        
        // Encode the diabetic info
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let analysisData = try encoder.encode(diabeticInfo)
        
        let modelActor = DiabeticAnalysisModelActor(modelContainer: modelContainer)
        try await modelActor.saveCachedAnalysis(
            recipeId: recipeId,
            analysisData: analysisData,
            recipeVersion: recipe.currentVersion,
            ingredientsHash: recipe.ingredientsHash ?? "",
            recipeLastModified: recipe.modificationDate
        )
        
        // Also store in in-memory cache for quick access
        DiabeticInfoCache.shared.store(diabeticInfo, recipeId: recipeId)
        
        return diabeticInfo
    }
    
    /// Clean up expired cache entries
    /// - Parameter modelContainer: SwiftData container
    func cleanupExpiredCache(modelContainer: ModelContainer) async throws {
        let modelActor = DiabeticAnalysisModelActor(modelContainer: modelContainer)
        try await modelActor.cleanupExpiredCache()
    }
    
    /// Invalidate cache for a specific recipe (useful when ingredients change)
    /// - Parameters:
    ///   - recipeId: The recipe ID to invalidate
    ///   - modelContainer: SwiftData container
    func invalidateCache(for recipeId: UUID, modelContainer: ModelContainer) async throws {
        // Clear persistent cache
        let modelActor = DiabeticAnalysisModelActor(modelContainer: modelContainer)
        try await modelActor.deleteCachedAnalysis(recipeId: recipeId)
        print("🗑️ Deleted persistent diabetic cache for recipe ID: \(recipeId)")
        
        // Clear in-memory cache
        await DiabeticInfoCache.shared.clear(recipeId: recipeId)
        print("🗑️ Deleted in-memory diabetic cache for recipe ID: \(recipeId)")
    }
    
    /// Check if a recipe has valid cached analysis
    /// - Parameters:
    ///   - recipe: The recipe to check
    ///   - modelContainer: SwiftData container
    /// - Returns: True if valid cache exists
    func hasCachedAnalysis(for recipe: RecipeX, modelContainer: ModelContainer) async throws -> Bool {
        guard let recipeId = recipe.id else {
            return false
        }
        let modelActor = DiabeticAnalysisModelActor(modelContainer: modelContainer)
        guard let cachedData = try await modelActor.fetchCachedAnalysis(recipeId: recipeId) else {
            return false
        }
        return cachedData.isValid(
            recipeVersion: recipe.currentVersion,
            recipeHash: recipe.ingredientsHash,
            recipeModificationDate: recipe.modificationDate
        )
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func buildAnalysisPrompt(_ recipe: RecipeX) -> String {
        // Extract all ingredients with details
        let ingredientsList = recipe.ingredientSections
            .flatMap { section -> [String] in
                let sectionTitle = section.title.map { "[\($0)]" } ?? ""
                return section.ingredients.map { ingredient in
                    var parts: [String] = []
                    if let qty = ingredient.quantity { parts.append(qty) }
                    if let unit = ingredient.unit { parts.append(unit) }
                    parts.append(ingredient.name)
                    if let prep = ingredient.preparation { parts.append("(\(prep))") }
                    return sectionTitle.isEmpty ? parts.joined(separator: " ") : "\(sectionTitle) \(parts.joined(separator: " "))"
                }
            }
            .joined(separator: "\n")
        
//        // Extract all instructions
//        let instructionsList = recipe.instructionSections
//            .flatMap { section -> [String] in
//                let sectionTitle = section.title.map { "[\($0)]" } ?? ""
//                return section.steps.map { step in
//                    let prefix = step.stepNumber.map { "\($0). " } ?? "• "
//                    return sectionTitle.isEmpty ? "\(prefix)\(step.text)" : "\(sectionTitle) \(prefix)\(step.text)"
//                }
//            }
//            .joined(separator: "\n")
        
        let systemPrompt = """
        You are a certified diabetes educator and registered dietitian analyzing recipes for diabetic dietary considerations.
        Your analysis must be evidence-based, citing only reputable medical sources.
        
        CRITICAL GUIDELINES (Medical Compliance):
        
        **Source Quality Control:**
        - ONLY cite sources from: ADA (American Diabetes Association), Mayo Clinic, CDC, NIH, peer-reviewed medical journals
        - Sources MUST be published between 2023-2025
        - EXCLUDE: blogs, forums, commercial diet sites, non-medical sources
        - Cite URL for EVERY claim
        - If sources conflict, explicitly note the disagreement with neutral language
        
        **Glycemic Calculations:**
        - Calculate glycemic load using: GL = (GI × net carbs per serving) / 100
        - Flag ingredients with GI > 70 as high-impact
        - Show calculation methodology transparently
        - Note confidence level (high/medium/low) based on data availability
        
        **Consensus Handling:**
        - If 3+ sources agree: "strongConsensus"
        - If 2 sources agree: "moderateConsensus"
        - If 1 source or conflicting: "limitedEvidence"
        - If outdated/no sources: "needsReview"
        - Use neutral phrasing for conflicts: "Some sources suggest... while others recommend..."
        
        **Privacy & Disclaimer:**
        - Never assume user's diabetic status
        - Frame as informational only, not medical advice
        - Encourage consulting healthcare providers
        
        Return ONLY valid JSON with no markdown formatting, no preamble, no explanation.
        """
        
        let userPrompt = """
        Analyze this recipe for diabetic-friendly dietary information:
        
        **Recipe Details:**
        Title: \(String(describing: recipe.title))
        Yield: \(recipe.yield ?? "Not specified")
        Header Notes: \(recipe.headerNotes ?? "None")
        
        **Ingredients:**
        \(ingredientsList)
        
        **Instructions:**
        
        
        **Required Analysis (Return as JSON):**
        
        {
          "estimatedGlycemicLoad": {
            "value": <number: calculated GL per serving>,
            "explanation": "<string: show calculation: 'Estimated using [ingredient] GI of X, net carbs of Y g: GL = (X × Y) / 100 = Z'>"
          },
          "carbCount": {
            "totalCarbs": <number: grams per serving>,
            "netCarbs": <number: total carbs - fiber>,
            "fiber": <number: grams>
          },
          "fiberContent": {
            "total": <number: grams>,
            "soluble": <number or null>,
            "insoluble": <number or null>
          },
          "sugarBreakdown": {
            "total": <number: grams>,
            "added": <number or null>,
            "natural": <number or null>
          },
          "glycemicImpactFactors": [
            {
              "ingredient": "<string: ingredient name>",
              "glycemicIndex": <number: GI value>,
              "impact": "<low|medium|high>",
              "explanation": "<string: why this matters>"
            }
          ],
          "diabeticGuidance": [
            {
              "title": "<string: brief title>",
              "summary": "<string: one-line summary>",
              "detailedExplanation": "<string: full explanation with medical context>",
              "icon": "<string: SF Symbol name like 'heart.fill', 'fork.knife', 'clock', 'leaf'>",
              "practicalTips": ["<string: actionable tip>"]
            }
          ],
          "portionRecommendations": {
            "recommendedServing": "<string: specific portion guidance>",
            "servingSize": "<string: measurement like '1 cup' or '150g'>",
            "explanation": "<string: why this portion size>"
          },
          "substitutionSuggestions": [
            {
              "originalIngredient": "<string>",
              "substitute": "<string>",
              "reason": "<string: why this substitution helps>",
              "nutritionalImprovement": "<string: specific benefits>"
            }
          ],
          "sources": [
            {
              "title": "<string: source title>",
              "organization": "<string: ADA, Mayo Clinic, CDC, NIH, etc.>",
              "url": "<string: full URL>",
              "publishDate": "<string: YYYY-MM-DD format>",
              "credibilityScore": "<high|medium|low>"
            }
          ],
          "consensusLevel": "<strongConsensus|moderateConsensus|limitedEvidence|needsReview>"
        }
        
        **Analysis Requirements:**
        1. Calculate glycemic load using standard formula: GL = (GI × net carbs) / 100
        2. Identify ALL ingredients with significant glycemic impact (GI > 55)
        3. Provide 3-5 guidance items covering: blood sugar impact, timing, portion control, pairing strategies
        4. Suggest 2-4 ingredient substitutions to lower glycemic load
        5. Cite 3-5 authoritative sources (ADA, Mayo Clinic, CDC, NIH, peer-reviewed journals)
        6. Note any conflicting information between sources
        7. Indicate confidence level based on source agreement
        
        **Icon Suggestions:**
        - Blood sugar impact: "waveform.path.ecg"
        - Timing/meal planning: "clock"
        - Portion control: "chart.pie"
        - Food pairing: "fork.knife"
        - Fiber benefits: "leaf"
        - Protein pairing: "fish"
        - Exercise: "figure.walk"
        
        Analyze now and return ONLY the JSON (no markdown, no explanation).
        """
        
        return systemPrompt + "\n\n" + userPrompt
    }
    
    private func callClaudeAPI(with prompt: String) async throws -> String {
        let baseURL = "https://api.anthropic.com/v1/messages"
        let apiKey = await getAPIKey()
        
        guard !apiKey.isEmpty else {
            throw DiabeticAnalysisError.missingAPIKey
        }
        
        guard let url = URL(string: baseURL) else {
            throw DiabeticAnalysisError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 120 // 2 minutes for analysis
        
        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514", // Latest model
            "max_tokens": 8192,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiabeticAnalysisError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw DiabeticAnalysisError.apiError(statusCode: httpResponse.statusCode)
        }
        
        // Parse Claude response (matching ClaudeAPIClient pattern)
        struct ClaudeResponse: Codable {
            struct ContentBlock: Codable {
                let type: String
                let text: String?
            }
            let content: [ContentBlock]
        }
        
        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        
        guard let textContent = claudeResponse.content.first(where: { $0.type == "text" }),
              let text = textContent.text else {
            throw DiabeticAnalysisError.noContentInResponse
        }
        
        return text
    }
    
    @MainActor
    private func parseAndValidate(_ response: String, recipeId: UUID) throws -> DiabeticInfo {
        // Extract JSON from response (Claude might wrap in markdown)
        let jsonString = extractJSON(from: response)
        
        guard let data = jsonString.data(using: .utf8) else {
            throw DiabeticAnalysisError.invalidJSON
        }
        
        // Decode into intermediate structure
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let analysisResponse = try decoder.decode(DiabeticAnalysisResponse.self, from: data)
        
        // Convert to DiabeticInfo with proper IDs
        return analysisResponse.toDiabeticInfo(recipeId: recipeId)
    }
    
    private nonisolated func extractJSON(from text: String) -> String {
        // Remove markdown code blocks if present
        let pattern = "```(?:json)?\\s*([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // If no code blocks, try to find JSON by looking for { }
        if let startIndex = text.firstIndex(of: "{"),
           let endIndex = text.lastIndex(of: "}") {
            return String(text[startIndex...endIndex])
        }
        return text
    }
}
// MARK: - Analysis Response Decoder

private struct DiabeticAnalysisResponse: Codable {
    let estimatedGlycemicLoad: GlycemicLoadResponse?
    let carbCount: CarbInfoResponse
    let fiberContent: FiberInfoResponse
    let sugarBreakdown: SugarBreakdownResponse
    let glycemicImpactFactors: [GlycemicFactorResponse]
    let diabeticGuidance: [GuidanceItemResponse]
    let portionRecommendations: PortionGuidanceResponse?
    let substitutionSuggestions: [IngredientSubstitutionResponse]
    let sources: [VerifiedSourceResponse]
    let consensusLevel: String
    
    @MainActor
    func toDiabeticInfo(recipeId: UUID) -> DiabeticInfo {
        DiabeticInfo(
            id: UUID(),
            recipeId: recipeId,
            lastUpdated: Date(),
            estimatedGlycemicLoad: estimatedGlycemicLoad?.toGlycemicLoad(),
            glycemicImpactFactors: glycemicImpactFactors.map { $0.toGlycemicFactor() },
            carbCount: carbCount.toCarbInfo(),
            fiberContent: fiberContent.toFiberInfo(),
            sugarBreakdown: sugarBreakdown.toSugarBreakdown(),
            diabeticGuidance: diabeticGuidance.map { $0.toGuidanceItem() },
            portionRecommendations: portionRecommendations?.toPortionGuidance(),
            substitutionSuggestions: substitutionSuggestions.map { $0.toIngredientSubstitution() },
            sources: sources.map { $0.toVerifiedSource() },
            consensusLevel: ConsensusLevel(rawValue: consensusLevel) ?? .needsReview
        )
    }
}

private struct GlycemicLoadResponse: Codable {
    let value: Double
    let explanation: String?
    
    func toGlycemicLoad() -> GlycemicLoad {
        GlycemicLoad(value: value, explanation: explanation)
    }
}

private struct CarbInfoResponse: Codable {
    let totalCarbs: Double
    let netCarbs: Double
    let fiber: Double
    
    func toCarbInfo() -> CarbInfo {
        CarbInfo(totalCarbs: totalCarbs, netCarbs: netCarbs, fiber: fiber)
    }
}

private struct FiberInfoResponse: Codable {
    let total: Double
    let soluble: Double?
    let insoluble: Double?
    
    func toFiberInfo() -> FiberInfo {
        FiberInfo(total: total, soluble: soluble, insoluble: insoluble)
    }
}

private struct SugarBreakdownResponse: Codable {
    let total: Double
    let added: Double?
    let natural: Double?
    
    func toSugarBreakdown() -> SugarBreakdown {
        SugarBreakdown(total: total, added: added, natural: natural)
    }
}

private struct GlycemicFactorResponse: Codable {
    let ingredient: String
    let glycemicIndex: Int
    let impact: String
    let explanation: String
    
    func toGlycemicFactor() -> GlycemicFactor {
        let impactLevel: GlycemicFactor.ImpactLevel
        switch impact.lowercased() {
        case "low": impactLevel = .low
        case "medium": impactLevel = .medium
        case "high": impactLevel = .high
        default: impactLevel = .medium
        }
        
        return GlycemicFactor(
            ingredient: ingredient,
            glycemicIndex: glycemicIndex,
            impact: impactLevel,
            explanation: explanation
        )
    }
}

private struct GuidanceItemResponse: Codable {
    let title: String
    let summary: String
    let detailedExplanation: String
    let icon: String
    let practicalTips: [String]?
    
    func toGuidanceItem() -> GuidanceItem {
        GuidanceItem(
            title: title,
            summary: summary,
            detailedExplanation: detailedExplanation,
            icon: icon,
            color: .blue, // Default color, will be properly styled in view
            practicalTips: practicalTips
        )
    }
}

private struct PortionGuidanceResponse: Codable {
    let recommendedServing: String
    let servingSize: String?
    let explanation: String
    
    func toPortionGuidance() -> PortionGuidance {
        PortionGuidance(
            recommendedServing: recommendedServing,
            servingSize: servingSize,
            explanation: explanation
        )
    }
}

private struct IngredientSubstitutionResponse: Codable {
    let originalIngredient: String
    let substitute: String
    let reason: String?
    let nutritionalImprovement: String?
    
    func toIngredientSubstitution() -> IngredientSubstitution {
        IngredientSubstitution(
            originalIngredient: originalIngredient,
            substitute: substitute,
            reason: reason,
            nutritionalImprovement: nutritionalImprovement
        )
    }
}

private struct VerifiedSourceResponse: Codable {
    let title: String
    let organization: String?
    let url: String?
    let publishDate: String?
    let credibilityScore: String?
    
    func toVerifiedSource() -> VerifiedSource {
        let urlObject = url.flatMap { URL(string: $0) }
        
        // Parse date string (YYYY-MM-DD format)
        var dateObject: Date?
        if let dateString = publishDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            dateObject = formatter.date(from: dateString)
        }
        
        let credibility: SourceCredibility?
        if let score = credibilityScore {
            credibility = SourceCredibility(rawValue: score)
        } else {
            credibility = nil
        }
        
        return VerifiedSource(
            title: title,
            organization: organization,
            url: urlObject,
            publishDate: dateObject,
            credibilityScore: credibility
        )
    }
}

// MARK: - Cache Implementation

final class DiabeticInfoCache: Sendable {
    static let shared = DiabeticInfoCache()
    
    private let cache: Cache
    
    private init() {
        self.cache = Cache()
    }
    
    // Thread-safe storage.
    //
    // # Thread Safety (`@unchecked Sendable` justification)
    //
    // `storage` is mutable, so the type cannot synthesize `Sendable`. All access
    // to `storage` is guarded by `lock` (`NSLock`), which provides mutual exclusion
    // across threads. Every public method follows the lock/defer-unlock pattern,
    // so there is no path that reads or writes `storage` without holding `lock`.
    //
    // An `actor` would provide compile-time enforcement but would force callers to
    // `await` every cache hit. Since this cache is read on the hot path during
    // diabetic analysis rendering, the synchronous lock-based API is intentional.
    // If actor migration is desired later, see `SWIFT_6_CONCURRENCY_AUDIT.md`.
    private final class Cache: @unchecked Sendable {
        private var storage: [UUID: CachedInfo] = [:]
        private let lock = NSLock()
        
        func get(_ key: UUID) -> CachedInfo? {
            lock.lock()
            defer { lock.unlock() }
            return storage[key]
        }
        
        func set(_ value: CachedInfo, forKey key: UUID) {
            lock.lock()
            defer { lock.unlock() }
            storage[key] = value
        }
        
        func remove(_ key: UUID) {
            lock.lock()
            defer { lock.unlock() }
            storage.removeValue(forKey: key)
        }
        
        func removeAll() {
            lock.lock()
            defer { lock.unlock() }
            storage.removeAll()
        }
        
        func filterInPlace(_ predicate: (CachedInfo) -> Bool) {
            lock.lock()
            defer { lock.unlock() }
            storage = storage.filter { predicate($0.value) }
        }
    }
    
    struct CachedInfo: Sendable {
        let info: DiabeticInfo
        let cachedAt: Date
        
        var isStillValid: Bool {
            // Cache expires after 30 days per guidelines
            let expirationDate = Calendar.current.date(
                byAdding: .day,
                value: 30,
                to: cachedAt
            ) ?? cachedAt
            return Date() < expirationDate
        }
    }
    
    func get(recipeId: UUID) -> CachedInfo? {
        cache.get(recipeId)
    }
    
    func store(_ info: DiabeticInfo, recipeId: UUID) {
        cache.set(CachedInfo(info: info, cachedAt: Date()), forKey: recipeId)
    }
    
    func clear(recipeId: UUID) {
        cache.remove(recipeId)
    }
    
    func clearAll() {
        cache.removeAll()
    }
    
    /// Remove expired cache entries
    func cleanupExpired() {
        cache.filterInPlace { $0.isStillValid }
    }
}

// MARK: - Errors

enum DiabeticAnalysisError: LocalizedError {
    case invalidRecipe
    case invalidRequest
    case invalidResponse
    case invalidJSON
    case noContentInResponse
    case apiError(statusCode: Int)
    case missingAPIKey
    
    var errorDescription: String? {
        switch self {
        case .invalidRecipe:
            return "Recipe data is invalid or incomplete"
        case .invalidRequest:
            return "Failed to create analysis request"
        case .invalidResponse:
            return "Received invalid response from analysis service"
        case .invalidJSON:
            return "Could not parse analysis results"
        case .noContentInResponse:
            return "No analysis content in response"
        case .apiError(let code):
            return "Analysis service error (code \(code))"
        case .missingAPIKey:
            return "API key not configured"
        }
    }
}

