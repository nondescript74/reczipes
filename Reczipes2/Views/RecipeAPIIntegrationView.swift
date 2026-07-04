//
//  RecipeAPIIntegrationView.swift
//  Reczipes2
//
//  Key onboarding and quota-safe smoke testing for recipe-api.com
//

import SwiftUI
import OSLog

private let recipeAPILog = Logger(subsystem: "com.headydiscy.Reczipes2", category: "RecipeAPIIntegrationView")

struct RecipeAPIIntegrationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isConfigured = APIKeyHelper.isRecipeAPIConfigured
    @State private var recipeAPIKey = ""
    @State private var isSavingKey = false
    @State private var isRunningTest = false
    @State private var statusMessage = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var skipValidation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        if isConfigured {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.appSuccess)
                        } else {
                            Label("Not Set", systemImage: "xmark.circle.fill")
                                .foregroundStyle(Color.appCritical)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("rapi_...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("Enter recipe-api.com key", text: $recipeAPIKey)
                            .labelsHidden()
                            .platformTextInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(isSavingKey)
                    }

                    Toggle("Skip validation (not recommended)", isOn: $skipValidation)
                        .font(.caption)

                    Button(isSavingKey ? "Saving..." : skipValidation ? "Save Without Validation" : "Save & Validate Key") {
                        recipeAPILog.info("RecipeAPIIntegrationView: Save key tapped, skipValidation=\(skipValidation)")
                        Task { await saveAndValidateKey() }
                    }
                    .disabled(recipeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingKey)

                    if isConfigured {
                        Button("Remove Recipe API Key", role: .destructive) {
                            recipeAPILog.info("RecipeAPIIntegrationView: Remove key tapped")
                            removeKey()
                        }
                    }
                } header: {
                    Text("Recipe API Key")
                } footer: {
                    Text(skipValidation
                         ? "Key will be saved directly without contacting recipe-api.com."
                         : "Validation uses GET /api/v1/categories, which is a free authenticated endpoint and does not consume paid credits.")
                }

                Section {
                    Button("Run Public Health Check (/health)") {
                        recipeAPILog.info("RecipeAPIIntegrationView: Health check tapped")
                        Task { await runHealthCheck() }
                    }
                    .disabled(isRunningTest)

                    Button("Fetch Dinner Sample (/api/v1/dinner)") {
                        recipeAPILog.info("RecipeAPIIntegrationView: Dinner check tapped")
                        Task { await runDinnerCheck() }
                    }
                    .disabled(isRunningTest)

                    Button("Validate Auth (/api/v1/categories)") {
                        recipeAPILog.info("RecipeAPIIntegrationView: Categories check tapped")
                        Task { await runCategoriesCheck() }
                    }
                    .disabled(!isConfigured || isRunningTest)
                } header: {
                    Text("Quota-Safe Tests")
                } footer: {
                    Text("All tests here avoid metered detail endpoints, so they are safe for low-quota plans.")
                }

                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage).font(.footnote)
                    } header: {
                        Text("Latest Result")
                    }
                }

                if showError {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Color.appCritical)
                            .font(.footnote)
                    } header: {
                        Text("Error")
                    }
                }
            }
            .navigationTitle("Recipe API")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { refreshStatus() }
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
            recipeAPILog.warning("RecipeAPIIntegrationView: Key rejected — wrong prefix")
            return
        }

        if !skipValidation {
            recipeAPILog.info("RecipeAPIIntegrationView: Validating key with /api/v1/categories")
            let client = RecipeAPIClient(apiKey: cleanedKey)
            let isValid = await client.validateAPIKey()
            guard isValid else {
                isSavingKey = false
                showError = true
                errorMessage = "Could not validate key with /api/v1/categories. Verify the key is active, or enable 'Skip validation'."
                recipeAPILog.error("RecipeAPIIntegrationView: Validation failed")
                return
            }
            recipeAPILog.info("RecipeAPIIntegrationView: Validation succeeded")
        } else {
            recipeAPILog.info("RecipeAPIIntegrationView: Skipping validation")
        }

        if APIKeyHelper.setRecipeAPIKey(cleanedKey) {
            recipeAPILog.info("RecipeAPIIntegrationView: Key saved to Keychain")
            statusMessage = skipValidation
                ? "Recipe API key saved (validation skipped)."
                : "Recipe API key validated and saved."
            recipeAPIKey = ""
            refreshStatus()
        } else {
            showError = true
            errorMessage = "Failed to save key to Keychain."
            recipeAPILog.error("RecipeAPIIntegrationView: Keychain save failed")
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
            recipeAPILog.info("RecipeAPIIntegrationView: Health check OK — \(health.status, privacy: .public)")
        } catch {
            showError = true
            errorMessage = error.localizedDescription
            recipeAPILog.error("RecipeAPIIntegrationView: Health check failed — \(error.localizedDescription, privacy: .public)")
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
            recipeAPILog.info("RecipeAPIIntegrationView: Dinner check OK — \(recipe.name, privacy: .public)")
        } catch {
            showError = true
            errorMessage = error.localizedDescription
            recipeAPILog.error("RecipeAPIIntegrationView: Dinner check failed — \(error.localizedDescription, privacy: .public)")
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
            recipeAPILog.info("RecipeAPIIntegrationView: Categories check OK — \(categories.count) categories")
        } catch {
            showError = true
            errorMessage = error.localizedDescription
            recipeAPILog.error("RecipeAPIIntegrationView: Categories check failed — \(error.localizedDescription, privacy: .public)")
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
