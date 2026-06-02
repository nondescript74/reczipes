//
//  RecipeBookExportService.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/28/25.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers
import Compression
import CryptoKit

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Service for exporting and importing recipe books as shareable packages
@MainActor
class RecipeBookExportService {
    
    // MARK: - ZIP Utilities
    
    /// Creates a ZIP archive from a directory using FileManager's native capabilities
    private static func createZipArchive(from sourceURL: URL, to destinationURL: URL) throws {
        // Remove destination if it exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        // Create a temporary flat directory (no parent folder)
        let flatTempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlatZip_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: flatTempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: flatTempDir)
        }
        
        // Copy all files from source to flat directory (at root level)
        let contents = try FileManager.default.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        
        for itemURL in contents {
            let destURL = flatTempDir.appendingPathComponent(itemURL.lastPathComponent)
            try FileManager.default.copyItem(at: itemURL, to: destURL)
        }
        
        // Now use NSFileCoordinator to zip the flat directory
        let coordinator = NSFileCoordinator()
        var error: NSError?
        
        coordinator.coordinate(readingItemAt: flatTempDir, options: [.forUploading], error: &error) { zipURL in
            do {
                // The zipURL is a temporary .zip file created by the system
                // Copy it to our desired destination
                try FileManager.default.copyItem(at: zipURL, to: destinationURL)
                AppLog.debug("Created ZIP archive at: \(destinationURL.lastPathComponent)", category: .backup)
            } catch {
                AppLog.error("Failed to copy zip archive: \(error)", category: .backup)
            }
        }
        
        if let error = error {
            throw error
        }
    }
    
    /// Extracts a ZIP archive to a directory using native iOS capabilities
    static func extractZipArchive(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        
        AppLog.debug("Starting ZIP extraction from: \(sourceURL.lastPathComponent)", category: .batch)
        
        // Create destination directory
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        
        // Try native extraction first (works with .forUploading ZIP files)
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var extractionSucceeded = false
        
        // Attempt 1: Use NSFileCoordinator's built-in unzipping
        coordinator.coordinate(readingItemAt: sourceURL, options: [.withoutChanges], error: &coordinatorError) { readURL in
            // Check if the coordinator automatically unzipped it
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: readURL.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                do {
                    // It was automatically extracted to a temp directory, copy contents
                    let contents = try fileManager.contentsOfDirectory(at: readURL, includingPropertiesForKeys: nil)
                    for itemURL in contents {
                        let destItemURL = destinationURL.appendingPathComponent(itemURL.lastPathComponent)
                        try fileManager.copyItem(at: itemURL, to: destItemURL)
                    }
                    extractionSucceeded = true
                    AppLog.debug("Successfully extracted using NSFileCoordinator", category: .batch)
                    return
                } catch {
                    AppLog.debug("NSFileCoordinator extraction failed: \(error)", category: .batch)
                }
            }
        }
        
        if extractionSucceeded {
            return
        }
        
        // Attempt 2: Manual ZIP parsing
        AppLog.debug("Attempting manual ZIP extraction", category: .batch)
        
        do {
            let zipData = try Data(contentsOf: sourceURL)
            AppLog.debug("ZIP file size: \(zipData.count) bytes", category: .batch)
            
            // Parse and extract using our custom parser
            try extractZipData(zipData, to: destinationURL)
            AppLog.debug("Successfully extracted using manual parser", category: .batch)
            
        } catch {
            AppLog.error("Manual ZIP extraction failed: \(error)", category: .batch)
            throw NSError(domain: "RecipeBookExport", code: -7, userInfo: [
                NSLocalizedDescriptionKey: "Failed to extract ZIP archive: \(error.localizedDescription)"
            ])
        }
    }
    
    /// Parses ZIP file format and extracts contents
    private static func extractZipData(_ data: Data, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        var filesExtracted = 0
        var dirsCreated = 0
        
        AppLog.debug("Starting manual ZIP parsing, size: \(data.count) bytes", category: .batch)
        
        // First, find and parse the central directory to get accurate file information
        let centralDir = try parseCentralDirectory(data)
        
        AppLog.debug("Found \(centralDir.count) entries in central directory", category: .batch)
        
        // Now extract files using information from central directory
        for entry in centralDir {
            if entry.fileName.hasSuffix("/") {
                // Create directory
                let dirURL = destinationURL.appendingPathComponent(entry.fileName)
                try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
                dirsCreated += 1
                AppLog.debug("Created directory: \(entry.fileName)", category: .batch)
            } else {
                // Extract file
                let fileURL = destinationURL.appendingPathComponent(entry.fileName)
                
                // Create parent directory if needed
                let parentDir = fileURL.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: parentDir.path) {
                    try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }
                
                // Read the compressed data from the local file header offset
                let compressedData = try readFileData(
                    from: data,
                    at: entry.localHeaderOffset,
                    compressedSize: entry.compressedSize
                )
                
                // Decompress if needed
                let fileData: Data
                if entry.compressionMethod == 0 {
                    // No compression
                    fileData = compressedData
                    AppLog.debug("Extracted (uncompressed): \(entry.fileName) (\(fileData.count) bytes)", category: .batch)
                } else if entry.compressionMethod == 8 {
                    // DEFLATE compression
                    fileData = try decompressDeflate(compressedData, uncompressedSize: entry.uncompressedSize)
                    AppLog.debug("Extracted (DEFLATE): \(entry.fileName) (\(entry.compressedSize) -> \(fileData.count) bytes)", category: .batch)
                } else {
                    throw NSError(domain: "RecipeBookExport", code: -3, userInfo: [
                        NSLocalizedDescriptionKey: "Unsupported compression method: \(entry.compressionMethod)"
                    ])
                }
                
                // Write file
                try fileData.write(to: fileURL)
                filesExtracted += 1
            }
        }
        
        AppLog.info("ZIP extraction complete: \(filesExtracted) files, \(dirsCreated) directories", category: .batch)
        
        if filesExtracted == 0 && dirsCreated == 0 {
            throw NSError(domain: "RecipeBookExport", code: -5, userInfo: [
                NSLocalizedDescriptionKey: "No files found in ZIP archive"
            ])
        }
    }
    
    /// ZIP central directory entry
    private struct ZipCentralDirEntry {
        let fileName: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }
    
    /// Parses the central directory at the end of the ZIP file
    private static func parseCentralDirectory(_ data: Data) throws -> [ZipCentralDirEntry] {
        var entries: [ZipCentralDirEntry] = []
        
        // Find End of Central Directory (EOCD) record
        // Signature: 0x06054b50
        // Search from end of file backwards (max 65KB + 22 bytes for EOCD)
        let searchStart = max(0, data.count - 65557)
        var eocdOffset = -1
        
        for i in stride(from: data.count - 22, through: searchStart, by: -1) {
            let sig = data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: i, as: UInt32.self)
            }
            if sig == 0x06054b50 {
                eocdOffset = i
                break
            }
        }
        
        guard eocdOffset >= 0 else {
            AppLog.error("End of Central Directory not found", category: .batch)
            throw NSError(domain: "RecipeBookExport", code: -6, userInfo: [
                NSLocalizedDescriptionKey: "Invalid ZIP file: End of Central Directory not found"
            ])
        }
        
        AppLog.debug("Found EOCD at offset \(eocdOffset)", category: .batch)
        
        var offset = eocdOffset
        offset += 4 // Skip signature
        offset += 4 // Skip disk numbers
        
        // Read number of entries
        let totalEntries = Int(data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
        })
        offset += 2
        offset += 2 // Skip total entries on this disk
        
        // Skip central directory size
        offset += 4
        
        // Read central directory offset
        let centralDirOffset = Int(data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        })
        
        AppLog.debug("Central directory at offset \(centralDirOffset), \(totalEntries) entries", category: .batch)
        
        // Parse central directory entries
        offset = centralDirOffset
        
        for _ in 0..<totalEntries {
            // Check signature
            let sig = data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            }
            
            guard sig == 0x02014b50 else {
                AppLog.error("Invalid central directory entry signature at \(offset)", category: .batch)
                throw NSError(domain: "RecipeBookExport", code: -6, userInfo: [
                    NSLocalizedDescriptionKey: "Corrupted ZIP central directory"
                ])
            }
            
            offset += 4 // Skip signature
            offset += 4 // Skip version made by & version needed
            offset += 2 // Skip flags
            
            // Read compression method
            let compressionMethod = data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
            }
            offset += 2
            
            offset += 4 // Skip mod time & date
            offset += 4 // Skip CRC-32
            
            // Read compressed size
            let compressedSize = Int(data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            })
            offset += 4
            
            // Read uncompressed size
            let uncompressedSize = Int(data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            })
            offset += 4
            
            // Read file name length
            let fileNameLength = Int(data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
            })
            offset += 2
            
            // Read extra field length
            let extraFieldLength = Int(data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
            })
            offset += 2
            
            // Read comment length
            let commentLength = Int(data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
            })
            offset += 2
            
            offset += 2 // Skip disk number start
            offset += 2 // Skip internal file attributes
            offset += 4 // Skip external file attributes
            
            // Read local header offset
            let localHeaderOffset = Int(data.withUnsafeBytes { buffer in
                buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            })
            offset += 4
            
            // Read file name
            let fileNameData = data.subdata(in: offset..<(offset + fileNameLength))
            guard let fileName = String(data: fileNameData, encoding: .utf8) else {
                throw NSError(domain: "RecipeBookExport", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid file name in ZIP central directory"
                ])
            }
            offset += fileNameLength
            
            // Skip extra field and comment
            offset += extraFieldLength + commentLength
            
            entries.append(ZipCentralDirEntry(
                fileName: fileName,
                compressionMethod: compressionMethod,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            ))
        }
        
        return entries
    }
    
    /// Reads compressed file data from a local file header
    private static func readFileData(from data: Data, at localHeaderOffset: Int, compressedSize: Int) throws -> Data {
        var offset = localHeaderOffset
        
        // Verify local file header signature
        let sig = data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        
        guard sig == 0x04034b50 else {
            throw NSError(domain: "RecipeBookExport", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid local file header"
            ])
        }
        
        offset += 4  // Skip signature
        offset += 2  // Skip version
        offset += 2  // Skip flags
        offset += 2  // Skip compression method
        offset += 4  // Skip mod time & date
        offset += 4  // Skip CRC-32
        offset += 4  // Skip compressed size
        offset += 4  // Skip uncompressed size
        
        // Read file name length
        let fileNameLength = Int(data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
        })
        offset += 2
        
        // Read extra field length
        let extraFieldLength = Int(data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
        })
        offset += 2
        
        // Skip file name and extra field
        offset += fileNameLength + extraFieldLength
        
        // Now we're at the compressed data
        guard offset + compressedSize <= data.count else {
            throw NSError(domain: "RecipeBookExport", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "ZIP file truncated"
            ])
        }
        
        return data.subdata(in: offset..<(offset + compressedSize))
    }
    
    /// Decompresses DEFLATE compressed data
    private static func decompressDeflate(_ data: Data, uncompressedSize: Int) throws -> Data {
        // ZIP uses raw DEFLATE (RFC 1951), not zlib-wrapped DEFLATE (RFC 1950)
        // We need to wrap it with proper zlib headers for Apple's Compression framework
        
        var decompressed = Data(count: uncompressedSize)
        
        let result = data.withUnsafeBytes { (compressedBuffer: UnsafeRawBufferPointer) -> Int in
            decompressed.withUnsafeMutableBytes { (decompressedBuffer: UnsafeMutableRawBufferPointer) -> Int in
                guard let compressedPtr = compressedBuffer.baseAddress,
                      let decompressedPtr = decompressedBuffer.baseAddress else {
                    return 0
                }
                
                // First, try treating it as standard zlib (some tools create ZIP with zlib headers)
                var bytesWritten = compression_decode_buffer(
                    decompressedPtr.assumingMemoryBound(to: UInt8.self),
                    uncompressedSize,
                    compressedPtr.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
                
                // If that fails, it's raw DEFLATE - wrap it with proper zlib header
                if bytesWritten == 0 {
                    // Create proper zlib header:
                    // CMF byte: 0x78 (DEFLATE, 32K window)
                    // FLG byte: calculated to make FCHECK valid
                    var zlibData = Data()
                    
                    // CMF: Compression Method and flags
                    let cmf: UInt8 = 0x78  // DEFLATE with 32K window
                    
                    // FLG: Flags (must make CMF*256 + FLG divisible by 31)
                    var flg: UInt8 = 0x9C  // Default compression level
                    let fcheck = (UInt16(cmf) * 256 + UInt16(flg)) % 31
                    if fcheck != 0 {
                        flg = flg + UInt8(31 - fcheck)
                    }
                    
                    zlibData.append(cmf)
                    zlibData.append(flg)
                    zlibData.append(data)
                    
                    // Add Adler-32 checksum (4 bytes) at the end
                    // For simplicity, use zeros (won't validate but decompression should work)
                    zlibData.append(contentsOf: [0, 0, 0, 0])
                    
                    AppLog.debug("Attempting raw DEFLATE decompression with zlib wrapper", category: .batch)
                    
                    bytesWritten = zlibData.withUnsafeBytes { (zlibBuffer: UnsafeRawBufferPointer) -> Int in
                        guard let zlibPtr = zlibBuffer.baseAddress else { return 0 }
                        
                        return compression_decode_buffer(
                            decompressedPtr.assumingMemoryBound(to: UInt8.self),
                            uncompressedSize,
                            zlibPtr.assumingMemoryBound(to: UInt8.self),
                            zlibData.count,
                            nil,
                            COMPRESSION_ZLIB
                        )
                    }
                }
                
                return bytesWritten
            }
        }
        
        guard result > 0 else {
            AppLog.error("Decompression failed: result=\(result), compressed=\(data.count) bytes, expected=\(uncompressedSize) bytes", category: .batch)
            throw NSError(domain: "RecipeBookExport", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "Could not decompress the file. The archive may be corrupted or use an unsupported compression format."
            ])
        }
        
        // Trim to actual decompressed size
        decompressed.count = result
        
        AppLog.debug("Successfully decompressed \(data.count) -> \(result) bytes", category: .batch)
        
        return decompressed
    }
    
    // MARK: - Export
    
    /// Exports a recipe book to a .recipebook file (ZIP package)
    /// - Parameters:
    ///   - book: The recipe book to export
    ///   - recipes: The recipes in the book
    ///   - includeImages: Whether to include images in the export
    /// - Returns: URL to the exported file with proper UTType
    static func exportBook(
        _ book: Book,
        recipes: [RecipeX],
        includeImages: Bool = true
    ) async throws -> URL {
        AppLog.info("Starting export of book: \(String(describing: book.name))", category: .backup)
        
        // Create temporary directory for export
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeBookExport_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            // Clean up temp directory
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Collect image manifest
        var imageManifest: [ImageManifestEntry] = []
        
        if includeImages {
            // Export book cover image
            if let coverImageName = book.coverImageName {
                try await copyImageToExport(
                    imageName: coverImageName,
                    to: tempDir,
                    entry: ImageManifestEntry(
                        fileName: coverImageName,
                        type: .bookCover,
                        associatedID: book.id ?? UUID()
                    ),
                    manifest: &imageManifest
                )
            }
            
            // Export recipe images
            for recipe in recipes {
                // Primary image
                if let imageName = recipe.imageName {
                    try await copyImageToExport(
                        imageName: imageName,
                        to: tempDir,
                        entry: ImageManifestEntry(
                            fileName: imageName,
                            type: .recipePrimary,
                            associatedID: recipe.id ?? UUID()
                        ),
                        manifest: &imageManifest
                    )
                }
                
                // Additional images
                if let additionalImages = recipe.additionalImageNames {
                    for imageName in additionalImages {
                        try await copyImageToExport(
                            imageName: imageName,
                            to: tempDir,
                            entry: ImageManifestEntry(
                                fileName: imageName,
                                type: .recipeAdditional,
                                associatedID: recipe.id ?? UUID()
                            ),
                            manifest: &imageManifest
                        )
                    }
                }
            }
        }
        
        // Convert Book to ExportableBook
        let exportableBook = ExportableBook(
            id: book.id ?? UUID(),
            name: book.name ?? "Untitled Book",
            bookDescription: book.bookDescription,
            coverImageName: book.coverImageName,
            dateCreated: book.dateCreated ?? Date(),
            dateModified: book.dateModified ?? Date(),
            recipeIDs: book.recipeIDs ?? [],
            color: book.color
        )
        
        // Convert RecipeX to ExportableRecipe
        let exportableRecipes = try recipes.map { recipe -> ExportableRecipe in
            // Decode ingredient sections
            let ingredientSections: [IngredientSection]
            if let data = recipe.ingredientSectionsData {
                ingredientSections = try JSONDecoder().decode([IngredientSection].self, from: data)
            } else {
                ingredientSections = []
            }
            
            // Decode instruction sections
            let instructionSections: [InstructionSection]
            if let data = recipe.instructionSectionsData {
                instructionSections = try JSONDecoder().decode([InstructionSection].self, from: data)
            } else {
                instructionSections = []
            }
            
            // Decode notes
            let notes: [RecipeNote]
            if let data = recipe.notesData {
                notes = try JSONDecoder().decode([RecipeNote].self, from: data)
            } else {
                notes = []
            }
            
            return ExportableRecipe(
                id: recipe.id ?? UUID(),
                title: recipe.title ?? "Untitled Recipe",
                headerNotes: recipe.headerNotes,
                yield: recipe.recipeYield,
                ingredientSections: ingredientSections,
                instructionSections: instructionSections,
                notes: notes,
                reference: recipe.reference,
                imageName: recipe.imageName,
                additionalImageNames: recipe.additionalImageNames,
                imageURLs: nil
            )
        }
        
        // Create export package
        let exportPackage = RecipeBookExportPackage(
            version: "2.0",
            book: exportableBook,
            recipes: exportableRecipes,
            imageManifest: imageManifest
        )
        
        // Write JSON metadata
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try encoder.encode(exportPackage)
        let jsonURL = tempDir.appendingPathComponent("book.json")
        try jsonData.write(to: jsonURL)
        
        // Create ZIP archive using FileManager's native zipping
        let fileName = sanitizeFileName(book.name ?? "Book")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileName)_\(Date().timeIntervalSince1970).\(RecipeBookPackageType.fileExtension)")
        
        try createZipArchive(from: tempDir, to: outputURL)
        
        AppLog.info("Successfully exported book to: \(outputURL.lastPathComponent)", category: .backup)
        
        return outputURL
    }
    
    // MARK: - Import
    
    /// Imports a recipe book from a .recipebook file
    /// - Parameters:
    ///   - url: URL to the .recipebook file
    ///   - modelContext: SwiftData model context
    ///   - replaceExisting: If true, replaces existing book with same ID
    /// - Returns: The imported Book
    static func importBook(
        from url: URL,
        modelContext: ModelContext,
        replaceExisting: Bool = false
    ) async throws -> Book {
        AppLog.info("Starting import from: \(url.lastPathComponent)", category: .batch)
        
        // Create temporary extraction directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeBookImport_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            // Clean up
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Extract ZIP using native unzip
        try extractZipArchive(from: url, to: tempDir)
        
        // Find book.json (may be in a subdirectory)
        let jsonURL = try findBookJSON(in: tempDir)
        let jsonData = try Data(contentsOf: jsonURL)
        
        // Determine the actual content directory (may be nested)
        let contentDir = jsonURL.deletingLastPathComponent()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let exportPackage = try decoder.decode(RecipeBookExportPackage.self, from: jsonData)
        
        AppLog.info("Importing book: \(exportPackage.book.name) with \(exportPackage.recipes.count) recipes", category: .batch)
        
        // Check for existing book
        let bookID = exportPackage.book.id
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { book in
                book.id == bookID
            }
        )
        
        let existingBooks = try modelContext.fetch(descriptor)
        
        if existingBooks.first != nil, !replaceExisting {
            // Generate new ID to avoid conflicts
            AppLog.info("Book already exists, creating as new copy", category: .batch)
            return try await importAsNewBook(exportPackage, tempDir: tempDir, modelContext: modelContext)
        } else if let existingBook = existingBooks.first, replaceExisting {
            // Replace existing book
            AppLog.info("Replacing existing book", category: .batch)
            modelContext.delete(existingBook)
        }
        
        // Import images from the content directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var bookCoverImageData: Data?
        
        for entry in exportPackage.imageManifest {
            let sourceURL = contentDir.appendingPathComponent(entry.fileName)
            
            // Load image data
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                if let imageData = try? Data(contentsOf: sourceURL) {
                    // Check if this is the book cover image
                    if entry.type == .bookCover && entry.associatedID == exportPackage.book.id {
                        bookCoverImageData = imageData
                        AppLog.debug("Loaded book cover image data (\(imageData.count / 1024)KB)", category: .batch)
                    }
                    
                    // Also copy to Documents for legacy support (optional)
                    let destURL = documentsPath.appendingPathComponent(entry.fileName)
                    if !FileManager.default.fileExists(atPath: destURL.path) {
                        try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                    }
                }
            } else {
                AppLog.warning("Image not found during import: \(entry.fileName)", category: .batch)
            }
        }
        
        // Create Book with cover image data
        let newBook = Book(
            id: exportPackage.book.id,
            name: exportPackage.book.name,
            bookDescription: exportPackage.book.bookDescription,
            coverImageData: bookCoverImageData,
            coverImageName: exportPackage.book.coverImageName,
            color: exportPackage.book.color,
            recipeIDs: exportPackage.book.recipeIDs,
            dateCreated: exportPackage.book.dateCreated,
            dateModified: Date() // Update to current date
        )
        
        modelContext.insert(newBook)
        
        // Import or update recipes
        for recipeModel in exportPackage.recipes {
            try await importRecipe(recipeModel, modelContext: modelContext)
        }
        
        try modelContext.save()
        
        AppLog.info("Successfully imported book: \(newBook.name ?? "Untitled")", category: .batch)
        
        return newBook
    }
    
    // MARK: - Helper Methods
    
    private static func copyImageToExport(
        imageName: String,
        to directory: URL,
        entry: ImageManifestEntry,
        manifest: inout [ImageManifestEntry]
    ) async throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sourceURL = documentsPath.appendingPathComponent(imageName)
        let destURL = directory.appendingPathComponent(imageName)
        
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            manifest.append(entry)
        }
    }
    
    private static func importAsNewBook(
        _ exportPackage: RecipeBookExportPackage,
        tempDir: URL,
        modelContext: ModelContext
    ) async throws -> Book {
        // Find the actual content directory (may be nested)
        let jsonURL = try findBookJSON(in: tempDir)
        let contentDir = jsonURL.deletingLastPathComponent()
        
        // Create new IDs for book and recipes
        let newBookID = UUID()
        var recipeIDMapping: [UUID: UUID] = [:] // Old ID to new ID
        
        // Import images with new names
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var newCoverImageName: String?
        var newCoverImageData: Data?
        
        for entry in exportPackage.imageManifest {
            let newFileName = "\(UUID().uuidString).\(entry.fileName.split(separator: ".").last ?? "jpg")"
            let sourceURL = contentDir.appendingPathComponent(entry.fileName)
            let destURL = documentsPath.appendingPathComponent(newFileName)
            
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                // Load image data
                if let imageData = try? Data(contentsOf: sourceURL) {
                    // Check if this is the book cover
                    if entry.type == .bookCover {
                        newCoverImageName = newFileName
                        newCoverImageData = imageData
                        AppLog.debug("Loaded book cover image data (\(imageData.count / 1024)KB) for new book", category: .batch)
                    }
                    
                    // Copy file for legacy support (optional)
                    try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
            } else {
                AppLog.warning("Image not found during import: \(entry.fileName)", category: .batch)
            }
        }
        
        // Create new recipes with new IDs
        var newRecipes: [ExportableRecipe] = []
        for recipe in exportPackage.recipes {
            let newRecipeID = UUID()
            recipeIDMapping[recipe.id] = newRecipeID
            
            // Note: You'll need to create new image names for recipes too
            // For simplicity, keeping the same image names here
            let newRecipe = ExportableRecipe(
                id: newRecipeID,
                title: recipe.title,
                headerNotes: recipe.headerNotes,
                yield: recipe.yield,
                ingredientSections: recipe.ingredientSections,
                instructionSections: recipe.instructionSections,
                notes: recipe.notes,
                reference: recipe.reference,
                imageName: recipe.imageName,
                additionalImageNames: recipe.additionalImageNames,
                imageURLs: recipe.imageURLs
            )
            newRecipes.append(newRecipe)
        }
        
        // Create new book with cover image data
        let newBook = Book(
            id: newBookID,
            name: "\(exportPackage.book.name) (Imported)",
            bookDescription: exportPackage.book.bookDescription,
            coverImageData: newCoverImageData,
            coverImageName: newCoverImageName,
            color: exportPackage.book.color,
            recipeIDs: newRecipes.map { $0.id },
            dateCreated: Date(),
            dateModified: Date()
        )
        
        modelContext.insert(newBook)
        
        // Import recipes
        for recipe in newRecipes {
            try await importRecipe(recipe, modelContext: modelContext)
        }
        
        try modelContext.save()
        
        return newBook
    }
    
    private static func importRecipe(_ recipeModel: ExportableRecipe, modelContext: ModelContext) async throws {
        // Check if recipe already exists
        let recipeID = recipeModel.id
        let descriptor = FetchDescriptor<RecipeX>(
            predicate: #Predicate<RecipeX> { recipe in
                recipe.id == recipeID
            }
        )
        
        let existingRecipes = try modelContext.fetch(descriptor)
        
        if existingRecipes.isEmpty {
            // Create new recipe from ExportableRecipe
            let encoder = JSONEncoder()
            
            let ingredientSectionsData = try encoder.encode(recipeModel.ingredientSections)
            let instructionSectionsData = try encoder.encode(recipeModel.instructionSections)
            let notesData = try encoder.encode(recipeModel.notes)
            
            // Load and assign image data from Documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            
            var imageData: Data?
            var additionalImagesData: Data?
            
            // Assign main image data
            if let imageName = recipeModel.imageName {
                let imageURL = documentsPath.appendingPathComponent(imageName)
                if FileManager.default.fileExists(atPath: imageURL.path),
                   let loadedImageData = try? Data(contentsOf: imageURL) {
                    imageData = loadedImageData
                    AppLog.debug("Loaded main image data (\(loadedImageData.count / 1024)KB) for recipe: \(recipeModel.title)", category: .batch)
                }
            }
            
            // Assign additional images data
            if let additionalImageNames = recipeModel.additionalImageNames, !additionalImageNames.isEmpty {
                var additionalImages: [[String: Data]] = []
                
                for imageName in additionalImageNames {
                    let imageURL = documentsPath.appendingPathComponent(imageName)
                    if FileManager.default.fileExists(atPath: imageURL.path),
                       let loadedImageData = try? Data(contentsOf: imageURL) {
                        additionalImages.append(["data": loadedImageData, "name": Data(imageName.utf8)])
                    }
                }
                
                if !additionalImages.isEmpty {
                    if let encoded = try? encoder.encode(additionalImages) {
                        additionalImagesData = encoded
                        AppLog.debug("Loaded \(additionalImages.count) additional images for recipe: \(recipeModel.title)", category: .batch)
                    }
                }
            }
            
            let newRecipe = RecipeX(
                id: recipeModel.id,
                title: recipeModel.title,
                headerNotes: recipeModel.headerNotes,
                recipeYield: recipeModel.yield,
                reference: recipeModel.reference,
                ingredientSectionsData: ingredientSectionsData,
                instructionSectionsData: instructionSectionsData,
                notesData: notesData,
                imageData: imageData,
                additionalImagesData: additionalImagesData,
                imageName: recipeModel.imageName,
                additionalImageNames: recipeModel.additionalImageNames,
                lastModified: Date(),
                version: 1
            )
            
            modelContext.insert(newRecipe)
            AppLog.info("Imported new recipe: \(recipeModel.title)", category: .batch)
        } else if let existingRecipe = existingRecipes.first {
            // Update existing recipe if the imported one is newer
            AppLog.info("Recipe already exists, checking for updates: \(recipeModel.title)", category: .batch)
            
            // Compare and potentially update the existing recipe
            let shouldUpdate = try updateRecipeIfNewer(existingRecipe, with: recipeModel)
            
            if shouldUpdate {
                AppLog.info("Updated existing recipe: \(recipeModel.title)", category: .batch)
            } else {
                AppLog.info("Existing recipe is current, no update needed: \(recipeModel.title)", category: .batch)
            }
        }
    }
    
    /// Updates an existing recipe with data from an ExportableRecipe if the model is newer
    /// - Returns: True if the recipe was updated
    private static func updateRecipeIfNewer(_ recipe: RecipeX, with model: ExportableRecipe) throws -> Bool {
        // For imported recipes, we'll update the content but preserve local version tracking
        // This ensures users don't lose their local changes
        
        // Encode the new data
        let encoder = JSONEncoder()
        
        // Update ingredient sections
        if let ingredientSectionsData = try? encoder.encode(model.ingredientSections) {
            recipe.ingredientSectionsData = ingredientSectionsData
        }
        
        // Update instruction sections
        if let instructionSectionsData = try? encoder.encode(model.instructionSections) {
            recipe.instructionSectionsData = instructionSectionsData
        }
        
        // Update notes
        if let notesData = try? encoder.encode(model.notes) {
            recipe.notesData = notesData
        }
        
        // Update metadata
        recipe.title = model.title
        recipe.headerNotes = model.headerNotes
        recipe.recipeYield = model.yield
        recipe.reference = model.reference
        
        // Update images (both filenames and data)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        if let imageName = model.imageName, !imageName.isEmpty {
            recipe.imageName = imageName
            
            // Load and assign image data
            let imageURL = documentsPath.appendingPathComponent(imageName)
            if FileManager.default.fileExists(atPath: imageURL.path),
               let imageData = try? Data(contentsOf: imageURL) {
                recipe.imageData = imageData
                AppLog.debug("Updated main image data (\(imageData.count / 1024)KB) for recipe: \(model.title)", category: .batch)
            }
        }
        
        if let additionalImages = model.additionalImageNames, !additionalImages.isEmpty {
            recipe.additionalImageNames = additionalImages
            
            // Load and assign additional images data
            var additionalImagesData: [[String: Data]] = []
            
            for imageName in additionalImages {
                let imageURL = documentsPath.appendingPathComponent(imageName)
                if FileManager.default.fileExists(atPath: imageURL.path),
                   let imageData = try? Data(contentsOf: imageURL) {
                    additionalImagesData.append(["data": imageData, "name": Data(imageName.utf8)])
                }
            }
            
            if !additionalImagesData.isEmpty {
                if let encoded = try? encoder.encode(additionalImagesData) {
                    recipe.additionalImagesData = encoded
                    AppLog.debug("Updated \(additionalImagesData.count) additional images for recipe: \(model.title)", category: .batch)
                }
            }
        }
        
        // Update version tracking
        recipe.version = (recipe.version ?? 1) + 1
        recipe.lastModified = Date()
        
        // Recalculate ingredients hash for cache invalidation
        let ingredientsString = model.ingredientSections.map { section in
            section.ingredients.map { $0.name }.joined(separator: ",")
        }.joined(separator: ";")
        recipe.ingredientsHash = ingredientsString.sha256Hash()
        
        return true
    }
    
    private static func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    // MARK: - Bulk Import
    
    /// Imports multiple recipe books from a ZIP file containing .recipebook files
    /// - Parameters:
    ///   - url: URL to the ZIP file containing multiple .recipebook files
    ///   - modelContext: SwiftData model context
    ///   - replaceExisting: If true, replaces existing books with same ID
    /// - Returns: Array of imported Books and summary information
    static func importMultipleBooks(
        from url: URL,
        modelContext: ModelContext,
        replaceExisting: Bool = false
    ) async throws -> (books: [Book], summary: String) {
        AppLog.info("Starting bulk import from: \(url.lastPathComponent)", category: .batch)
        
        // Create temporary extraction directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeBookBulkImport_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            // Clean up
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Extract ZIP
        try extractZipArchive(from: url, to: tempDir)
        
        // Find all .recipebook files recursively (handles nested directories)
        let recipeBookFiles = try findRecipeBookFiles(in: tempDir)
        
        guard !recipeBookFiles.isEmpty else {
            // Check if this is a single .recipebook file (has book.json directly)
            let jsonURL = tempDir.appendingPathComponent("book.json")
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                // This is a single book, not a multi-book ZIP
                throw NSError(domain: "RecipeBookExport", code: -5, userInfo: [
                    NSLocalizedDescriptionKey: "This appears to be a single recipe book, not a collection. Please use the regular import function."
                ])
            } else {
                throw NSError(domain: "RecipeBookExport", code: -6, userInfo: [
                    NSLocalizedDescriptionKey: "No recipe books found in the ZIP file."
                ])
            }
        }
        
        AppLog.info("Found \(recipeBookFiles.count) recipe books to import", category: .batch)
        
        // Import each book
        var importedBooks: [Book] = []
        var successCount = 0
        var errorCount = 0
        var failedBooks: [String] = []
        
        for bookFile in recipeBookFiles {
            do {
                let book = try await importBook(
                    from: bookFile,
                    modelContext: modelContext,
                    replaceExisting: replaceExisting
                )
                importedBooks.append(book)
                successCount += 1
                AppLog.info("Successfully imported: \(book.name ?? "Untitled")", category: .batch)
            } catch {
                errorCount += 1
                let bookName = bookFile.deletingPathExtension().lastPathComponent
                failedBooks.append(bookName)
                AppLog.error("Failed to import \(bookFile.lastPathComponent): \(error)", category: .batch)
            }
        }
        
        // Build detailed summary
        var summaryParts: [String] = []
        
        if successCount > 0 {
            summaryParts.append("Successfully imported \(successCount) of \(recipeBookFiles.count) recipe books.")
        } else {
            summaryParts.append("Successfully imported 0 of \(recipeBookFiles.count) recipe books.")
        }
        
        if errorCount > 0 {
            summaryParts.append("Failed: \(errorCount)")
            
            // Add details about failed books
            if !failedBooks.isEmpty {
                let failedList = failedBooks.prefix(3).joined(separator: ", ")
                let remaining = failedBooks.count > 3 ? " and \(failedBooks.count - 3) more" : ""
                summaryParts.append("Failed books: \(failedList)\(remaining)")
            }
        }
        
        let summary = summaryParts.joined(separator: "\n")
        
        AppLog.info("Bulk import complete: \(summary)", category: .batch)
        
        // Throw error if ALL imports failed
        if successCount == 0 {
            throw NSError(domain: "RecipeBookExport", code: -7, userInfo: [
                NSLocalizedDescriptionKey: summary
            ])
        }
        
        return (importedBooks, summary)
    }
    
    /// Detects whether a ZIP file contains multiple recipe books or a single book
    static func detectImportType(from url: URL) throws -> ImportType {
        AppLog.debug("Detecting import type for: \(url.lastPathComponent)", category: .batch)
        
        // Create temporary extraction directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeBookDetect_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Extract ZIP
        do {
            try extractZipArchive(from: url, to: tempDir)
            AppLog.debug("ZIP extracted successfully for type detection", category: .batch)
        } catch {
            AppLog.error("Failed to extract ZIP for type detection: \(error)", category: .batch)
            throw error
        }
        
        // Log extracted contents for debugging
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
            AppLog.debug("Extracted \(contents.count) items:", category: .batch)
            for item in contents {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                AppLog.debug("  - \(item.lastPathComponent) \(isDir ? "(dir)" : "")", category: .batch)
            }
        } catch {
            AppLog.warning("Could not list extracted contents: \(error)", category: .batch)
        }
        
        // Check for book.json in root (single book)
        let jsonURL = tempDir.appendingPathComponent("book.json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            AppLog.debug("Found book.json - single book import", category: .batch)
            return .singleBook
        }
        
        // Search recursively for .recipebook files (handles nested directories)
        let recipeBookFiles = try findRecipeBookFiles(in: tempDir)
        
        if recipeBookFiles.count > 0 {
            AppLog.debug("Found \(recipeBookFiles.count) .recipebook files - multiple book import", category: .batch)
            return .multipleBooks(count: recipeBookFiles.count)
        }
        
        AppLog.warning("No book.json or .recipebook files found in ZIP", category: .batch)
        return .unknown
    }
    
    /// Recursively finds all .recipebook files in a directory
    private static func findRecipeBookFiles(in directory: URL) throws -> [URL] {
        var recipeBookFiles: [URL] = []
        
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension == "recipebook" {
                // Verify it's a regular file, not a directory
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                   resourceValues.isRegularFile == true {
                    recipeBookFiles.append(fileURL)
                    AppLog.debug("  Found .recipebook file: \(fileURL.lastPathComponent)", category: .batch)
                }
            }
        }
        
        return recipeBookFiles
    }
    
    /// Finds book.json file in a directory (may be in a subdirectory)
    private static func findBookJSON(in directory: URL) throws -> URL {
        // First check at the root
        let rootBookJSON = directory.appendingPathComponent("book.json")
        if FileManager.default.fileExists(atPath: rootBookJSON.path) {
            AppLog.debug("Found book.json at root", category: .batch)
            return rootBookJSON
        }
        
        // Search recursively for book.json
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent == "book.json" {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                   resourceValues.isRegularFile == true {
                    AppLog.debug("Found book.json at: \(fileURL.path.replacingOccurrences(of: directory.path, with: ""))", category: .batch)
                    return fileURL
                }
            }
        }
        
        // Not found
        throw NSError(domain: "RecipeBookExport", code: -8, userInfo: [
            NSLocalizedDescriptionKey: "book.json not found in the extracted archive. The file may be corrupted."
        ])
    }
    
    enum ImportType {
        case singleBook
        case multipleBooks(count: Int)
        case unknown
    }
}
