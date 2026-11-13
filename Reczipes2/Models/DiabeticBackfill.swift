//
//  DiabeticBackfill.swift
//  Reczipes2
//
//  Lane 37 — operator ruling 2026-11-13: every recipe gets its Diabetic-Friendly Analysis
//  without anyone opening it, so the web shows it for all of them. An automatic pass on the
//  same model as the recipe page (Opus 5.5); the analysis's sources are labelled unverified.
//
//  Runs after each publish pass, like RecipeLocalizer, and never blocks it:
//  1. A batch this device sent earlier is collected once Claude has finished it: each answer
//     is read exactly as a tap on "Analyze" reads it and cached against the ingredients it was
//     asked about.
//  2. A recipe whose cached analysis is current but missing from its public copy is published
//     again (no Claude call).
//  3. Every other public recipe with ingredients and no analysis goes to Claude in ONE Message
//     Batch — half the price of single requests; most batches finish within the hour.
//
//  Nothing is paid for twice. Skipped: a recipe whose public copy has an analysis; whose cached
//  one still matches its ingredients; that is in a batch on any device (a claim row in the
//  iCloud-synced cache, see CachedDiabeticAnalysis.isBatchClaim); or that Claude could not
//  answer usably, until its ingredients change. Runs only on a device with Diabetic-Friendly
//  Analysis turned on and a Claude key: turning that setting off stops it.
//

import Foundation
import SwiftData
import CloudKit

// MARK: - Plan (pure: what to send, what came back, what each recipe needs)

enum DiabeticBackfillPlan {
    /// Same model and limit as the recipe page (DiabeticAnalysisService.callClaudeAPI).
    static let model = "claude-opus-5-5"
    static let maxTokens = 32_000
    /// Recipes per batch; the rest go in the next one.
    static let maxPerBatch = 250
    /// A claim older than this is a batch that never came back (batches end within 24 h).
    static let claimLifetime: TimeInterval = 26 * 60 * 60

    /// The recipe as it was sent to Claude.
    struct Snapshot: Codable, Equatable, Sendable {
        let id: UUID
        let version: Int
        let hash: String
        let lastModified: Date

        var fingerprint: String { "\(version)|\(hash)|\(Int(lastModified.timeIntervalSinceReferenceDate))" }

        /// Same ingredients (version and hash), same edit (to the second: iCloud can round dates).
        func matches(_ other: Snapshot) -> Bool {
            id == other.id && version == other.version && hash == other.hash
                && abs(lastModified.timeIntervalSince(other.lastModified)) < 1
        }
    }

    enum Need: Equatable {
        case nothing
        case publish      // a current analysis is cached but not on the public copy
        case analyze
    }

    static func need(hasIngredients: Bool, hasStoredDate: Bool, publicHasAnalysis: Bool,
                     cachedIsCurrent: Bool, cachedIsPublishable: Bool,
                     claimed: Bool, unusableForTheseIngredients: Bool) -> Need {
        if publicHasAnalysis { return .nothing }
        if cachedIsCurrent { return cachedIsPublishable ? .publish : .nothing }
        // Without a stored date a recipe's modification date is "now", so no analysis of it
        // could ever count as current: it would be paid for on every pass.
        if !hasIngredients || !hasStoredDate || claimed || unusableForTheseIngredients { return .nothing }
        return .analyze
    }

    /// POST /v1/messages/batches body: one request per recipe, custom_id = recipe id.
    static func requestBody(_ prompts: [(id: UUID, prompt: String)]) throws -> Data {
        let requests: [[String: Any]] = prompts.map { item in
            [
                "custom_id": item.id.uuidString,   // 36 chars of [A-F0-9-]: within ^[a-zA-Z0-9_-]{1,64}$
                "params": [
                    "model": model,
                    "max_tokens": maxTokens,
                    "messages": [["role": "user", "content": item.prompt]],
                ] as [String: Any],
            ]
        }
        return try JSONSerialization.data(withJSONObject: ["requests": requests])
    }

    enum Outcome: Equatable {
        case answer(String)      // Claude's text, to parse as the recipe page does
        case unusable(String)    // answered, but not usably: not asked again until the recipe changes
        case retry(String)       // not answered (error, canceled, expired): asked again next pass
    }

