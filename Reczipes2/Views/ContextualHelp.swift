//
//  ContextualHelp.swift
//  Reczipes2
//
//  Contextual help system for all app features
//  Created on 12/18/25.
//

import SwiftUI

// MARK: - Help Content Model

/// Represents a help topic with title, description, and tips
struct HelpTopic: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let description: String
    let tips: [String]
    let relatedTopics: [String]
}

// MARK: - Help Content Database

struct AppHelp {
    
    // MARK: - Main Tabs
    
    static let recipesTab = HelpTopic(
        title: "Recipes Collection",
        icon: "book.fill",
        description: """
        Your personal recipe collection where you can view, organize, and filter all your saved recipes. Recipes appear with thumbnails if images have been assigned.
        """,
        tips: [
            "Tap any recipe to view its full details, ingredients, and instructions",
            "Swipe left on a recipe to delete it",
            "Use the allergen filter bar at the top to find safe recipes based on your dietary needs",
            "The recipe count shows how many recipes are in your collection",
            "Recipes with assigned images display thumbnails for easy visual identification"
        ],
        relatedTopics: ["Recipe Detail", "Allergen Filtering", "Image Assignment"]
    )
    
    static let extractTab = HelpTopic(
        title: "Recipe Extraction",
        icon: "camera.fill",
        description: """
        Extract recipes from photos using Claude AI. Take pictures of recipe cards, cookbook pages, or handwritten recipes and convert them into structured digital recipes instantly.
        """,
        tips: [
            "Tap 'Take Photo' to capture a recipe with your camera",
            "Tap 'Choose from Library' to select an existing photo",
            "Enable 'Image Preprocessing' for old or faded recipe cards",
            "Compare before/after preprocessing to see which works better",
            "Extraction typically takes 15-30 seconds",
            "The source image is automatically saved with your recipe",
            "Review the extracted recipe before saving to ensure accuracy"
        ],
        relatedTopics: ["Image Preprocessing", "Claude API", "Saving Recipes"]
    )
    
    static let settingsTab = HelpTopic(
        title: "Settings",
        icon: "gear",
        description: """
        Configure your app preferences, manage your Claude API key, and view legal information.
        """,
        tips: [
            "Set up your Claude API key to enable recipe extraction",
            "Toggle auto-extract to start extraction immediately after selecting an image",
            "Enable/disable image preprocessing as your default preference",
            "View the license agreement at any time",
            "Check your API key status (configured or not set)"
        ],
        relatedTopics: ["API Key Setup", "License Agreement"]
    )
    
    // MARK: - Recipe Features
    
    static let recipeDetail = HelpTopic(
        title: "Recipe Details",
        icon: "doc.text",
        description: """
        View complete recipe information including ingredients, instructions, notes, and allergen analysis. Edit saved recipes or save extracted recipes to your collection.
        """,
        tips: [
            "Scroll through sections: Image, Ingredients, Instructions, Notes, and Source",
            "Tap 'Edit' (pencil icon) to modify any saved recipe",
            "Tap 'Save' to add an extracted recipe to your collection",
            "Export ingredients to Apple Reminders for grocery shopping",
            "View allergen analysis if you have an active dietary profile",
            "Print or share recipes using the share button",
            "Recipe images are automatically saved from extraction"
        ],
        relatedTopics: ["Recipe Editing", "Allergen Analysis", "Export to Reminders"]
    )
    
    static let recipeEditing = HelpTopic(
        title: "Recipe Editing",
        icon: "pencil",
        description: """
        Edit all aspects of your saved recipes including title, ingredients, instructions, and notes. Add new sections or remove unwanted items.
        """,
        tips: [
            "The title is required - all other fields are optional",
            "Tap 'Add Ingredient Section' to create organized ingredient groups",
            "Tap 'Add Instruction Section' to separate cooking steps",
            "Tap 'Edit' in section headers to reorder or delete sections",
            "Changes are saved when you tap 'Save' in the toolbar",
            "You'll be warned if you try to cancel with unsaved changes",
            "All saved recipes can be edited, regardless of how they were created"
        ],
        relatedTopics: ["Recipe Detail", "Ingredient Sections", "Instruction Sections"]
    )
    
    // MARK: - Image Features
    
    static let imageAssignment = HelpTopic(
        title: "Recipe Images",
        icon: "photo.on.rectangle",
        description: """
        Manage photos for your recipes. Images extracted with recipes are automatically assigned, but you can change or add images anytime.
        """,
        tips: [
            "Green checkmarks indicate recipes that already have assigned images",
            "Tap the pencil icon to change a recipe's image",
            "Select a new photo from your photo library",
            "Images are stored in your app's Documents folder",
            "Compressed JPEG format (80% quality) balances quality and storage",
            "Thumbnails appear throughout the app for visual identification",
            "Images from recipe extraction are automatically saved and assigned"
        ],
        relatedTopics: ["Recipe Extraction", "Image Storage"]
    )
    
