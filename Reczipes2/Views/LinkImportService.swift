//
//  LinkImportService.swift
//  Reczipes2
//
//  Created for importing recipe links from JSON
//

import Foundation
import SwiftData

/// Service for importing recipe links from JSON files
class LinkImportService {
    
    // MARK: - JSON Sanitization
    
    /// Strips trailing commas before `]` or `}` from a JSON string.
    /// Swift's JSONDecoder does not tolerate trailing commas, but they are
    /// common in hand-edited JSON files.  This regex-based pass runs before
    /// any decode attempt so the rest of the pipeline never sees them.
    static func sanitizeJSON(_ data: Data) -> Data {
        guard var json = String(data: data, encoding: .utf8) else { return data }
        
        // Remove trailing commas before ] or }
        // Matches: optional whitespace, a comma, optional whitespace/newlines, then ] or }
        if let regex = try? NSRegularExpression(pattern: ",\\s*([\\]\\}])") {
            let range = NSRange(json.startIndex..., in: json)
            json = regex.stringByReplacingMatches(in: json, range: range, withTemplate: "$1")
        }
        
        return json.data(using: .utf8) ?? data
    }
    
    /// Import links from a JSON file in the app bundle
    /// - Parameters:
    ///   - filename: Name of the JSON file (including extension)
    ///   - modelContext: SwiftData model context for saving
    ///   - validate: Whether to validate the file before importing (default: true)
    ///   - autoClean: Whether to automatically clean the data (default: false)
    /// - Returns: Number of links imported
    /// - Throws: Import errors
    static func importLinksFromBundle(
        filename: String,
        into modelContext: ModelContext,
        validate: Bool = true,
        autoClean: Bool = false
    ) async throws -> Int {
        AppLog.info("Starting import from bundle file: \(filename)", category: .batch)
        
        // Locate the file in the bundle
        guard let url = Bundle.main.url(forResource: filename.replacingOccurrences(of: ".json", with: ""), withExtension: "json") else {
            AppLog.error("Could not find \(filename) in app bundle", category: .batch)
            throw LinkImportError.fileNotFound
        }
        
        return try await importLinks(from: url, into: modelContext, validate: validate, autoClean: autoClean)
    }
    
    /// Import links from a JSON file URL
    /// - Parameters:
    ///   - url: URL of the JSON file
    ///   - modelContext: SwiftData model context for saving
    ///   - validate: Whether to validate the file before importing (default: true)
    ///   - autoClean: Whether to automatically clean the data (default: false)
    /// - Returns: Number of links imported
    /// - Throws: Import errors
    static func importLinks(
        from url: URL,
        into modelContext: ModelContext,
        validate: Bool = true,
        autoClean: Bool = false
    ) async throws -> Int {
        AppLog.info("Importing links from: \(url.path)", category: .batch)
        
        // Read and sanitize the raw file data first (strips trailing commas etc.)
        let rawData = try Data(contentsOf: url)
        let sanitizedData = sanitizeJSON(rawData)
        
        // Validate the sanitized data if requested
        if validate {
            AppLog.info("Validating JSON file...", category: .batch)
            let validationResult = JSONLinkValidator.validate(data: sanitizedData)
            
            if !validationResult.isValid {
                AppLog.error("Validation failed: \(validationResult.errors.joined(separator: ", "))", category: .batch)
                throw LinkImportError.invalidJSON
            }
            
            AppLog.info("Validation passed: \(validationResult.linkCount) links, \(validationResult.warnings.count) warnings, \(validationResult.duplicateURLs.count) duplicates in file", category: .batch)
        }
        
        // Use sanitized data (with optional duplicate-removal cleaning)
        let data: Data
        if autoClean {
            AppLog.info("Auto-cleaning data before import...", category: .batch)
            // Write sanitized data to a temp file so the cleaner can read it
            let tempInput = FileManager.default.temporaryDirectory.appendingPathComponent("sanitized_links_\(UUID().uuidString).json")
            let tempOutput = FileManager.default.temporaryDirectory.appendingPathComponent("cleaned_links_\(UUID().uuidString).json")
            try sanitizedData.write(to: tempInput)
            try JSONLinkValidator.clean(inputURL: tempInput, outputURL: tempOutput, removeDuplicates: true)
            data = try Data(contentsOf: tempOutput)
            
            // Clean up temp files
            try? FileManager.default.removeItem(at: tempInput)
            try? FileManager.default.removeItem(at: tempOutput)
            AppLog.info("Used cleaned data for import", category: .batch)
        } else {
            data = sanitizedData
        }
        
        AppLog.debug("Read \(data.count) bytes from file", category: .batch)
        
        // Decode JSON
        let decoder = JSONDecoder()
        let jsonLinks = try decoder.decode([JSONLink].self, from: data)
        AppLog.info("Decoded \(jsonLinks.count) links from JSON", category: .batch)
        
        // Filter out already-imported links
        let existingURLs = try await getExistingURLs(from: modelContext)
        let newLinks = jsonLinks.filter { !existingURLs.contains($0.url) }
        
        AppLog.info("Found \(newLinks.count) new links to import (skipping \(jsonLinks.count - newLinks.count) duplicates)", category: .batch)
        
        // Convert to SavedLink models and insert
        var importCount = 0
        for jsonLink in newLinks {
            let savedLink = SavedLink(from: jsonLink)
            modelContext.insert(savedLink)
            importCount += 1
        }
        
        // Save the context
        try modelContext.save()
        AppLog.info("Successfully imported \(importCount) links", category: .batch)
        
        return importCount
    }
    