    /// The batch's results file (JSONL, one line per request, any order) by recipe id.
    static func outcomes(fromResults jsonl: Data) -> [UUID: Outcome] {
        struct Line: Decodable {
            struct Result: Decodable {
                struct Message: Decodable {
                    struct Block: Decodable { let type: String; let text: String? }
                    let content: [Block]
                    let stop_reason: String?
                }
                struct Failure: Decodable {
                    struct Detail: Decodable { let type: String? }
                    let error: Detail?
                }
                let type: String
                let message: Message?
                let error: Failure?
            }
            let custom_id: String
            let result: Result
        }
        var out: [UUID: Outcome] = [:]
        for raw in String(decoding: jsonl, as: UTF8.self).split(whereSeparator: \.isNewline) {
            guard let line = try? JSONDecoder().decode(Line.self, from: Data(raw.utf8)),
                  let id = UUID(uuidString: line.custom_id) else { continue }
            switch line.result.type {
            case "succeeded":
                if line.result.message?.stop_reason == "max_tokens" {
                    out[id] = .unusable("cut off at max_tokens")
                } else if let text = line.result.message?.content.first(where: { $0.type == "text" })?.text {
                    out[id] = .answer(text)
                } else {
                    out[id] = .unusable("no text in the reply")
                }
            case "errored":
                let kind = line.result.error?.error?.type ?? "error"
                // A request Claude rejects as invalid will be rejected again; anything else may pass.
                out[id] = kind == "invalid_request_error" ? .unusable(kind) : .retry(kind)
            default:   // canceled, expired
                out[id] = .retry(line.result.type)
            }
        }
        return out
    }
}

extension DiabeticBackfillPlan.Snapshot {
    init(recipe: RecipeX) {
        self.init(id: recipe.safeID, version: recipe.currentVersion,
                  hash: recipe.ingredientsHash ?? "", lastModified: recipe.modificationDate)
    }
}

// MARK: - Batch client and this device's state

enum DiabeticBackfillError: Error {
    case unreadableReply
}

final class DiabeticBackfill {
    static let shared = DiabeticBackfill()
    private init() {}

    /// Application Support/DiabeticBackfill/state.json — this device only.
    struct State: Codable {
        var batchID: String?
        var submittedAt: Date?
        var snapshots: [DiabeticBackfillPlan.Snapshot] = []
        /// Recipe id → fingerprint of the ingredients Claude could not answer usably for.
        var unusable: [String: String] = [:]
    }

    private lazy var stateURL: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("DiabeticBackfill", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("state.json")
    }()

    func loadState() -> State {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return state
    }

    func saveState(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    enum BatchStatus: Equatable {
        case running
        case ended(URL)
        case gone          // unknown to Anthropic (deleted, or another workspace's key)
    }

    private static let batchesURL = URL(string: "https://api.anthropic.com/v1/messages/batches")!

    /// Sends the batch; its id.
    func submit(_ prompts: [(id: UUID, prompt: String)]) async throws -> String {
        let body = try DiabeticBackfillPlan.requestBody(prompts)
        let (data, _) = try await send(try request(Self.batchesURL, method: "POST", body: body))
        struct Created: Decodable { let id: String }
        guard let created = try? JSONDecoder().decode(Created.self, from: data) else { throw DiabeticBackfillError.unreadableReply }
        return created.id
    }

    func status(_ batchID: String) async throws -> BatchStatus {
        let url = Self.batchesURL.appendingPathComponent(batchID)
        let (data, code) = try await send(try request(url, method: "GET"), allowNotFound: true)
        if code == 404 { return .gone }
        struct Batch: Decodable { let processing_status: String; let results_url: String? }
        guard let batch = try? JSONDecoder().decode(Batch.self, from: data) else { throw DiabeticBackfillError.unreadableReply }
        guard batch.processing_status == "ended" else { return .running }
        guard let text = batch.results_url, let url = URL(string: text) else { return .gone }
        return .ended(url)
    }

    func results(_ url: URL) async throws -> Data {
        try await send(try request(url, method: "GET")).0
    }

    private func request(_ url: URL, method: String, body: Data? = nil) throws -> URLRequest {
        let apiKey = APIKeyHelper.getAPIKey() ?? ""
        guard !apiKey.isEmpty else { throw ClaudeServiceIssue.keyMissing }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = body
        }
        request.timeoutInterval = 300
        return request
    }