    static let imagePreprocessing = HelpTopic(
        title: "Image Preprocessing",
        icon: "wand.and.stars",
        description: """
        Enhance recipe photos before extraction to improve text recognition. Especially useful for old, faded, or low-contrast recipe cards.
        """,
        tips: [
            "Toggle 'Use Image Preprocessing' to enhance your photo",
            "Tap 'Compare Original vs Processed' to see the difference",
            "Preprocessing converts to grayscale and boosts contrast",
            "Text becomes clearer and easier for AI to read",
            "Best for: old recipe cards, faded text, handwritten recipes",
            "May not help for: already clear digital photos, color-dependent recipes",
            "Try extraction both with and without preprocessing to see which works better"
        ],
        relatedTopics: ["Recipe Extraction", "Claude API"]
    )
    
    static let batchImageExtraction_image = HelpTopic(
        title: "Batch Image Extraction",
        icon: "photo.stack.fill",
        description: """
        Extract multiple recipes at once from images in your Photos library or Files app. Perfect for digitizing recipe collections quickly - process up to 10 images at a time with optional cropping and background extraction.
        """,
        tips: [
            "Tap 'Batch Extract Images' from the Extract tab to get started",
            "Select multiple recipe photos from your Photos library or Files app",
            "Toggle 'Crop each image' ON to adjust each photo individually, or OFF for fastest processing",
            "With cropping OFF, extraction continues in the background - you can close the screen and do other things!",
            "Recipes appear in the 'Recipes Mine' tab in real-time as they're extracted",
            "The app processes images sequentially with progress updates",
            "Use Pause to temporarily stop, Resume to continue, or Stop to cancel the entire batch",
            "Each extraction takes 10-30 seconds per image depending on complexity",
            "All successfully extracted recipes are automatically saved to your collection",
            "Review the error log if any images fail - you can retry them individually later",
            "Start with 3-5 images to learn the workflow before processing larger batches",
            "Best results on WiFi to avoid data charges and ensure stable connection"
        ],
        relatedTopics: ["Recipe Extraction", "Background Extraction", "Image Preprocessing", "Claude API", "Image Assignment"]
    )
    
    static let backgroundExtraction = HelpTopic(
        title: "Background Extraction",
        icon: "arrow.triangle.2.circlepath",
        description: """
        When cropping is disabled, batch extraction continues in the background even if you close the extraction screen. Recipes appear in your collection as they're extracted, letting you use the app while extraction runs.
        """,
        tips: [
            "Background extraction only works when 'Crop each image' is turned OFF",
            "Look for the purple banner 'Extraction will continue if you close this screen'",
            "Tap 'Close' during extraction to see three options: Continue in Background, Stop and Close, or Cancel",
            "Choose 'Continue in Background' to keep extraction running while you navigate away",
            "Extracted recipes appear in 'Recipes Mine' tab in real-time - no need to wait",
            "You can pause the extraction, close the screen, and resume later by reopening the batch extractor",
            "Background extraction stops if you force-quit the app",
            "With cropping ON, extraction requires you to stay on the screen for manual adjustments",
            "Perfect for extracting 10-20 recipes while browsing your existing collection",
            "Check the diagnostic log to monitor progress even when the extraction screen is closed"
        ],
        relatedTopics: ["Batch Image Extraction", "Recipe Extraction", "Pause and Resume", "Real-Time Updates"]
    )
    
    static let pauseAndResume = HelpTopic(
        title: "Pause and Resume Extraction",
        icon: "pause.circle.fill",
        description: """
        Control batch extraction with pause and resume functionality. Take a break during long extraction sessions or pause to review extracted recipes before continuing.
        """,
        tips: [
            "Tap 'Pause' during extraction to temporarily stop processing",
            "While paused, the current image finishes extracting, then extraction stops",
            "Tap 'Resume' to continue from where you left off",
            "Paused state persists even if you close the extraction screen (background mode)",
            "Use 'Stop' to cancel the entire batch and exit extraction",
            "Pause is useful for checking recipes in the 'Mine' tab during extraction",
            "Paused extractions remain in memory until resumed or stopped",
            "Progress and extracted recipes are preserved when paused"
        ],
        relatedTopics: ["Batch Image Extraction", "Background Extraction", "Extraction Controls"]
    )
    
