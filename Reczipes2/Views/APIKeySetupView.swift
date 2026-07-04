//
//  APIKeySetupView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/8/25.
//

import SwiftUI
import OSLog

struct APIKeySetupView: View {
    @Binding var isPresented: Bool
    @State private var apiKey = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isValidating = false
    @State private var skipValidation = false
    @State private var showSuccess = false
    @State private var successMessage = ""

    var log = OSLog(subsystem: "com.headydiscy.Reczipes2", category: "APIKeySetupView")

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Welcome to Reczipes!")
                            .font(.title2)
                            .bold()
                        
                        Text("Enter a valid API key to enable network recipe features.")
                            .font(.body)
                    }
                    .padding(.vertical, 8)
                    
                    Link(destination: URL(string: "https://recipe-api.com/docs")!) {
                        HStack {
                            Text("Get Recipe API Key")
                            .font(.headline)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                } header: {
                    Text("API Key Setup")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("sk-ant-... or rapi_...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("Enter API Key", text: $apiKey)
                            .labelsHidden()
                            .platformTextInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(isValidating)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    if !apiKey.isEmpty {
                        HStack {
                            Text("Key Length:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(apiKey.count) characters")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if apiKey.count < 8 {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.appWarning)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    Toggle("Skip validation (not recommended)", isOn: $skipValidation)
                        .font(.caption)
                    
                    Button(isValidating ? "Validating..." : skipValidation ? "Save Without Validation" : "Save & Validate API Key") {
                        Task {
                            await validateAndSaveAPIKey()
                        }
                    }
                    .disabled(apiKey.isEmpty || isValidating)
                    
                    if isValidating {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Testing API key...")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if showError {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.appCritical)
                            .font(.caption)
                    }
                } header: {
                    Text("Enter Your API Key")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        if !skipValidation {
                            Text("Your API key will be tested before saving.")
                        }
                        Text("It's stored securely in the Keychain.")
                        Text("Supported key formats: 'sk-ant-...' (Anthropic) or 'rapi_...' (recipe-api.com)")
                            .bold()
                        if !apiKey.isEmpty && apiKey.count < 8 {
                            Text("⚠️ Your key looks very short. Double-check you copied the entire key.")
                                .foregroundStyle(Color.appWarning)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                if showSuccess {
                    Section {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.appSuccess)
                        Button("Done") {
                            isPresented = false
                        }
                    }
                }

                if !showSuccess {
                    Section {
                        Button("Skip for Now") {
                            isPresented = false
                        }
                        .foregroundColor(.secondary)
                    } footer: {
                        Text("You can add your API key later in Settings. Without an API key, you won't be able to extract recipes from images.")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Setup")
            .platformNavigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(isValidating)
    }
    
    @MainActor
    private func validateAndSaveAPIKey() async {
        print("🔑 Starting API key validation in setup...")
        
        showError = false
        errorMessage = ""
        isValidating = true
        
        // Sanitize the API key - remove any whitespace, newlines, etc.
        let cleanedKey = apiKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
        
        print("🔑 Original key length: \(apiKey.count), Cleaned key length: \(cleanedKey.count)")
        
        // Basic validation
        guard cleanedKey.hasPrefix("sk-ant-") || cleanedKey.hasPrefix("rapi_") else {
            showError = true
            errorMessage = "Invalid API key format. Keys should start with 'sk-ant-' or 'rapi_'."
            isValidating = false
            return
        }

        let isClaudeKey = cleanedKey.hasPrefix("sk-ant-")
        if isClaudeKey && cleanedKey.count < 50 {
            showError = true
            errorMessage = "Claude API key seems too short. Please copy the complete key."
            isValidating = false
            return
        }
        
        // If skipping validation, just save it
        if skipValidation {
            print("🔑 Skipping validation, saving directly...")
            let saved = isClaudeKey
                ? APIKeyHelper.setAPIKey(cleanedKey)
                : APIKeyHelper.setRecipeAPIKey(cleanedKey)
            if saved {
                print("🔑 API key saved successfully (without validation)!")
                showSuccess = true
                successMessage = isClaudeKey
                    ? "Claude API key saved (validation skipped)."
                    : "Recipe API key saved (validation skipped)."
                apiKey = ""
            } else {
                showError = true
                errorMessage = "Failed to save the API key to Keychain."
            }
            isValidating = false
            return
        }

        // Validate with matching provider
        let isValid: Bool
        if isClaudeKey {
            let client = ClaudeAPIClient(apiKey: cleanedKey)
            isValid = await client.validateAPIKey()
        } else {
            let client = RecipeAPIClient(apiKey: cleanedKey)
            isValid = await client.validateAPIKey()
        }

        isValidating = false

        if isValid {
            print("🔑 API key is valid, saving...")
            let saved = isClaudeKey
                ? APIKeyHelper.setAPIKey(cleanedKey)
                : APIKeyHelper.setRecipeAPIKey(cleanedKey)
            if saved {
                print("🔑 API key saved successfully!")
                showSuccess = true
                successMessage = isClaudeKey
                    ? "Claude API key validated and saved."
                    : "Recipe API key validated and saved."
                apiKey = ""
            } else {
                showError = true
                errorMessage = "Failed to save the API key to Keychain."
            }
        } else {
            print("🔑 API key validation failed")
            showError = true
            errorMessage = isClaudeKey
                ? "Could not validate with Anthropic. Please verify the key is active, or use 'Skip validation'."
                : "Could not validate with recipe-api.com. Please verify the key is active, or use 'Skip validation'."
        }
    }
}

#Preview {
    APIKeySetupView(isPresented: .constant(true))
}
