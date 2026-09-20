//
//  AppClipContentView.swift
//  Reczipes2Clip
//
//  Full App Clip UI and extraction logic.
//  Uses the real ClaudeAPIClient, ImagePreprocessor, and WebRecipeExtractor
//  — the same code paths the main app uses.
//
//  TARGET MEMBERSHIP: Reczipes2Clip only
//
//  ── Files that must be added to the Reczipes2Clip target in Xcode ──
//  (select each file → File Inspector → Target Membership → ✅ Reczipes2Clip)
//
//      ClaudeAPIClient.swift          – Claude API + response models + errors
//      ExtractionRetryManager.swift   – retry/backoff actor
//      ImagePreprocessor.swift        – OCR pre-processing
//      WebRecipeExtractor.swift       – HTML fetch + clean
//      KeychainManager.swift          – (not called here, but ClaudeAPIClient
//                                        is compiled alongside it)
//      RecipeExtractorConfig.swift    – shared constants
//      AppClipSharedModels.swift      – AppClipExtractedRecipeData (Codable)
//      AppClipLogging.swift           – lightweight logging shim (see below)
//  ────────────────────────────────────────────────────────────────────────

import SwiftUI
import PhotosUI

// MARK: - Content View

struct AppClipContentView: View {

    // Passed down from Reczipes2ClipApp; non-nil when the clip was invoked
    // with a ?url= parameter and we can skip straight to extraction.
    @Binding var invocationURL: String?

    // MARK: - State

    /// Current extraction phase drives the entire UI.
    @State private var phase: ClipPhase = .sourcePicker

    /// The recipe the user extracted (populated when phase == .success).
    @State private var extractedRecipe: AppClipExtractedRecipeData?

    /// URL typed / pasted by the user in the URL input screen.
    @State private var enteredURL: String = ""

    // MARK: - Body

    var body: some View {
        switch phase {
        case .sourcePicker:
            SourcePickerView(phase: $phase, enteredURL: $enteredURL)
                .onAppear {
                    // If we were invoked with a URL, jump straight to extraction.
                    if let url = invocationURL {
                        enteredURL = url
                        invocationURL = nil          // consume it
                        phase = .extractingURL(url)  // kick off extraction
                    }
                }

        case .urlInput:
            URLInputView(enteredURL: $enteredURL, phase: $phase)

        case .imagePicker(let source):
            ImagePickerView(source: source, phase: $phase)

        case .extractingImage(let imageData):
            ExtractionProgressView(phase: $phase,
                                   extractedRecipe: $extractedRecipe,
                                   source: .image(imageData))

        case .extractingURL(let url):
            ExtractionProgressView(phase: $phase,
                                   extractedRecipe: $extractedRecipe,
                                   source: .url(url))

        case .success:
            if let recipe = extractedRecipe {
                SuccessView(recipe: recipe, phase: $phase)
            }

        case .apiKeyRequired:
            APIKeyEntryView(phase: $phase)

        case .error(let message):
            ErrorView(message: message, phase: $phase)
        }
    }
}

// MARK: - Phase Enum

/// Drives the App Clip as a simple state machine — no nested sheets or
/// NavigationStacks needed, which keeps the binary small.
enum ClipPhase {
    case sourcePicker                   // initial screen: camera / photos / URL
    case urlInput                       // text field for typing a recipe URL
    case imagePicker(ImageSource)       // UIImagePicker is on screen
    case extractingImage(Data)          // Claude is processing an image
    case extractingURL(String)          // Claude is processing a URL
    case success                        // extraction finished; show recipe
    case apiKeyRequired                 // no key available; prompt the user
    case error(String)                  // something went wrong; show message
}

enum ImageSource {
    case camera
    case photoLibrary
}

/// What we hand to the extraction worker.
enum ExtractionInput {
    case image(Data)
    case url(String)
}

// MARK: - Source Picker