    static let realTimeUpdates = HelpTopic(
        title: "Real-Time Recipe Updates",
        icon: "arrow.clockwise.circle.fill",
        description: """
        Extracted recipes appear in your 'Recipes Mine' tab immediately as they're processed. No need to wait for the entire batch to complete before viewing your new recipes.
        """,
        tips: [
            "Each recipe is saved to your collection as soon as it's successfully extracted",
            "Navigate to 'Recipes Mine' to see new recipes appearing in real-time",
            "Recipes include all extracted details: ingredients, instructions, notes, and images",
            "You can start using newly extracted recipes immediately - view, edit, or cook with them",
            "Failed extractions are logged but don't create incomplete recipes",
            "The extraction screen shows a count of successful and failed extractions",
            "All images are automatically assigned to their extracted recipes",
            "Perfect for starting to organize recipes while the rest are still being extracted"
        ],
        relatedTopics: ["Batch Image Extraction", "Background Extraction", "Recipe Collection"]
    )
    
    // MARK: - Allergen Features
    
    static let allergenProfiles = HelpTopic(
        title: "Allergen Profiles",
        icon: "heart.text.square",
        description: """
        Create profiles to track your food allergies, sensitivities, and intolerances. The app automatically analyzes recipes to show which ones are safe for you.
        """,
        tips: [
            "Tap '+' to create a new allergen profile",
            "Add sensitivities from 'Big 9 Allergens' or 'Intolerances' tabs",
            "Set severity levels: Mild, Moderate, or Severe",
            "Only one profile can be active at a time",
            "Toggle 'Active Profile' ON to enable automatic recipe analysis",
            "Add optional notes about your reactions or restrictions",
            "Create multiple profiles for different family members or scenarios"
        ],
        relatedTopics: ["Allergen Analysis", "Food Sensitivities", "FODMAP Analysis"]
    )
    
    static let allergenAnalysis = HelpTopic(
        title: "Allergen Analysis",
        icon: "checkmark.shield",
        description: """
        Automatic safety scoring for recipes based on your allergen profile. See which ingredients contain allergens and get risk level assessments.
        """,
        tips: [
            "Enable filtering in the recipe list to see safety badges",
            "Green checkmark (✅) = Safe - no detected allergens",
            "Yellow/Orange/Red warnings (⚠️) = allergens detected",
            "Tap 'View Detailed Analysis' to see which ingredients triggered detection",
            "Higher severity levels (Severe vs Mild) increase the risk score",
            "The system checks 16 different allergens and intolerances",
            "Toggle 'Safe Only' to show only recipes without detected allergens"
        ],
        relatedTopics: ["Allergen Profiles", "Food Sensitivities", "Recipe Filtering"]
    )
    
    static let fodmapAnalysis = HelpTopic(
        title: "FODMAP Analysis",
        icon: "heart.text.square.fill",
        description: """
        Specialized analysis for Low FODMAP diets based on Monash University research. Identifies high FODMAP ingredients and suggests alternatives.
        """,
        tips: [
            "Add 'FODMAPs' to your allergen profile to enable this analysis",
            "The system checks all four FODMAP categories: Oligosaccharides, Disaccharides, Monosaccharides, and Polyols",
            "Many foods are low FODMAP in small portions but high in large amounts",
            "Look for serving size guidance in detailed analysis",
            "Get suggestions for low FODMAP alternatives (e.g., garlic-infused oil instead of garlic)",
            "Based on current Monash University FODMAP research",
            "Combine with Claude AI analysis for detecting hidden FODMAPs"
        ],
        relatedTopics: ["Allergen Analysis", "Food Intolerances", "Recipe Modifications"]
    )
    
    static let allergenFiltering = HelpTopic(
        title: "Allergen Filtering",
        icon: "line.3.horizontal.decrease.circle",
        description: """
        Filter and sort your recipe collection by allergen safety. Find recipes that are safe for your dietary needs quickly.
        """,
        tips: [
            "Tap the filter bar at the top of the recipe list to access filtering",
            "Enable the filter toggle to activate allergen-based sorting",
            "Tap 'Safe Only' to show only recipes with no detected allergens",
            "Without 'Safe Only', recipes are sorted by safety score (safest first)",
            "Tap your profile name in the filter bar to manage allergen profiles",
            "Allergen badges appear on each recipe showing its safety level",
            "An active profile is required for filtering to work"
        ],
        relatedTopics: ["Allergen Profiles", "Allergen Analysis", "Recipe Collection"]
    )
    
    // MARK: - API & Setup Features
    