    private func send(_ request: URLRequest, allowNotFound: Bool = false) async throws -> (Data, Int) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw error.code == .timedOut ? ClaudeServiceIssue.timedOut : ClaudeServiceIssue.offline
        }
        guard let http = response as? HTTPURLResponse else { throw ClaudeServiceIssue.unexpected }
        if http.statusCode == 404, allowNotFound { return (data, 404) }
        guard http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8)
            AppLog.warning("🩺 Diabetic batch: Claude returned HTTP \(http.statusCode): \(text?.prefix(300) ?? "")", category: .sharing)
            throw ClaudeServiceIssue.from(statusCode: http.statusCode, body: text)
        }
        return (data, 200)
    }
}

// MARK: - The pass

extension CloudKitSharingService {

    private static var diabeticBackfillTask: Task<Void, Never>?

    /// Starts the diabetic pass unless one is running. Called at the end of every publish
    /// pass; does not wait for it.
    func startDiabeticBackfillPass(modelContext: ModelContext) {
        guard Self.diabeticBackfillTask == nil else { return }
        guard UserDiabeticSettings.shared.isDiabeticEnabled else { return }
        guard !(APIKeyHelper.getAPIKey() ?? "").isEmpty else {
            AppLog.info("🩺 Diabetic analysis: no Claude key, nothing analyzed", category: .sharing)
            return
        }
        Self.diabeticBackfillTask = Task { @MainActor in
            await self.performDiabeticBackfillPass(modelContext: modelContext)
            Self.diabeticBackfillTask = nil
        }
    }

    /// The analysis a public recipe record carries, if any.
    static func publishedDiabeticInfoJSON(in record: CKRecord) -> String? {
        guard let text = record["recipeData"] as? String, let data = text.data(using: .utf8),
              let recipe = try? JSONDecoder().decode(CloudKitRecipe.self, from: data) else { return nil }
        return recipe.diabeticInfoJSON
    }

