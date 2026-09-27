# Reczipes

AI-powered recipe extraction for iOS.

Reczipes converts photos of recipes into structured, searchable data using Apple Vision OCR and LLM reasoning.

## Key capabilities

• OCR extraction using Apple Vision  
• LLM-assisted interpretation of recipe structure  
• Allergen and FODMAP dietary analysis  
• Structured recipe data for storage and retrieval  
• Modern SwiftUI architecture with CloudKit synchronization

## GutSense — gut-health intelligence

GutSense is the gut-health intelligence layer developed alongside Reczipes. Its source is kept in a separate private repository; this section describes what it does, not how.

**What it does**

- **Independent dual-model analysis.** Two language models analyze each food or meal independently. Their results are then reconciled on-device, and the disagreements between them are shown rather than hidden.
- **Ingredient-level FODMAP assessment.** Each ingredient gets a low / moderate / high tier with estimated fructan, GOS, lactose, excess-fructose and polyol content.
- **Serving-aware scoring.** Values are scaled to the amount actually eaten, not a standard serving.
- **Personalized risk.** Results take the user's own profile into account: IBS subtype, elimination or reintroduction phase, known triggers and known safe foods.
- **Evidence tiers and citations.** Findings are graded as peer-reviewed, clinical or anecdotal. Users can add their own sources, and anecdotal evidence widens the uncertainty band.
- **Enzyme mitigation guidance.** Where relevant, it suggests enzyme options matched to the FODMAP groups involved.
- **What-if simulation.** Users can edit a meal's ingredient list and re-run the analysis to see how substitutions change the risk.
- **Recipe ingestion.** It can pull a recipe from a web page for analysis.
- **Built-in safety rules.** It uses probabilistic language and never gives a diagnosis. It never advises changing prescribed medication, and it flags Crohn's disease as distinct from IBS.

GutSense provides dietary information, not medical advice.

Access to the GutSense code is available on request.

## Architecture

Pipeline:

Image → OCR extraction → LLM interpretation → structured recipe model → user interface

Technologies:

- Swift / SwiftUI
- Apple Vision
- Claude API
- CloudKit

**Transform recipe card photos into structured, digital recipes using Claude's vision AI.**

Built with SwiftUI for iOS 17+ | Uses Claude Sonnet 4 | Integrates with your existing RecipeModel


---

## 🎯 What This Does

Take a photo of any recipe card, cookbook page, or handwritten recipe, and instantly get:

- ✅ **Structured recipe data** matching your existing `RecipeModel`
- ✅ **Multiple ingredient sections** (e.g., "For the dough", "For the filling")
- ✅ **Multiple instruction sections** with proper numbering
- ✅ **Metric conversions** when available
- ✅ **Recipe notes, tips, warnings, and timing**
- ✅ **Yield and serving information**
- ✅ **Source references and page numbers**

### Before & After

**Input:** Photo of a recipe card  
**Output:** Complete `RecipeModel` with all sections properly parsed

## 📦 What You Get

### Core Files (Production)
1. **ImagePreprocessor.swift** (3.9 KB) - Image enhancement for OCR
2. **ClaudeAPIClient.swift** (11 KB) - Claude API integration
3. **RecipeExtractorViewModel.swift** (2.3 KB) - State management
4. **RecipeExtractorView.swift** (11 KB) - Main user interface
5. **RecipeDetailView.swift** (12 KB) - Recipe display with formatting
6. **ImagePicker.swift** (1.5 KB) - Camera/photo library helper
7. **RecipeExtractorConfig.swift** (6.4 KB) - Configuration & security

### Documentation & Examples
8. **ExampleAppIntegration.swift** (13 KB) - Complete integration example
9. **RecipeExtractorTests.swift** (16 KB) - Testing utilities
10. **QUICK_START.md** - 5-minute setup guide
11. **IMPLEMENTATION_GUIDE.md** - Detailed implementation
12. **ARCHITECTURE.md** - System design documentation

**Total:** 94.4 KB of production-ready code + comprehensive docs

## 🚀 Quick Start