    static let apiKeySetup = HelpTopic(
        title: "Claude API Key Setup",
        icon: "key.fill",
        description: """
        Configure your Anthropic Claude API key to enable recipe extraction from images. Your key is stored securely in the iOS Keychain.
        """,
        tips: [
            "Visit console.anthropic.com to create an account and get an API key",
            "Your API key starts with 'sk-ant-api03-'",
            "Keys are stored securely in the iOS Keychain, never in plain text",
            "Recipe extraction costs approximately $0.02 per recipe",
            "You can change or remove your API key anytime in Settings",
            "The app checks your key status and shows green checkmark when configured",
            "API keys are private - never share them publicly"
        ],
        relatedTopics: ["Recipe Extraction", "Settings", "Security"]
    )
    
    static let claudeAPI = HelpTopic(
        title: "Claude AI Integration",
        icon: "sparkles",
        description: """
        The app uses Claude Sonnet 4, Anthropic's advanced AI model, to extract recipes from images with high accuracy and comprehensive detail parsing.
        """,
        tips: [
            "Claude can read printed text, handwritten recipes, and even complex layouts",
            "Extraction includes: ingredients with quantities, step-by-step instructions, notes, yield, and source references",
            "The AI organizes multi-section recipes (e.g., 'For the dough', 'For the filling')",
            "Metric conversions are included when available",
            "Processing typically takes 15-30 seconds depending on image complexity",
            "Enhanced allergen detection can identify hidden allergens in ingredients",
            "Cost is approximately $0.02 per recipe extraction"
        ],
        relatedTopics: ["Recipe Extraction", "API Key Setup", "Image Preprocessing"]
    )
    
    // MARK: - Data & Storage
    
    static let dataStorage = HelpTopic(
        title: "Data Storage",
        icon: "internaldrive",
        description: """
        All your recipes, images, and preferences are stored locally on your device using SwiftData and the iOS file system.
        """,
        tips: [
            "Recipes are stored in SwiftData for fast, efficient access",
            "Recipe images are saved as JPEG files in your app's Documents folder",
            "Image assignments link recipes to their photos",
            "Allergen profiles are stored in SwiftData",
            "Your API key is stored securely in the iOS Keychain",
            "All data is private and stored only on your device",
            "No cloud sync (can be added in future versions)"
        ],
        relatedTopics: ["Recipe Collection", "Image Assignment", "Privacy"]
    )
    
    static let exportToReminders = HelpTopic(
        title: "Export to Reminders",
        icon: "checklist",
        description: """
        Export recipe ingredients directly to Apple Reminders as a shopping list. Perfect for grocery shopping with your recipes.
        """,
        tips: [
            "Tap the export button in recipe detail view",
            "Ingredients are organized by section if your recipe has multiple sections",
            "Each ingredient becomes a checkable reminder item",
            "You'll need to grant Reminders access the first time",
            "Lists are created with the recipe title as the list name",
            "Check off items as you shop",
            "You can edit the reminder list in the Reminders app"
        ],
        relatedTopics: ["Recipe Detail", "Ingredients"]
    )
    
    // MARK: - Additional Features
    
    static let licenseAgreement = HelpTopic(
        title: "License Agreement",
        icon: "doc.text",
        description: """
        The app's terms of use and license agreement. You accepted this when first launching the app.
        """,
        tips: [
            "View the full license text anytime from Settings",
            "The acceptance date is recorded and displayed in Settings",
            "The app follows standard iOS privacy practices",
            "All data is stored locally on your device",
            "No personal data is collected or transmitted",
            "The license covers app usage and Claude API integration"
        ],
        relatedTopics: ["Settings", "Privacy", "Legal"]
    )
    
    static let launchScreen = HelpTopic(
        title: "Launch Screen",
        icon: "sparkles",
        description: """
        The animated launch screen that appears when you first open the app. Shows the app logo and name with a smooth animation.
        """,
        tips: [
            "The launch screen appears only once per app session",
            "It won't show again when returning from background",
            "Provides a polished first impression",
            "Automatically dismisses after animation completes"
        ],
        relatedTopics: ["App Launch"]
    )
    
    // MARK: - Cooking Mode Features
    
    static let cookingMode = HelpTopic(
        title: "Cooking Mode",
        icon: "flame.fill",
        description: """
        A specialized hands-free cooking interface that lets you view up to two recipes side-by-side while you cook. Perfect for following multiple recipes simultaneously or referencing a recipe while keeping your device awake.
        """,
        tips: [
            "View one or two recipes at the same time",
            "On iPad and Mac, recipes appear side-by-side for easy comparison",
            "On iPhone, swipe between recipes using the page dots at the bottom",
            "Your cooking session is automatically saved and restored when you return",
            "Enable 'Keep Awake' to prevent your screen from going to sleep while cooking",
            "Perfect for complex recipes that require timing multiple dishes",
            "Tap the swap icon to change recipes without losing your other selections"
        ],
        relatedTopics: ["Dual Recipe View", "Keep Awake Mode", "Recipe Panel Controls"]
    )
    
