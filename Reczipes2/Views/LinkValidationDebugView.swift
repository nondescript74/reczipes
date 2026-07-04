//
//  LinkValidationDebugView.swift
//  Reczipes2
//
//  Developer tools for validating and cleaning link JSON files
//

import SwiftUI
import UniformTypeIdentifiers

#if DEBUG

/// Debug view for validating and cleaning JSON link files
struct LinkValidationDebugView: View {
    @State private var validationResult: JSONLinkValidator.ValidationResult?
    @State private var isValidating = false
    @State private var isCleaning = false
    @State private var cleaningSuccess = false
    @State private var cleaningError: String?
    @State private var showingExportSheet = false
    @State private var cleanedFileURL: URL?
    
    var body: some View {
        NavigationStack {
            List {
                // Validation Section
                Section {
                    Button {
                        performValidation()
                    } label: {
                        HStack {
                            Label("Validate Bundle File", systemImage: "checkmark.shield")
                            Spacer()
                            if isValidating {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isValidating)
                    
                    Text("Validates 'links_from_notes.json' from app bundle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let result = validationResult {
                        ValidationResultDetailView(result: result)
                    }
                } header: {
                    Text("Validation")
                }
                
                // Cleaning Section
                Section {
                    Button {
                        performCleaning()
                    } label: {
                        HStack {
                            Label("Clean & Export", systemImage: "sparkles")
                            Spacer()
                            if isCleaning {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isCleaning || isValidating)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cleaning operations:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Removes duplicate URLs")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("• Trims whitespace")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("• Removes empty entries")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("• Formats as pretty JSON")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if cleaningSuccess, let url = cleanedFileURL {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.appSuccess)
                                Text("File cleaned successfully!")
                                    .font(.subheadline)
                            }
                            
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button {
                                showingExportSheet = true
                            } label: {
                                Label("Share File", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    if let error = cleaningError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.appCritical)
                            .padding()
                            .adaptiveToneBackground(.critical, baseOpacity: 0.1)
                            .cornerRadius(8)
                    }
                } header: {
                    Text("Cleaning")
                }
                
                // Info Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Developer Tool", systemImage: "hammer.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.appInfo)
                        
                        Text("Use this tool to validate and clean your JSON link files before importing them into the app.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("The cleaned file will be saved to your Documents folder and can be shared or re-imported.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Link Validation Tools")
            .platformNavigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingExportSheet) {
                if let url = cleanedFileURL {
                    ShareSheet_LVD(items: [url])
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func performValidation() {
        isValidating = true
        validationResult = nil
        
        Task {
            do {
                guard let url = Bundle.main.url(
                    forResource: "links_from_notes",
                    withExtension: "json"
                ) else {
                    throw LinkImportError.fileNotFound
                }
                
                let result = JSONLinkValidator.validate(fileAt: url)
                
                await MainActor.run {
                    validationResult = result
                    isValidating = false
                    
                    // Also print to console for debugging
                    print("\n=== JSON Link Validation Results ===")
                    print(result.summary)
                    print("===================================\n")
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    print("❌ Validation error: \(error)")
                }
            }
        }
    }
    
    private func performCleaning() {
        isCleaning = true
        cleaningSuccess = false
        cleaningError = nil
        cleanedFileURL = nil
        
        Task {
            do {
                guard let inputURL = Bundle.main.url(
                    forResource: "links_from_notes",
                    withExtension: "json"
                ) else {
                    throw LinkImportError.fileNotFound
                }
                
                let documentsPath = FileManager.default.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                )[0]
                
                let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let filename = "links_cleaned_\(timestamp).json"
                let outputURL = documentsPath.appendingPathComponent(filename)
                
                try JSONLinkValidator.clean(
                    inputURL: inputURL,
                    outputURL: outputURL,
                    removeDuplicates: true
                )
                
                await MainActor.run {
                    cleanedFileURL = outputURL
                    cleaningSuccess = true
                    isCleaning = false
                    
                    print("✅ Cleaned file saved to: \(outputURL.path)")
                }
            } catch {
                await MainActor.run {
                    isCleaning = false
                    cleaningError = error.localizedDescription
                    
                    print("❌ Cleaning error: \(error)")
                }
            }
        }
    }
}

// MARK: - Validation Result Detail View

struct ValidationResultDetailView: View {
    let result: JSONLinkValidator.ValidationResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status
            HStack {
                Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.isValid ? .green : .red)
                    .font(.title2)
                Text(result.isValid ? "Valid JSON" : "Invalid JSON")
                    .font(.headline)
            }
            
            // Stats
            VStack(alignment: .leading, spacing: 4) {
                statRow(label: "Total Links", value: "\(result.linkCount)", color: .primary)
                
                if !result.errors.isEmpty {
                    statRow(label: "Errors", value: "\(result.errors.count)", color: .red)
                }
                
                if !result.warnings.isEmpty {
                    statRow(label: "Warnings", value: "\(result.warnings.count)", color: .orange)
                }
                
                if !result.duplicateURLs.isEmpty {
                    statRow(label: "Duplicates", value: "\(result.duplicateURLs.count)", color: .blue)
                }
            }
            .padding(.vertical, 4)
            
            // Detailed errors
            if !result.errors.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Label("Errors", systemImage: "xmark.octagon")
                        .font(.subheadline)
                        .foregroundStyle(Color.appCritical)
                    
                    ForEach(result.errors, id: \.self) { error in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                            Text(error)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
            
            // Detailed warnings
            if !result.warnings.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Label("Warnings", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(Color.appWarning)
                    
                    ForEach(result.warnings.prefix(5), id: \.self) { warning in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                            Text(warning)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    if result.warnings.count > 5 {
                        Text("... and \(result.warnings.count - 5) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
            
            // Duplicates (first few)
            if !result.duplicateURLs.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    Label("Duplicate URLs", systemImage: "doc.on.doc")
                        .font(.subheadline)
                        .foregroundStyle(Color.appInfo)
                    
                    ForEach(result.duplicateURLs.prefix(3), id: \.self) { duplicate in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                            Text(duplicate)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    if result.duplicateURLs.count > 3 {
                        Text("... and \(result.duplicateURLs.count - 3) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
        }
        .padding()
        .background(
            result.isValid ? Color.green.opacity(0.1) : Color.red.opacity(0.1)
        )
        .cornerRadius(12)
    }
    
    private func statRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

// MARK: - Share Sheet Helper

#if os(iOS)
struct ShareSheet_LVD: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct ShareSheet_LVD: View {
    let items: [Any]
    var body: some View { MacShareView(items: items) }
}
#endif

// MARK: - Preview

#Preview {
    LinkValidationDebugView()
}

#endif
