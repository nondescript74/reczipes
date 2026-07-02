//
//  RecipeAPIIntegrationView.swift
//  Reczipes2
//
//  Key onboarding and quota-safe smoke testing for recipe-api.com
//

import SwiftUI

struct RecipeAPIIntegrationView: View {
    @State private var isConfigured = APIKeyHelper.isRecipeAPIConfigured
    @State private var recipeAPIKey = ""
    @State private var isSavingKey = false
    @State private var isRunningTest = false
    @State private var statusMessage = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        if isConfigured {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Not Set", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }

                    SecureField("Enter recipe-api.com key (rapi_...)", text: $recipeAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isSavingKey)

                    Button(isSavingKey ? "Validating..." : "Save & Validate Key") {
                        Task {
                            await saveAndValidateKey()
                        }
                    }
                    .disabled(recipeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingKey)

                    if isConfigured {
                        Button("Remove Recipe API Key", role: .destructive) {
                            removeKey()
                        }
                    }
                } header: {
                    Text("Recipe API Key")
                } footer: {
                    Text("Validation uses GET /api/v1/categories, which is a free authenticated endpoint and does not consume paid credits.")
                }

                Section {
                    Button("Run Public Health Check (/health)") {
                        Task {
                            await runHealthCheck()
                        }
                    }
                    .disabled(isRunningTest)

                    Button("Fetch Dinner Sample (/api/v1/dinner)") {
                        Task {
                            await runDinnerCheck()
                        }
                    }
                    .disabled(isRunningTest)

                    Button("Validate Auth (/api/v1/categories)") {
                        Task {
                            await runCategoriesCheck()
                        }
                    }
                    .disabled(!isConfigured || isRunningTest)
                } header: {
                    Text("Quota-Safe Tests")
                } footer: {
                    Text("All tests here avoid metered detail endpoints, so they are safe for low-quota plans.")
                }

                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                    } header: {
                        Text("Latest Result")
                    }
                }

                if showError {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                    } header: {
                        Text("Error")
                    }
                }
            }
            .navigationTitle("Recipe API")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                refreshStatus()
            }
        }
    }

    @MainActor
    private func saveAndValidateKey() async {
        let cleanedKey = recipeAPIKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")

        showError = false
        errorMessage = ""
        isSavingKey = true

        guard cleanedKey.hasPrefix("rapi_") else {
            isSavingKey = false
            showError = true
            errorMessage = "Recipe API keys should start with 'rapi_'."
            return
        }

        let client = RecipeAPIClient(apiKey: cleanedKey)
        let isValid = await client.validateAPIKey()
        guard isValid else {
            isSavingKey = false
            showError = true
            errorMessage = "Could not validate key with /api/v1/categories. Verify the key is active."
            return
        }

        if APIKeyHelper.setRecipeAPIKey(cleanedKey) {
            statusMessage = "Recipe API key validated and saved."
            recipeAPIKey = ""
            refreshStatus()
        } else {
            showError = true
            errorMessage = "Failed to save key to Keychain."
        }

        isSavingKey = false
    }

    private func removeKey() {
        _ = APIKeyHelper.removeRecipeAPIKey()
        statusMessage = "Recipe API key removed."
        showError = false
        errorMessage = ""
        refreshStatus()
    }

    @MainActor
    private func runHealthCheck() async {
        isRunningTest = true
        showError = false

        do {
            let health = try await RecipeAPIClient().fetchHealth()
            statusMessage = "Health OK: \(health.status)"
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }

        isRunningTest = false
    }

    @MainActor
    private func runDinnerCheck() async {
        isRunningTest = true
        showError = false

        do {
            let recipe = try await RecipeAPIClient().fetchDinnerRecipe()
            statusMessage = "Dinner sample fetched: \(recipe.name) (\(recipe.id))"
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }

        isRunningTest = false
    }

    @MainActor
    private func runCategoriesCheck() async {
        isRunningTest = true
        showError = false

        guard let key = APIKeyHelper.getRecipeAPIKey() else {
            showError = true
            errorMessage = "Recipe API key is not configured."
            isRunningTest = false
            return
        }

        do {
            let categories = try await RecipeAPIClient(apiKey: key).fetchCategories()
            statusMessage = "Authenticated successfully. Categories returned: \(categories.count)"
        } catch {
            showError = true
            errorMessage = error.localizedDescription
        }

        isRunningTest = false
    }

    private func refreshStatus() {
        isConfigured = APIKeyHelper.isRecipeAPIConfigured
    }
}

#Preview {
    RecipeAPIIntegrationView()
}