    static let dualRecipeView = HelpTopic(
        title: "Dual Recipe View",
        icon: "rectangle.split.2x1",
        description: """
        View two recipes simultaneously in cooking mode. Compare recipes, follow main dish and side dish together, or reference one recipe while cooking another.
        """,
        tips: [
            "On iPad and Mac, both recipes are visible at once with a divider between them",
            "On iPhone, swipe left or right to switch between your two recipes",
            "Page indicator dots show which recipe you're currently viewing (iPhone only)",
            "Each recipe slot can be independently filled, changed, or cleared",
            "Empty slots show a '+' button - tap to select a recipe",
            "Great for cooking a main dish and side dish that need different timing",
            "Perfect for comparing similar recipes or ingredient lists"
        ],
        relatedTopics: ["Cooking Mode", "Recipe Panel Controls", "Session Persistence"]
    )
    
    static let keepAwakeMode = HelpTopic(
        title: "Keep Awake Mode",
        icon: "eye.fill",
        description: """
        Prevent your device screen from sleeping while you're cooking. Essential for keeping recipes visible without constantly touching the screen with messy hands.
        """,
        tips: [
            "Tap the eye icon in the top-right corner to toggle Keep Awake on/off",
            "Eye icon = Keep Awake is ON, screen won't sleep",
            "Eye with slash icon = Keep Awake is OFF, normal sleep behavior",
            "Your preference is saved with your cooking session",
            "Works even when your device would normally sleep after 30 seconds or 1 minute",
            "Turn it off when you're done cooking to save battery",
            "Automatically disabled when you exit cooking mode"
        ],
        relatedTopics: ["Cooking Mode", "Battery Management", "Session Persistence"]
    )
    
    static let recipePanelControls = HelpTopic(
        title: "Recipe Panel Controls",
        icon: "slider.horizontal.3",
        description: """
        Manage your active recipes in cooking mode with intuitive controls. Swap recipes, clear slots, or select new recipes without leaving cooking mode.
        """,
        tips: [
            "Tap the circular swap icon (↻) in the top-right to choose a different recipe",
            "Tap the 'X' icon to clear a recipe from its slot",
            "Controls appear as floating buttons over each recipe",
            "Both recipe panels have independent controls",
            "Clearing a recipe returns that panel to the empty '+' state",
            "Swapping recipes opens the recipe picker filtered to your collection",
            "Recipe picker remembers the current recipe to help you avoid duplicates"
        ],
        relatedTopics: ["Cooking Mode", "Recipe Selection", "Session Management"]
    )
    
    static let recipeSelection = HelpTopic(
        title: "Recipe Selection in Cooking Mode",
        icon: "list.bullet.rectangle",
        description: """
        Choose recipes for your cooking session from your entire recipe collection. The recipe picker makes it easy to find and select the recipes you need.
        """,
        tips: [
            "Tap the '+' button on an empty slot to open the recipe picker",
            "Tap the swap icon (↻) on a filled slot to choose a different recipe",
            "Search by recipe title to quickly find specific recipes",
            "Scroll through your collection to browse available recipes",
            "The current recipe in that slot is highlighted (if swapping)",
            "Tap any recipe to select it for cooking",
            "The sheet automatically dismisses when you select a recipe"
        ],
        relatedTopics: ["Cooking Mode", "Recipe Panel Controls", "Session Persistence"]
    )
    
    static let sessionPersistence = HelpTopic(
        title: "Session Persistence",
        icon: "arrow.clockwise",
        description: """
        Your cooking session is automatically saved, so you can leave and return without losing your selected recipes or settings.
        """,
        tips: [
            "Selected recipes are automatically saved when you make changes",
            "Keep Awake preference is remembered across sessions",
            "Return to cooking mode to find your recipes exactly as you left them",
            "Session persists even if you force-quit the app",
            "On iPhone, your current page (recipe 1 or 2) is saved",
            "Works across app launches - start cooking, check another tab, come back",
            "Only one cooking session is active at a time (most recent)"
        ],
        relatedTopics: ["Cooking Mode", "Keep Awake Mode", "Data Storage"]
    )
    
