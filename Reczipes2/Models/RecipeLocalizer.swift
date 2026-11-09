//
//  RecipeLocalizer.swift
//  Reczipes2
//
//  Puts every recipe this person publishes into every app language (AppLanguage,
//  English excepted) and publishes the text with the recipe's public copy.
//
//  Runs after each publish pass (launch, auto-sync, an import, an edit), never
//  blocking it. What a public copy already carries is read from the public database,
//  so a recipe translated on the Mac is not paid for again on the iPhone. A language
//  added to AppLanguage is filled in for every recipe on the next launch: nothing
//  else needs changing.
//
//  Never removes or unshares anything; each public copy is refreshed in place.
//  No Claude key → nothing happens. A recipe edited since its translation gets a
//  new one; until then its stale translation is not published (English shows).
//

import Foundation
import SwiftData
import CloudKit

@MainActor
final class RecipeLocalizer {
    static let shared = RecipeLocalizer()

    /// Same model as extraction and the diabetic analysis (ClaudeAPIClient).
    static let model = "claude-opus-5-5"

    /// Every app language except the one recipes are written in.
    static var targetLanguages: [String] {
        AppLanguage.allCases.filter { $0 != .english }.map(\.rawValue)
    }

    /// Translations in flight at once.
    static let maxConcurrent = 4
    /// Recipes translated, then published, per round (a stopped pass loses at most one round's publishing).
    static let roundSize = 12
    /// Largest translationsJSON published with a recipe (a CloudKit record holds ~1 MB of text).
    static let byteBudget = 300_000

    // MARK: Local cache (Application Support/RecipeTranslations/<id>.json)

    /// What this device has translated, per recipe: language → translation; and the
    /// English it could not translate (refused replies), so it is not paid for again
    /// until the recipe changes.
    private struct CacheFile: Codable {
        var translations: [String: RecipeTranslation] = [:]
        var refused: [String: String] = [:]   // language → fingerprint
    }

    private lazy var folder: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("RecipeTranslations", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private func fileURL(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).json") }

    private func load(_ id: UUID) -> CacheFile {
        guard let data = try? Data(contentsOf: fileURL(id)),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data) else { return CacheFile() }
        return file
    }

    private func save(_ file: CacheFile, _ id: UUID) {
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL(id), options: .atomic)
    }

    func cached(_ id: UUID, language: String, fingerprint: String) -> RecipeTranslation? {
        let t = load(id).translations[language]
        return t?.source == fingerprint ? t : nil
    }

    func store(_ translation: RecipeTranslation, id: UUID, language: String) {
        var file = load(id)
        file.translations[language] = translation
        file.refused[language] = nil
        save(file, id)
    }

    func wasRefused(_ id: UUID, language: String, fingerprint: String) -> Bool {
        load(id).refused[language] == fingerprint
    }

    func markRefused(_ id: UUID, language: String, fingerprint: String) {
        var file = load(id)
        file.refused[language] = fingerprint
        save(file, id)
    }

    // MARK: Claude

    func translate(_ source: RecipeTranslationSource, to language: String) async throws -> RecipeTranslation {
        let apiKey = APIKeyHelper.getAPIKey() ?? ""
        guard !apiKey.isEmpty else { throw ClaudeServiceIssue.keyMissing }
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw ClaudeServiceIssue.unexpected }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 300
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "messages": [["role": "user", "content": RecipeTranslations.prompt(for: source, language: language)]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw error.code == .timedOut ? ClaudeServiceIssue.timedOut : ClaudeServiceIssue.offline
        }
        guard let http = response as? HTTPURLResponse else { throw ClaudeServiceIssue.unexpected }
        guard http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8)
            AppLog.warning("🌐 Translation: Claude returned HTTP \(http.statusCode): \(text?.prefix(300) ?? "")", category: .sharing)
            throw ClaudeServiceIssue.from(statusCode: http.statusCode, body: text)
        }

        struct Reply: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
            let stop_reason: String?
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        if reply.stop_reason == "max_tokens" { throw RecipeTranslationError.unreadable }
        guard let text = reply.content.first(where: { $0.type == "text" })?.text else { throw RecipeTranslationError.unreadable }
        return try RecipeTranslations.parse(text, source: source, language: language, model: Self.model)
    }
}