/// The landing screen: three big buttons.
struct SourcePickerView: View {
    @Binding var phase: ClipPhase
    @Binding var enteredURL: String

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // ── Hero ──
                    VStack(spacing: 12) {
                        ClipBadge()

                        Image(systemName: "book.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.accentColor)
                            .padding(20)
                            .background(Circle().fill(.white))
                            .shadow(radius: 8)

                        Text("Extract Recipe")
                            .font(.title.bold())
                        Text("Capture a recipe from a photo or website instantly")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 48)
                    .padding(.bottom, 36)

                    // ── Actions ──
                    VStack(spacing: 16) {
                        SourceButton(
                            title: "Take Photo",
                            subtitle: "Snap a recipe card or cookbook page",
                            icon: "camera.fill",
                            color: .blue
                        ) {
                            phase = .imagePicker(.camera)
                        }

                        SourceButton(
                            title: "From Photos",
                            subtitle: "Choose an existing photo",
                            icon: "photo.on.rectangle",
                            color: .green
                        ) {
                            phase = .imagePicker(.photoLibrary)
                        }

                        SourceButton(
                            title: "From URL",
                            subtitle: "Extract from a recipe website",
                            icon: "link",
                            color: .orange
                        ) {
                            enteredURL = ""
                            phase = .urlInput
                        }
                    }
                    .padding(.horizontal)

                    // ── Feature summary ──
                    VStack(alignment: .leading, spacing: 14) {
                        Text("What You Get")
                            .font(.headline)
                            .padding(.leading)

                        FeatureRow(icon: "wand.and.stars",
                                   title: "AI-Powered Extraction",
                                   detail: "Claude AI extracts ingredients, steps, and notes")
                        FeatureRow(icon: "list.bullet.rectangle",
                                   title: "Complete Details",
                                   detail: "Ingredients, instructions, timing, and tips")
                        FeatureRow(icon: "square.and.arrow.down",
                                   title: "Save to Full App",
                                   detail: "Keep your recipes forever with Reczipes")
                    }
                    .padding(.vertical, 28)

                    // ── Full-app CTA ──
                    FullAppCTA()
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - URL Input

struct URLInputView: View {
    @Binding var enteredURL: String
    @Binding var phase: ClipPhase

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Image(systemName: "link.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)

                Text("Recipe URL")
                    .font(.title2.bold())
                Text("Paste the address of a recipe webpage")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("https://example.com/recipe", text: $enteredURL)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal)

                Button {
                    guard let trimmed = enteredURL.trimmingCharacters(in: .whitespacesAndNewlines) as String?,
                          !trimmed.isEmpty else { return }
                    phase = .extractingURL(trimmed)
                } label: {
                    Text("Extract Recipe")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(enteredURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.gray : Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(enteredURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Enter URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { phase = .sourcePicker }
                }
            }
        }
    }
}

// MARK: - Image Picker Wrapper

/// Presents UIImagePickerController and converts the result to JPEG Data,
/// then transitions to the extraction phase.
struct ImagePickerView: UIViewControllerRepresentable {
    let source: ImageSource
    @Binding var phase: ClipPhase

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = source == .camera ? .camera : .photoLibrary
        picker.delegate   = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        init(_ parent: ImagePickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.phase = .error("Could not read the selected image.")
                return
            }
            // Compress to JPEG once here; the preprocessor / Claude client work on Data.
            guard let data = image.jpegData(compressionQuality: 0.9) else {
                parent.phase = .error("Could not compress the image.")
                return
            }
            parent.phase = .extractingImage(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.phase = .sourcePicker
        }
    }
}

// MARK: - Extraction Progress + Worker

/// Shows a spinner while Claude does its work.  The actual network call happens
/// in a Task launched on appear so the view stays lightweight.
struct ExtractionProgressView: View {
    @Binding var phase:            ClipPhase
    @Binding var extractedRecipe:  AppClipExtractedRecipeData?
    let source: ExtractionInput

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.8)
                    .tint(Color.accentColor)

                Text("Extracting Recipe…")
                    .font(.headline)
                Text("Claude AI is analyzing your recipe")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .background(.ultraThickMaterial)
            .cornerRadius(20)
            .shadow(radius: 12)
        }
        .task {
            await runExtraction()
        }
    }

    // MARK: - Extraction Logic

    private func runExtraction() async {
        // ── 1. Resolve API key ──
        guard let apiKey = AppClipAPIKeyHelper.getAPIKey() else {
            clipLog("No API key available; showing prompt", level: .warning)
            phase = .apiKeyRequired
            return
        }

        let client = ClaudeAPIClient(apiKey: apiKey)

        do {
            switch source {
            // ── 2a. Image extraction ──
            case .image(let imageData):
                clipLog("Starting image extraction (\(imageData.count) bytes)", level: .info)
                let clipData = try await client.extractRecipeAsClipData(from: imageData, usePreprocessing: true)
                extractedRecipe = clipData
                clipLog("Image extraction succeeded: \(clipData.title)", level: .info)

            // ── 2b. URL extraction ──
            case .url(let urlString):
                clipLog("Starting URL extraction: \(urlString)", level: .info)
                let webExtractor = WebRecipeExtractor()
                let html         = try await webExtractor.fetchWebContent(from: urlString)
                let cleaned      = webExtractor.cleanHTML(html)

                // Anthropic has token limits; truncate if needed.
                let content = cleaned.count > 50_000
                    ? String(cleaned.prefix(50_000))
                    : cleaned

                let clipData = try await client.extractRecipeAsClipData(from: content)
                extractedRecipe = clipData
                clipLog("URL extraction succeeded: \(clipData.title)", level: .info)
            }

            phase = .success

        } catch let error as ClaudeAPIError {
            clipLog("Claude error: \(error.errorDescription ?? "unknown")", level: .error)
            phase = .error(error.errorDescription ?? "Extraction failed.")

        } catch {
            clipLog("Extraction error: \(error.localizedDescription)", level: .error)
            phase = .error(error.localizedDescription)
        }
    }
}