    static let cookingModeLayouts = HelpTopic(
        title: "Cooking Mode Layouts",
        icon: "rectangle.on.rectangle",
        description: """
        Cooking mode adapts to your device with optimized layouts for iPhone, iPad, and Mac. Each layout is designed for the best cooking experience on that device.
        """,
        tips: [
            "iPad & Mac: Side-by-side layout with vertical divider between recipes",
            "iPhone Portrait: Swipeable pages with indicator dots to switch recipes",
            "iPhone Landscape: Swipeable pages optimized for horizontal viewing",
            "The layout automatically adjusts when you rotate your device",
            "Controls remain in consistent positions regardless of layout",
            "Both layouts provide full access to all recipe details",
            "No functionality is lost on smaller screens - just a different presentation"
        ],
        relatedTopics: ["Cooking Mode", "Dual Recipe View", "Device Optimization"]
    )
    
    static let emptyRecipeSlots = HelpTopic(
        title: "Empty Recipe Slots",
        icon: "plus.circle",
        description: """
        When a cooking slot is empty, you'll see a friendly prompt to select a recipe. Each slot can be filled independently.
        """,
        tips: [
            "Empty slots show a large '+' icon with 'Select a Recipe' text",
            "Tap anywhere on the empty slot to open recipe picker",
            "You can have one or two recipes active at the same time",
            "Having only one recipe selected is perfectly fine",
            "Use both slots when you need to reference multiple recipes",
            "Clearing a filled recipe returns it to the empty state",
            "Empty slots don't interfere with Keep Awake mode functionality"
        ],
        relatedTopics: ["Recipe Selection", "Cooking Mode", "Recipe Panel Controls"]
    )
    
    // MARK: - CloudKit & Sync Features
    
    static let cloudKitSync = HelpTopic(
        title: "iCloud Sync",
        icon: "icloud.fill",
        description: """
        Your recipes automatically sync across all your devices using iCloud. Create a recipe on your iPhone and it appears on your iPad instantly.
        """,
        tips: [
            "Sign in with the same Apple ID on all devices to enable sync",
            "Ensure iCloud Drive is enabled in Settings → [Your Name] → iCloud",
            "Initial sync can take 5-10 minutes after first launch",
            "Sync works faster when on Wi-Fi and app is in foreground",
            "All recipe data is encrypted end-to-end for privacy",
            "Check sync status in Settings → iCloud Sync",
            "No manual sync needed - it happens automatically"
        ],
        relatedTopics: ["CloudKit Setup", "Sync Troubleshooting", "Container Details"]
    )
    
    static let cloudKitSetup = HelpTopic(
        title: "CloudKit Setup",
        icon: "gearshape.icloud",
        description: """
        CloudKit enables your recipes to sync across all your Apple devices. Setup is automatic, but you need to be signed into iCloud.
        """,
        tips: [
            "Open Settings app on your device",
            "Sign in with your Apple ID at the top",
            "Go to iCloud and enable iCloud Drive",
            "Restart the Reczipes app after enabling iCloud",
            "Check Settings → iCloud Sync in the app to verify status",
            "Green checkmark means CloudKit is working properly",
            "Orange or red warnings indicate setup issues that need attention"
        ],
        relatedTopics: ["iCloud Sync", "Sync Troubleshooting", "CloudKit Diagnostics"]
    )
    
    static let cloudKitDiagnostics = HelpTopic(
        title: "CloudKit Diagnostics",
        icon: "stethoscope",
        description: """
        Built-in diagnostic tools help you troubleshoot sync issues and verify your CloudKit configuration. Access detailed system information and test connectivity.
        """,
        tips: [
            "Go to Settings → CloudKit Diagnostics to run tests",
            "Tap 'Run Full Diagnostics' to check all sync components",
            "Green checkmarks mean everything is working",
            "Red X marks indicate problems that need fixing",
            "Compare diagnostics on both devices if sync isn't working",
            "Use 'Copy Diagnostics to Clipboard' to save results",
            "Force Sync Check can help trigger delayed sync operations"
        ],
        relatedTopics: ["iCloud Sync", "Sync Troubleshooting", "Container Details"]
    )
    
    static let syncTroubleshooting = HelpTopic(
        title: "Sync Troubleshooting",
        icon: "wrench.and.screwdriver",
        description: """
        If recipes aren't syncing between devices, this guide helps you identify and fix common issues. Most problems are quick to resolve.
        """,
        tips: [
            "Verify you're signed into the SAME Apple ID on both devices",
            "Check that iCloud Drive is enabled on both devices",
            "Wait 5-10 minutes for initial sync (it's not instant)",
            "Ensure both devices have good network connectivity",
            "Open Settings → CloudKit Diagnostics and compare results",
            "Look for 'CloudKit sync enabled' in app console logs",
            "If one device shows 'local-only', CloudKit isn't working on that device"
        ],
        relatedTopics: ["CloudKit Diagnostics", "iCloud Sync", "Container Details"]
    )
    