extension RecipeTranslationSource {
    init(recipe: RecipeX) {
        self.init(title: recipe.safeTitle, headerNotes: recipe.headerNotes, yield: recipe.yield,
                  ingredientSections: recipe.ingredientSections, instructionSections: recipe.instructionSections,
                  notes: recipe.notes)
    }
}

// MARK: - Publishing

extension CloudKitSharingService {

    /// The translations to publish with a recipe: every one that still matches its English,
    /// from this device's cache or already on its public copy. nil when there are none.
    func publishableTranslationsJSON(for recipe: RecipeX, existingRecord: CKRecord?) -> String? {
        let fingerprint = RecipeTranslationSource(recipe: recipe).fingerprint
        var map: [String: RecipeTranslation] = [:]
        if let existingRecord {
            for (language, t) in Self.publishedTranslations(in: existingRecord) where t.source == fingerprint {
                map[language] = t
            }
        }
        for language in RecipeLocalizer.targetLanguages {
            if let t = RecipeLocalizer.shared.cached(recipe.safeID, language: language, fingerprint: fingerprint) {
                map[language] = t
            }
        }
        guard let json = RecipeTranslations.encode(map) else { return nil }
        guard json.utf8.count <= RecipeLocalizer.byteBudget else {
            AppLog.warning("🌐 Translations for '\(recipe.safeTitle)' are too large to publish (\(json.utf8.count) bytes)", category: .sharing)
            return nil
        }
        return json
    }

    /// The translations a public recipe record carries.
    static func publishedTranslations(in record: CKRecord) -> [String: RecipeTranslation] {
        guard let text = record["recipeData"] as? String, let data = text.data(using: .utf8),
              let recipe = try? JSONDecoder().decode(CloudKitRecipe.self, from: data) else { return [:] }
        return RecipeTranslations.decode(recipe.translationsJSON)
    }

    private static var localizationTask: Task<Void, Never>?

    /// Starts the localization pass unless one is running. Called at the end of every
    /// publish pass; does not wait for it.
    func startLocalizationPass(modelContext: ModelContext) {
        guard Self.localizationTask == nil, !RecipeLocalizer.targetLanguages.isEmpty else { return }
        guard !(APIKeyHelper.getAPIKey() ?? "").isEmpty else {
            AppLog.info("🌐 Translations: no Claude key, recipes stay in English on the web", category: .sharing)
            return
        }
        Self.localizationTask = Task { @MainActor in
            await self.performLocalizationPass(modelContext: modelContext)
            Self.localizationTask = nil
        }
    }

    private struct LocalizationItem {
        let recipe: RecipeX
        let id: UUID
        let recordName: String
        let source: RecipeTranslationSource
        let fingerprint: String
        let missing: [String]
    }

    /// Drops what has been published since the pass read the public list (another device).
    private func stillMissing(_ round: [LocalizationItem]) async -> [LocalizationItem] {
        let ids = round.map { CKRecord.ID(recordName: $0.recordName) }
        guard let results = try? await publicDatabase.records(for: ids, desiredKeys: ["recipeData"]) else { return round }
        return round.compactMap { item in
            guard case .success(let record)? = results[CKRecord.ID(recordName: item.recordName)] else { return item }
            let published = Self.publishedTranslations(in: record)
            let missing = item.missing.filter { published[$0]?.source != item.fingerprint }
            return missing.isEmpty ? nil : LocalizationItem(recipe: item.recipe, id: item.id, recordName: item.recordName,
                                                            source: item.source, fingerprint: item.fingerprint, missing: missing)
        }
    }

