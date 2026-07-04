//
//  APIKeyManagerView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/8/25.
//

import SwiftUI

// MARK: - API Key Manager View

struct APIKeyManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var newAPIKey = ""
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isValidating = false
    @State private var isAPIKeyConfigured = APIKeyHelper.isConfigured
    @State private var isRecipeAPIKeyConfigured = APIKeyHelper.isRecipeAPIConfigured
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isAPIKeyConfigured {
                        HStack {
                            Text("Claude Status")
                            Spacer()
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.appSuccess)
                        }

                        Button("Remove Claude API Key", role: .destructive) {
                            removeAPIKey()
                        }
                    }

                    if isRecipeAPIKeyConfigured {
                        HStack {
                            Text("Recipe API Status")
                            Spacer()
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.appSuccess)
                        }

                        Button("Remove Recipe API Key", role: .destructive) {
                            removeRecipeAPIKey()
                        }
                    }

                    if !isAPIKeyConfigured && !isRecipeAPIKeyConfigured {
                        Text("No API key configured")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("sk-ant-... or rapi_...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("Enter new API key", text: $newAPIKey)
                            .labelsHidden()
                            .platformTextInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(isValidating)
                    }
                    
                    Button(isValidating ? "Validating..." : "Update API Key") {
                        Task {
                            await updateAPIKey()
                        }
                    }
                    .disabled(newAPIKey.isEmpty || isValidating)
                } header: {
                    Text("Update API Key")
                } footer: {
                    Text("Keys are validated with the matching provider before saving to Keychain.")
                }
                
                // Separate section for feedback to make it more visible
                if isValidating || showSuccess || showError {
                    Section {
                        if isValidating {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 8)
                            Text("Testing API key...")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if showSuccess {
                            Label("API key validated and saved successfully!", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.appSuccess)
                        }
                        
                        if showError {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Failed to validate API key", systemImage: "xmark.circle.fill")
                                    .foregroundStyle(Color.appCritical)
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("API Key Manager")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .platformNavBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Refresh the API key status when the view appears
                isAPIKeyConfigured = APIKeyHelper.isConfigured
                isRecipeAPIKeyConfigured = APIKeyHelper.isRecipeAPIConfigured
            }
        }
    }
    
    @MainActor
    private func updateAPIKey() async {
        print("🔑 Starting API key validation...")
        showSuccess = false
        showError = false
        errorMessage = ""
        isValidating = true
        
        print("🔑 isValidating set to true")
        
        // Sanitize the API key - remove any whitespace, newlines, etc.
        let cleanedKey = newAPIKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
        
        print("🔑 Original key length: \(newAPIKey.count), Cleaned key length: \(cleanedKey.count)")
        
        // Basic validation
        if !cleanedKey.hasPrefix("sk-ant-") && !cleanedKey.hasPrefix("rapi_") {
            showError = true
            errorMessage = "Invalid API key format. Keys should start with 'sk-ant-' or 'rapi_'."
            isValidating = false
            return
        }

        let isClaudeKey = cleanedKey.hasPrefix("sk-ant-")
        let isValid: Bool
        if isClaudeKey {
            if cleanedKey.count < 50 {
                showError = true
                errorMessage = "Claude API key seems too short. Please verify you copied the entire key."
                isValidating = false
                return
            }
            let client = ClaudeAPIClient(apiKey: cleanedKey)
            print("🔑 Calling Claude validateAPIKey...")
            isValid = await client.validateAPIKey()
        } else {
            let client = RecipeAPIClient(apiKey: cleanedKey)
            print("🔑 Calling Recipe API validateAPIKey...")
            isValid = await client.validateAPIKey()
        }
        print("🔑 Validation result: \(isValid)")
        
        // All UI updates on main thread
        isValidating = false
        print("🔑 isValidating set to false")
        
        if isValid {
            print("🔑 API key is valid, attempting to save...")
            let saved: Bool
            if isClaudeKey {
                saved = APIKeyHelper.setAPIKey(cleanedKey)
            } else {
                saved = APIKeyHelper.setRecipeAPIKey(cleanedKey)
            }

            if saved {
                print("🔑 API key saved successfully!")
                showSuccess = true
                isAPIKeyConfigured = true
                if !isClaudeKey {
                    isRecipeAPIKeyConfigured = true
                }
                newAPIKey = ""
                
                // Dismiss after showing success
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                print("🔑 Dismissing view...")
                dismiss()
            } else {
                print("🔑 Failed to save to Keychain")
                showError = true
                errorMessage = "Failed to save the API key to Keychain."
            }
        } else {
            print("🔑 API key validation failed")
            // API key is invalid
            showError = true
            errorMessage = isClaudeKey
                ? "Could not validate with Anthropic. Please verify your key is active."
                : "Could not validate with recipe-api.com. Please verify your key is active."
        }
        
        print("🔑 Final state - showSuccess: \(showSuccess), showError: \(showError)")
    }
    
    private func removeAPIKey() {
        _ = KeychainManager.shared.delete(key: "claudeAPIKey")
        isAPIKeyConfigured = false
        // Don't dismiss immediately - let user see the updated state
    }

    private func removeRecipeAPIKey() {
        _ = APIKeyHelper.removeRecipeAPIKey()
        isRecipeAPIKeyConfigured = false
    }
}

#Preview {
    APIKeyManagerView()
}