    /// Import links from JSON data
    /// - Parameters:
    ///   - data: JSON data
    ///   - modelContext: SwiftData model context for saving
    ///   - validate: Whether to validate the data before importing (default: true)
    /// - Returns: Number of links imported
    /// - Throws: Import errors
    static func importLinks(
        from data: Data,
        into modelContext: ModelContext,
        validate: Bool = true
    ) async throws -> Int {
        AppLog.info("Importing links from data (\(data.count) bytes)", category: .batch)
        
        // Validate the data if requested
        if validate {
            AppLog.info("Validating JSON data...", category: .batch)
            let validationResult = JSONLinkValidator.validate(data: data)
            
            if !validationResult.isValid {
                AppLog.error("Validation failed: \(validationResult.errors.joined(separator: ", "))", category: .batch)
                throw LinkImportError.invalidJSON
            }
            
            AppLog.info("Validation passed: \(validationResult.linkCount) links, \(validationResult.warnings.count) warnings", category: .batch)
        }
        
        // Decode JSON
        let decoder = JSONDecoder()
        let jsonLinks = try decoder.decode([JSONLink].self, from: data)
        AppLog.info("Decoded \(jsonLinks.count) links from JSON", category: .batch)
        
        // Filter out already-imported links
        let existingURLs = try await getExistingURLs(from: modelContext)
        let newLinks = jsonLinks.filter { !existingURLs.contains($0.url) }
        
        AppLog.info("Found \(newLinks.count) new links to import (skipping \(jsonLinks.count - newLinks.count) duplicates)", category: .batch)
        
        // Convert to SavedLink models and insert
        var importCount = 0
        for jsonLink in newLinks {
            let savedLink = SavedLink(from: jsonLink)
            modelContext.insert(savedLink)
            importCount += 1
        }
        
        // Save the context
        try modelContext.save()
        AppLog.info("Successfully imported \(importCount) links", category: .batch)
        
        return importCount
    }
    
    /// Get all existing URLs from the database
    private static func getExistingURLs(from modelContext: ModelContext) async throws -> Set<String> {
        let descriptor = FetchDescriptor<SavedLink>()
        let existingLinks = try modelContext.fetch(descriptor)
        return Set(existingLinks.map { $0.url })
    }
    
    /// Delete all saved links (useful for re-importing)
    static func clearAllLinks(from modelContext: ModelContext) throws {
        AppLog.warning("Clearing all saved links", category: .batch)
        
        let descriptor = FetchDescriptor<SavedLink>()
        let allLinks = try modelContext.fetch(descriptor)
        
        for link in allLinks {
            modelContext.delete(link)
        }
        
        try modelContext.save()
        AppLog.info("Cleared \(allLinks.count) links", category: .batch)
    }
}

// MARK: - Error Types

enum LinkImportError: LocalizedError {
    case fileNotFound
    case invalidJSON
    case duplicateURL
    case databaseError
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Could not find the JSON file in the app bundle"
        case .invalidJSON:
            return "The JSON file format is invalid"
        case .duplicateURL:
            return "This URL has already been imported"
        case .databaseError:
            return "Failed to save links to the database"
        }
    }
}