    static let containerDetails = HelpTopic(
        title: "Container Details",
        icon: "cylinder.split.1x2",
        description: """
        View detailed information about your app's persistent storage container and CloudKit configuration. Useful for verifying setup and debugging.
        """,
        tips: [
            "Access via Settings → Container Details",
            "Check that 'CloudKit Enabled' shows 'Yes'",
            "Verify Container ID matches: iCloud.com.headydiscy.reczipes",
            "Compare configurations on both devices - they should match",
            "Recipe count shows how many recipes are stored locally",
            "Use 'Copy Configuration' to save technical details",
            "Storage location shows where your data is physically stored"
        ],
        relatedTopics: ["CloudKit Diagnostics", "iCloud Sync", "Data Storage"]
    )
    
    static let batchImageExtraction = HelpTopic(
        title: "Batch Image Extraction",
        icon: "photo.stack.fill",
        description: """
        Extract multiple recipes at once from images in your Photos library. Perfect for digitizing recipe collections quickly - process up to 10 images at a time with optional cropping.
        """,
        tips: [
            "Tap 'Batch Extract Images' from the Extract tab",
            "Select multiple recipe photos from your library",
            "Toggle 'Crop each image' ON to adjust each photo individually, or OFF for fastest processing",
            "The app processes images in batches of 10 with progress updates",
            "You can pause, resume, or stop extraction at any time",
            "Each extraction takes 10-30 seconds per image",
            "All successfully extracted recipes are automatically saved",
            "Review the error log if any images fail to extract",
            "Start with 3-5 images to learn the workflow before processing larger batches"
        ],
        relatedTopics: ["Recipe Extraction", "Image Preprocessing", "Claude API", "Photos Library"]
    )
    
    // MARK: - Category Organization
    
    static let allTopics: [String: HelpTopic] = [
        // Main Tabs
        "recipesTab": recipesTab,
        "extractTab": extractTab,
        "settingsTab": settingsTab,
        
        // Recipe Features
        "recipeDetail": recipeDetail,
        "recipeEditing": recipeEditing,
        
        // Image Features
        "imageAssignment": imageAssignment,
        "imagePreprocessing": imagePreprocessing,
        "batchImageExtraction": batchImageExtraction_image,
        "backgroundExtraction": backgroundExtraction,
        "pauseAndResume": pauseAndResume,
        "realTimeUpdates": realTimeUpdates,
        
        // Allergen Features
        "allergenProfiles": allergenProfiles,
        "allergenAnalysis": allergenAnalysis,
        "fodmapAnalysis": fodmapAnalysis,
        "allergenFiltering": allergenFiltering,
        
        // API & Setup
        "apiKeySetup": apiKeySetup,
        "claudeAPI": claudeAPI,
        
        // Data & Storage
        "dataStorage": dataStorage,
        "exportToReminders": exportToReminders,
        
        // CloudKit & Sync
        "cloudKitSync": cloudKitSync,
        "cloudKitSetup": cloudKitSetup,
        "cloudKitDiagnostics": cloudKitDiagnostics,
        "syncTroubleshooting": syncTroubleshooting,
        "containerDetails": containerDetails,
        
        // Cooking Mode
        "cookingMode": cookingMode,
        "dualRecipeView": dualRecipeView,
        "keepAwakeMode": keepAwakeMode,
        "recipePanelControls": recipePanelControls,
        "recipeSelection": recipeSelection,
        "sessionPersistence": sessionPersistence,
        "cookingModeLayouts": cookingModeLayouts,
        "emptyRecipeSlots": emptyRecipeSlots,
        
        // Additional
        "licenseAgreement": licenseAgreement,
        "launchScreen": launchScreen
    ]
    
    static func topic(for key: String) -> HelpTopic? {
        allTopics[key]
    }
    