    private func performDiabeticBackfillPass(modelContext: ModelContext) async {
        guard isCloudKitAvailable, currentUserID != nil else { return }
        let backfill = DiabeticBackfill.shared
        var state = backfill.loadState()

        // 1. Collect the batch this device sent, if Claude has finished it.
        var batchRunning = false
        if let batchID = state.batchID {
            do {
                switch try await backfill.status(batchID) {
                case .running:
                    batchRunning = true
                    AppLog.info("🩺 Diabetic batch \(batchID): Claude is still working on \(state.snapshots.count) recipe(s)", category: .sharing)
                case .ended(let url):
                    let outcomes = DiabeticBackfillPlan.outcomes(fromResults: try await backfill.results(url))
                    collectDiabeticBatch(outcomes, state: &state, modelContext: modelContext)
                    endDiabeticBatch(batchID, state: &state, modelContext: modelContext)
                case .gone:
                    AppLog.warning("🩺 Diabetic batch \(batchID) is no longer known to Claude; its recipes will be asked again", category: .sharing)
                    endDiabeticBatch(batchID, state: &state, modelContext: modelContext)
                }
            } catch {
                AppLog.warning("🩺 Diabetic batch \(batchID): could not check it (\(error.localizedDescription)); trying next pass", category: .sharing)
                return
            }
            backfill.saveState(state)
        }

        // 2. What each live public recipe needs.
        guard let index = await readOwnPublicIndex(.recipe) else { return }
        let deleted = index.deleted
        let now = Date()
        var claimed = Set<UUID>()
        for row in (try? modelContext.fetch(FetchDescriptor<CachedDiabeticAnalysis>())) ?? [] where row.isBatchClaim {
            if now.timeIntervalSince(row.cachedAt) > DiabeticBackfillPlan.claimLifetime {
                modelContext.delete(row)      // a batch that never came back
            } else {
                claimed.insert(row.recipeId)
            }
        }
        var toPublish: [(recipe: RecipeX, recordName: String)] = []
        var toAnalyze: [RecipeX] = []
        var undated = 0
        for recipe in (try? modelContext.fetch(FetchDescriptor<RecipeX>())) ?? [] {
            guard let id = recipe.id, !recipe.isDeleted, deleted[id] == nil, let live = index.live[id],
                  !OwnerDeletedStore.shared.isPendingTombstone(.recipe, id) else { continue }
            let record = index.liveRecords[id]?.first { $0.recordID.recordName == live.recordName }
            let current = currentDiabeticAnalysis(for: recipe, modelContext: modelContext)
            let hasStoredDate = recipe.lastModified != nil || recipe.dateAdded != nil
            let hasIngredients = recipe.ingredientSections.contains { !$0.ingredients.isEmpty }
            let need = DiabeticBackfillPlan.need(
                hasIngredients: hasIngredients,
                hasStoredDate: hasStoredDate,
                publicHasAnalysis: record.flatMap(Self.publishedDiabeticInfoJSON(in:)) != nil,
                cachedIsCurrent: current != nil,
                cachedIsPublishable: (current?.analysisData.count ?? .max) <= Self.diabeticInfoByteBudget,
                claimed: claimed.contains(id),
                unusableForTheseIngredients: state.unusable[id.uuidString] == DiabeticBackfillPlan.Snapshot(recipe: recipe).fingerprint)
            switch need {
            case .nothing:
                if !hasStoredDate && hasIngredients && current == nil { undated += 1 }
            case .publish: toPublish.append((recipe, live.recordName))
            case .analyze: toAnalyze.append(recipe)
            }
        }
        try? modelContext.save()
        if undated > 0 {
            AppLog.warning("🩺 Diabetic analysis: \(undated) recipe(s) have no stored date and are not analyzed automatically", category: .sharing)
        }

        // 3. Publish what is cached but not public yet.
        if !toPublish.isEmpty {
            let (ok, bad) = await republishForDiabetic(toPublish, modelContext: modelContext)
            AppLog.info("🩺 Diabetic analysis published with \(ok) recipe(s)\(bad > 0 ? ", \(bad) to retry" : "")", category: .sharing)
        }

        // 4. Send the rest to Claude, one batch at a time.
        guard !batchRunning else { return }
        guard !toAnalyze.isEmpty else {
            AppLog.info("🩺 Diabetic analysis: every public recipe that can have one has one", category: .sharing)
            return
        }
        let chosen = Array(toAnalyze.shuffled().prefix(DiabeticBackfillPlan.maxPerBatch))
        let prompts = chosen.map { (id: $0.safeID, prompt: DiabeticAnalysisService.shared.buildAnalysisPrompt($0)) }
        do {
            let batchID = try await backfill.submit(prompts)
            state.batchID = batchID
            state.submittedAt = Date()
            state.snapshots = chosen.map(DiabeticBackfillPlan.Snapshot.init(recipe:))
            backfill.saveState(state)
            for recipe in chosen {
                modelContext.insert(CachedDiabeticAnalysis.batchClaim(recipeId: recipe.safeID, batchID: batchID))
            }
            try? modelContext.save()
            AppLog.info("🩺 Diabetic batch \(batchID) sent: \(chosen.count) recipe(s)\(toAnalyze.count > chosen.count ? ", \(toAnalyze.count - chosen.count) in a later batch" : "")", category: .sharing)
        } catch {
            AppLog.warning("🩺 Diabetic batch not sent: \(error.localizedDescription)", category: .sharing)
        }
    }

    /// The newest real cached analysis that still matches the recipe's ingredients — the one
    /// publishableDiabeticInfoJSON would publish (before its size check).
    private func currentDiabeticAnalysis(for recipe: RecipeX, modelContext: ModelContext) -> CachedDiabeticAnalysis? {
        let recipeID = recipe.safeID
        let descriptor = FetchDescriptor<CachedDiabeticAnalysis>(
            predicate: #Predicate<CachedDiabeticAnalysis> { $0.recipeId == recipeID },
            sortBy: [SortDescriptor(\.cachedAt, order: .reverse)]
        )
        guard let newest = try? modelContext.fetch(descriptor).first(where: { !$0.isBatchClaim }),
              !newest.isIngredientsOutdated(recipe: recipe) else { return nil }
        return newest
    }