### 1. Requirements
- iOS 17.0+
- Xcode 15.0+
- Claude API key ([Get one here](https://console.anthropic.com))
- Your existing `RecipeModel.swift`

### 2. Installation (2 minutes)

```bash
# Add all .swift files to your Xcode project
# Drag them into your project navigator
```

### 3. Configuration (2 minutes)

**Update Info.plist:**
```xml
<key>NSCameraUsageDescription</key>
<string>Take photos of recipe cards</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Select recipe images from your library</string>
```

**Set up API key (choose one method):**

```swift
// Method 1: Keychain (Recommended)
KeychainManager.shared.save(key: "claudeAPIKey", value: "sk-ant-api03-...")

// Method 2: Environment Variable (Development)
// Xcode → Edit Scheme → Run → Environment Variables
// Add: CLAUDE_API_KEY = sk-ant-api03-...
```

### 4. Integration (1 minute)

```swift
import SwiftUI

@main
struct YourApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                RecipeListView()
                    .tabItem { Label("Recipes", systemImage: "book.fill") }
                
                if let apiKey = APIKeyHelper.getAPIKey() {
                    RecipeExtractorView(apiKey: apiKey)
                        .tabItem { Label("Extract", systemImage: "camera.fill") }
                }
            }
        }
    }
}
```

**That's it!** You now have Claude-powered recipe extraction.

## 📱 How It Works

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│ Take Photo  │────▶│ Preprocess   │────▶│ Send to     │────▶│ Get Recipe   │
│ or Select   │     │ (enhance)    │     │ Claude API  │     │ Data         │
└─────────────┘     └──────────────┘     └─────────────┘     └──────────────┘
```

### Image Preprocessing (Automatic)

Your old, faded recipe cards get enhanced:
- **Grayscale conversion** - Reduces color noise
- **Contrast boost (+50%)** - Makes text pop
- **Sharpening** - Clearer character recognition
- **Noise reduction** - Cleans up artifacts

Users can toggle preprocessing on/off and compare before/after.

### Claude Integration

The system sends your image to Claude with detailed instructions to:
1. Extract all text from the image
2. Identify ingredient sections
3. Parse measurements and units
4. Recognize instruction steps
5. Capture notes and variations
6. Output structured JSON matching your `RecipeModel`

### Your Recipe Model

The extracted data perfectly matches your existing structure:

```swift
RecipeModel(
    title: "Chocolate Chip Cookies",
    yield: "24 cookies",
    ingredientSections: [...],  // Multiple sections supported
    instructionSections: [...], // Numbered steps
    notes: [...]                // Tips, warnings, timing
)
```

## 💰 Cost

**~$0.02 per recipe extraction**

Based on Claude Sonnet 4 pricing:
- Input: ~2,000 tokens ($0.006)
- Output: ~1,000 tokens ($0.015)
- **Total: ~$0.021 per recipe**

Extract 100 recipes for ~$2.

## ✨ Features

### For Users
- 📸 **Camera & Photo Library** support
- 🎨 **Image Enhancement** toggle with preview
- ⚡ **Fast extraction** (15-30 seconds)
- ✅ **Comprehensive parsing** of complex recipes
- 🔄 **Error recovery** with retry options
- 📤 **Share functionality** for extracted recipes

### For Developers
- 🏗️ **MVVM architecture** with proper separation
- 🧪 **Comprehensive test suite** included
- 🔒 **Secure API key management** (Keychain + Environment)
- 📊 **Detailed error handling** with specific types
- ⚙️ **Highly configurable** (preprocessing levels, timeouts, etc.)
- 📝 **Well-documented** with inline comments

### Technical Highlights
- SwiftUI-native with `@Published` properties
- Async/await for modern concurrency
- Core Image for GPU-accelerated preprocessing
- Proper memory management
- No external dependencies (except Claude API)

## 🎨 Customization

### Adjust Preprocessing Intensity

```swift
// In RecipeExtractorConfig.swift
static let contrastLevel: Float = 1.8  // Default: 1.5
static let sharpnessLevel: Float = 0.9  // Default: 0.7
```

### Modify Extraction Prompt

```swift
// In ClaudeAPIClient.swift
let systemPrompt = """
You are an expert at extracting recipes...
[Add your custom instructions here]
"""
```

### Change UI Appearance

All views are standard SwiftUI - modify colors, layouts, and styling as needed.

## 🔒 Security

### API Key Protection
- ✅ **Never hardcoded** in source files
- ✅ **Keychain storage** with iOS encryption
- ✅ **Environment variables** for development
- ✅ **Not in version control** (.gitignore patterns)
- ✅ **Centralized access** through `APIKeyHelper`

### Best Practices Included
- Secure credential storage
- Rate limiting considerations
- Error message sanitization
- Debug mode controls

## 📊 Performance

### Benchmarks
- Image preprocessing: < 2 seconds
- API request: 10-30 seconds (network dependent)
- UI updates: Instant (reactive)
- Memory usage: ~20-35 MB peak

### Optimization Tips
- Enable preprocessing for old recipe cards
- Disable preprocessing for high-quality digital images
- Use lightweight preprocessing for color preservation
- Implement caching for frequently accessed recipes

## 🧪 Testing

### Included Test Suite

```swift
// Unit Tests
- ImagePreprocessor functionality
- RecipeModel parsing
- Keychain operations

// Integration Tests  
- API client request/response
- ViewModel state management

// Manual Testing Guide
- Checklist for all features
- Edge case scenarios
- Performance validation
```

### Test Your Integration

```swift
// Use provided test image generator
let testImage = TestImageGenerator.generateTestRecipeImage()

// Or use sample recipes
let sampleRecipe = RecipeModel.sampleRecipe
```

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| **QUICK_START.md** | 5-minute setup guide |
| **IMPLEMENTATION_GUIDE.md** | Detailed integration steps |
| **ARCHITECTURE.md** | System design and patterns |
| **ExampleAppIntegration.swift** | Complete working example |
| **RecipeExtractorTests.swift** | Testing utilities |

## 🆘 Troubleshooting

### Common Issues

**"No recipe could be extracted"**
- ✅ Enable image preprocessing
- ✅ Ensure text is legible in photo
- ✅ Try better lighting/focus

**"API Error (401)"**
- ✅ Check API key is correct
- ✅ Verify key starts with `sk-ant-`
- ✅ Confirm key is properly stored

**"API Error (429)"**
- ✅ Rate limit reached
- ✅ Wait a moment and retry
- ✅ Implement request throttling

**Preprocessing makes image worse**
- ✅ Use lightweight mode
- ✅ Disable for high-quality photos
- ✅ Adjust contrast/sharpness values

## 🚀 Built since the original extractor

The app has grown well beyond the extraction module described above:

1. **Persistence and sync**: SwiftData storage with CloudKit sync, backup and restore
2. **Recipe editing**: correct and refine every part of an extracted recipe
3. **Batch extraction**: extract many recipes at once from photos, iCloud Drive or saved web links, including in the background
4. **Dietary intelligence**: allergen detection, FODMAP analysis and substitutions, diabetic-friendly analysis and nutritional goals
5. **Search**: search across your recipe collection
6. **Recipe books**: organize recipes into books, with export and import
7. **Community sharing**: share recipes and books through CloudKit
8. **Cooking mode**: a step-by-step cooking view that keeps the screen awake
9. **App Clip**: lightweight extraction without installing the full app

## 📄 License

This implementation is provided as-is for use in your iOS applications.

## 🙏 Acknowledgments

- Built with **Claude Sonnet 4** by Anthropic
- Uses **Core Image** for preprocessing
- **SwiftUI** for modern iOS UI
- Compatible with your existing **RecipeModel** architecture

---

## Need Help?

1. Check **QUICK_START.md** for setup issues
2. Review **IMPLEMENTATION_GUIDE.md** for integration questions  
3. See **ARCHITECTURE.md** for design decisions
4. Test with **RecipeExtractorTests.swift**
5. Reference **ExampleAppIntegration.swift** for patterns

## Get Your API Key

Visit [console.anthropic.com](https://console.anthropic.com) to:
1. Create an Anthropic account
2. Generate an API key
3. Add credits to your account

---

**Ready to digitize your recipe collection?** 🍳

Start with the [Quick Start Guide](QUICK_START.md) →

Built with ❤️ using Claude Sonnet 4