    // Organized by category for help browser
    static let categories: [(name: String, icon: String, topics: [HelpTopic])] = [
        ("Getting Started", "figure.walk", [
            launchScreen,
            licenseAgreement,
            apiKeySetup
        ]),
        ("Main Features", "star.fill", [
            recipesTab,
            extractTab,
            recipeDetail,
            recipeEditing
        ]),
        ("Cooking Mode", "flame.fill", [
            cookingMode,
            dualRecipeView,
            keepAwakeMode,
            recipePanelControls,
            recipeSelection,
            sessionPersistence,
            cookingModeLayouts,
            emptyRecipeSlots
        ]),
        ("Images", "photo.fill", [
            imageAssignment,
            imagePreprocessing
        ]),
        ("Extraction Features", "camera.fill", [
            extractTab,
            batchImageExtraction_image,
            backgroundExtraction,
            pauseAndResume,
            realTimeUpdates,
            imagePreprocessing
        ]),
        ("Allergen & Dietary", "heart.fill", [
            allergenProfiles,
            allergenAnalysis,
            fodmapAnalysis,
            allergenFiltering
        ]),
        ("CloudKit & Sync", "icloud.fill", [
            cloudKitSync,
            cloudKitSetup,
            cloudKitDiagnostics,
            syncTroubleshooting,
            containerDetails
        ]),
        ("Advanced", "gear", [
            claudeAPI,
            exportToReminders,
            dataStorage,
            settingsTab
        ])
    ]
}

// MARK: - Help Views

/// Quick help button that can be added to any view
struct HelpButton: View {
    let topicKey: String
    @State private var showingHelp = false
    
    var body: some View {
        Button {
            showingHelp = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.title3)
        }
        .sheet(isPresented: $showingHelp) {
            if let topic = AppHelp.topic(for: topicKey) {
                HelpDetailView(topic: topic)
            }
        }
    }
}

/// Full help detail view
struct HelpDetailView: View {
    let topic: HelpTopic
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header with icon
                    HStack {
                        Image(systemName: topic.icon)
                            .font(.system(size: 50))
                            .foregroundStyle(.tint)
                        
                        Spacer()
                    }
                    .padding(.bottom, 8)
                    
                    // Description
                    Text(topic.description)
                        .font(.body)
                        .foregroundStyle(.primary)
                    
                    Divider()
                    
                    // Tips Section
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Tips & Tricks", systemImage: "lightbulb.fill")
                            .font(.headline)
                            .foregroundStyle(Color.appWarning)
                        
                        ForEach(Array(topic.tips.enumerated()), id: \.offset) { index, tip in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .trailing)
                                
                                Text(tip)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    
                    // Related Topics
                    if !topic.relatedTopics.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Related Topics", systemImage: "link")
                                .font(.headline)
                                .foregroundStyle(Color.appInfo)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(topic.relatedTopics, id: \.self) { related in
                                    Text(related)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundStyle(Color.appInfo)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(topic.title)
            .platformNavigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Browse all help topics
struct HelpBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    var filteredCategories: [(name: String, icon: String, topics: [HelpTopic])] {
        guard !searchText.isEmpty else {
            return AppHelp.categories
        }
        
        let lowercasedSearch = searchText.lowercased()
        return AppHelp.categories.compactMap { category in
            let filteredTopics = category.topics.filter { topic in
                topic.title.lowercased().contains(lowercasedSearch) ||
                topic.description.lowercased().contains(lowercasedSearch)
            }
            
            if filteredTopics.isEmpty {
                return nil
            } else {
                return (category.name, category.icon, filteredTopics)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredCategories, id: \.name) { category in
                    Section {
                        ForEach(category.topics) { topic in
                            NavigationLink {
                                HelpDetailView(topic: topic)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(topic.title)
                                            .font(.headline)
                                        
                                        Text(topic.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                } icon: {
                                    Image(systemName: topic.icon)
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    } header: {
                        Label(category.name, systemImage: category.icon)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search help topics")
            .navigationTitle("Help")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Helper Views

/// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        
        for (index, subview) in subviews.enumerated() {
            subview.place(at: result.positions[index], proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    // Start new line
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                x += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

// MARK: - View Extensions for Help

extension View {
    /// Add a help button to any view's toolbar
    func helpButton(for topicKey: String) -> some View {
        toolbar {
            ToolbarItem(placement: .platformNavBarTrailing) {
                HelpButton(topicKey: topicKey)
            }
        }
    }
}

// MARK: - Quick Reference Card

/// Show a quick reference card for a feature
struct QuickReferenceCard: View {
    let topic: HelpTopic
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: topic.icon)
                        .font(.title2)
                        .foregroundStyle(.tint)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(topic.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(topic.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding()
            .background(Color.appSystemBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Help Detail") {
    HelpDetailView(topic: AppHelp.recipesTab)
}

#Preview("Help Browser") {
    HelpBrowserView()
}

#Preview("Help Button") {
    NavigationStack {
        Text("Sample View")
            .navigationTitle("Sample")
            .helpButton(for: "recipesTab")
    }
}