    /// Caches each usable answer against the ingredients it was asked about.
    private func collectDiabeticBatch(_ outcomes: [UUID: DiabeticBackfillPlan.Outcome],
                                      state: inout DiabeticBackfill.State, modelContext: ModelContext) {
        var recipes: [UUID: RecipeX] = [:]
        for recipe in (try? modelContext.fetch(FetchDescriptor<RecipeX>())) ?? [] {
            if let id = recipe.id { recipes[id] = recipe }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var cached = 0, unusable = 0, again = 0
        for sent in state.snapshots {
            guard let recipe = recipes[sent.id], !recipe.isDeleted else { continue }
            let now = DiabeticBackfillPlan.Snapshot(recipe: recipe)
            // Edited while Claude worked: the answer is about other ingredients. Ask again.
            guard now.matches(sent) else { again += 1; continue }
            switch outcomes[sent.id] {
            case .answer(let text)?:
                do {
                    let info = try DiabeticAnalysisService.shared.parseAndValidate(text, recipeId: sent.id)
                    let data = try encoder.encode(info)
                    guard data.count <= Self.diabeticInfoByteBudget else {
                        state.unusable[sent.id.uuidString] = now.fingerprint
                        unusable += 1
                        continue
                    }
                    modelContext.insert(CachedDiabeticAnalysis(
                        recipeId: sent.id, analysisData: data, cachedAt: Date(),
                        recipeVersion: now.version, ingredientsHash: now.hash, recipeLastModified: now.lastModified))
                    cached += 1
                } catch {
                    state.unusable[sent.id.uuidString] = now.fingerprint
                    unusable += 1
                    AppLog.warning("🩺 Diabetic analysis for '\(recipe.safeTitle)' could not be read: \(error.localizedDescription)", category: .sharing)
                }
            case .unusable(let why)?:
                state.unusable[sent.id.uuidString] = now.fingerprint
                unusable += 1
                AppLog.warning("🩺 Diabetic analysis for '\(recipe.safeTitle)' unusable: \(why)", category: .sharing)
            case .retry?, nil:
                again += 1
            }
        }
        try? modelContext.save()
        AppLog.info("🩺 Diabetic batch collected: \(cached) cached, \(unusable) unusable, \(again) to ask again", category: .sharing)
    }

    /// Forgets the batch and removes its claims (on every device, through iCloud).
    private func endDiabeticBatch(_ batchID: String, state: inout DiabeticBackfill.State, modelContext: ModelContext) {
        for row in (try? modelContext.fetch(FetchDescriptor<CachedDiabeticAnalysis>())) ?? []
        where row.claimBatchID == batchID {
            modelContext.delete(row)
        }
        try? modelContext.save()
        state.batchID = nil
        state.submittedAt = nil
        state.snapshots = []
    }

    /// Refreshes public copies in place (same lock as the publish pass and the translation pass).
    private func republishForDiabetic(_ items: [(recipe: RecipeX, recordName: String)],
                                      modelContext: ModelContext) async -> (Int, Int) {
        while let running = publishTask { await running.value }
        let work = Task { @MainActor () -> (Int, Int) in
            var ok = 0, bad = 0
            for item in items where !item.recipe.isDeleted {
                do {
                    _ = try await self.shareRecipe(item.recipe, modelContext: modelContext, refreshExisting: true,
                                                   knownRecordName: item.recordName, scanForDuplicates: false)
                    ok += 1
                } catch {
                    bad += 1
                    AppLog.warning("🩺 Could not publish the diabetic analysis for '\(item.recipe.safeTitle)': \(error.localizedDescription)", category: .sharing)
                }
            }
            return (ok, bad)
        }
        publishTask = Task { @MainActor in _ = await work.value }
        let result = await work.value
        publishTask = nil
        return result
    }
}