    private func performLocalizationPass(modelContext: ModelContext) async {
        let languages = RecipeLocalizer.targetLanguages
        let localizer = RecipeLocalizer.shared
        guard isCloudKitAvailable, currentUserID != nil,
              let index = await readOwnPublicIndex(.recipe) else { return }
        let deleted = index.deleted

        // What each live public copy lacks. Recipes not public yet are published by the
        // publish pass first and picked up by the next localization pass.
        var todo: [LocalizationItem] = []
        for recipe in (try? modelContext.fetch(FetchDescriptor<RecipeX>())) ?? [] {
            guard let id = recipe.id, deleted[id] == nil, let live = index.live[id],
                  !OwnerDeletedStore.shared.isPendingTombstone(.recipe, id) else { continue }
            let source = RecipeTranslationSource(recipe: recipe)
            let fingerprint = source.fingerprint
            let record = index.liveRecords[id]?.first { $0.recordID.recordName == live.recordName }
            let published = record.map(Self.publishedTranslations(in:)) ?? [:]
            let missing = languages.filter {
                published[$0]?.source != fingerprint && !localizer.wasRefused(id, language: $0, fingerprint: fingerprint)
            }
            if !missing.isEmpty {
                todo.append(LocalizationItem(recipe: recipe, id: id, recordName: live.recordName,
                                             source: source, fingerprint: fingerprint, missing: missing))
            }
        }
        guard !todo.isEmpty else {
            AppLog.info("🌐 Translations: every public recipe is in \(languages.joined(separator: ", "))", category: .sharing)
            return
        }
        AppLog.info("🌐 Translations: \(todo.count) recipe(s) to put into \(languages.joined(separator: ", "))", category: .sharing)

        // Another device may be working through the same list; a different order on each
        // means they seldom reach the same recipe at once (each round re-checks, below).
        todo.shuffle()

        var published = 0, failed = 0
        let status = LibrarySyncStatus.shared
        var start = 0
        while start < todo.count {
            var round = Array(todo[start..<min(start + RecipeLocalizer.roundSize, todo.count)])
            start += round.count
            round = await stillMissing(round)

            // 1. Translate what this device hasn't already.
            var jobs: [(id: UUID, language: String, source: RecipeTranslationSource)] = []
            for item in round {
                for language in item.missing where localizer.cached(item.id, language: language, fingerprint: item.fingerprint) == nil {
                    jobs.append((item.id, language, item.source))
                }
            }
            var stop = false
            await withTaskGroup(of: (UUID, String, String, Result<RecipeTranslation, Error>).self) { group in
                var next = 0
                func addJob() {
                    guard next < jobs.count else { return }
                    let job = jobs[next]; next += 1
                    group.addTask { @MainActor in
                        do { return (job.id, job.language, job.source.fingerprint, .success(try await localizer.translate(job.source, to: job.language))) }
                        catch { return (job.id, job.language, job.source.fingerprint, .failure(error)) }
                    }
                }
                for _ in 0..<RecipeLocalizer.maxConcurrent { addJob() }
                for await (id, language, fingerprint, result) in group {
                    switch result {
                    case .success(let t):
                        localizer.store(t, id: id, language: language)
                    case .failure(let error as RecipeTranslationError):
                        localizer.markRefused(id, language: language, fingerprint: fingerprint)
                        AppLog.warning("🌐 Translation refused (\(error)) for \(id) [\(language)]", category: .sharing)
                    case .failure(let error as ClaudeServiceIssue) where [.keyMissing, .keyRejected, .accessDenied, .outOfCredit].contains(error):
                        AppLog.warning("🌐 Translations stopped: \(error)", category: .sharing)
                        stop = true
                    case .failure(let error):
                        AppLog.warning("🌐 Translation failed for \(id) [\(language)]: \(error.localizedDescription)", category: .sharing)
                    }
                    if !stop { addJob() }
                }
            }

            // 2. Publish the round (same lock as the publish pass and Update All Public Books).
            let ready = round.filter { item in
                item.missing.contains { localizer.cached(item.id, language: $0, fingerprint: item.fingerprint) != nil }
            }
            if !ready.isEmpty {
                while let running = publishTask { await running.value }
                let work = Task { @MainActor () -> (Int, Int) in
                    var ok = 0, bad = 0
                    for item in ready where !item.recipe.isDeleted {
                        do {
                            _ = try await self.shareRecipe(item.recipe, modelContext: modelContext, refreshExisting: true,
                                                           knownRecordName: item.recordName, scanForDuplicates: false)
                            ok += 1
                        } catch {
                            bad += 1
                            AppLog.warning("🌐 Could not publish translations for '\(item.recipe.safeTitle)': \(error.localizedDescription)", category: .sharing)
                        }
                    }
                    return (ok, bad)
                }
                publishTask = Task { @MainActor in _ = await work.value }
                let (ok, bad) = await work.value
                publishTask = nil
                published += ok
                failed += bad
            }
            status.publishProgress(done: min(start, todo.count), total: todo.count)
            if stop { break }
        }
        status.publishFinished()
        AppLog.info("🌐 Translations done: \(published) recipe(s) published, \(failed) to retry", category: .sharing)
    }
}