// MARK: - Success View

/// Shows the extracted recipe and offers the "save to full app" CTA.
struct SuccessView: View {
    let recipe: AppClipExtractedRecipeData
    @Binding var phase: ClipPhase

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // ── Header ──
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.green)
                        Text("Recipe Extracted!")
                            .font(.title2.bold())
                        Text(recipe.title)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)

                    // ── Meta badges ──
                    HStack(spacing: 12) {
                        MetaBadge(icon: "person.2",     text: "\(recipe.servings) servings")
                        if let prep = recipe.prepTime  { MetaBadge(icon: "clock",        text: "Prep \(prep)")  }
                        if let cook = recipe.cookTime  { MetaBadge(icon: "flame",        text: "Cook \(cook)")  }
                    }
                    .padding(.horizontal)

                    // ── Ingredients ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredients").font(.headline)
                        ForEach(recipe.ingredients, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").foregroundStyle(Color.accentColor)
                                Text(item).font(.subheadline)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // ── Instructions ──
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Instructions").font(.headline)
                        ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { idx, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(idx + 1).")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 22, alignment: .trailing)
                                Text(step).font(.subheadline)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // ── Notes ──
                    if let notes = recipe.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes").font(.headline)
                            Text(notes).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    Divider().padding(.horizontal)

                    // ── Save CTA ──
                    VStack(spacing: 10) {
                        Text("Save this recipe forever")
                            .font(.headline)

                        Button { saveToMainAppAndOpen() } label: {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Get Reczipes & Save")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        }

                        Text("Plus: iCloud sync, recipe books, diabetic analysis, and more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { phase = .sourcePicker }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("New") { phase = .sourcePicker }
                }
            }
        }
    }

    // ── Persist to App Group + open App Store / universal link ──
    private func saveToMainAppAndOpen() {
        let sharedDefaults = UserDefaults(suiteName: "group.com.headydiscy.reczipes")
        if let encoded = try? JSONEncoder().encode(recipe) {
            sharedDefaults?.set(encoded, forKey: "appClipPendingRecipe")
            clipLog("Saved pending recipe to App Group UserDefaults", level: .info)
        }

        // Opening the universal link will either bring the main app to the
        // foreground (if installed) or land on the App Store page.
        // Replace with your actual domain once configured.
        if let url = URL(string: "https://yourdomain.com/app") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - API Key Entry

/// Shown when no key is found in either Keychain.  On save we write to both
/// the shared and clip-local Keychains, then loop back to the extraction phase
/// that originally needed it.
struct APIKeyEntryView: View {
    @Binding var phase: ClipPhase
    @State private var apiKey    = ""
    @State private var showError = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Image(systemName: "key.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)

                Text("API Key Required")
                    .font(.title2.bold())
                Text("Enter your Claude API key to extract recipes.\nYou can get a free key at anthropic.com")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude API Key")
                        .font(.subheadline.weight(.medium))
                    SecureField("sk-ant-…", text: $apiKey)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal)

                Button { saveKey() } label: {
                    Text("Save & Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(apiKey.isEmpty ? Color.gray : Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(apiKey.isEmpty)
                .padding(.horizontal)

                Button("Back") { phase = .sourcePicker }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                FullAppCTA()
                    .padding(.horizontal)
                    .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Invalid Key", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please enter a valid Claude API key starting with sk-ant-.")
            }
        }
    }

    private func saveKey() {
        guard apiKey.hasPrefix("sk-ant-") else {
            showError = true
            return
        }
        AppClipAPIKeyHelper.setAPIKey(apiKey)
        clipLog("API key saved via App Clip", level: .info)

        // Go back to source picker; the user will re-tap their action and
        // this time the key will be found.
        phase = .sourcePicker
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    @Binding var phase: ClipPhase

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer(minLength: 60)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)

                Text("Extraction Failed")
                    .font(.title2.bold())

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    Button { phase = .sourcePicker } label: {
                        Text("Try Again")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    FullAppCTA()
                        .padding(.horizontal)
                }

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Reusable Sub-Views

struct ClipBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "app.badge.checkmark")
                .font(.caption)
            Text("App Clip")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.15))
        .foregroundStyle(Color.accentColor)
        .cornerRadius(20)
    }
}

struct SourceButton: View {
    let title:    String
    let subtitle: String
    let icon:     String
    let color:    Color
    let action:   () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.12))
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct FeatureRow: View {
    let icon:   String
    let title:  String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}

struct MetaBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption)
            Text(text).font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(8)
    }
}

struct FullAppCTA: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Want More Features?").font(.headline)

            Button {
                if let url = URL(string: "https://yourdomain.com/app") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Get Reczipes").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }

            Text("Recipe collections • iCloud sync • Diabetic analysis")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}



