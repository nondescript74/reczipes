# Recipe API Integration

This app now includes `recipe-api.com` integration focused on low-quota validation and smoke testing.

## What was added

- `RecipeAPIClient.swift`
  - `GET /health` (no key, free)
  - `GET /api/v1/dinner` (no key, free)
  - `GET /api/v1/categories` (requires `X-API-Key`, free)
  - Key validation via `/api/v1/categories`
- `APIKeyHelper.swift`
  - Added dedicated Keychain storage for recipe-api key: `recipeAPIKey`
  - New helpers:
    - `getRecipeAPIKey()`
    - `setRecipeAPIKey(_:)`
    - `removeRecipeAPIKey()`
    - `isRecipeAPIConfigured`
- `RecipeAPIIntegrationView.swift`
  - Onboarding UI for recipe-api key
  - Save + validate workflow
  - Quota-safe endpoint test buttons
  - `SettingsView.swift`
  - Added recipe-api key status
  - Added `Recipe API Setup & Test` entry point
- URL extraction provider strategy
  - Default: `Recipe API -> Claude fallback`
  - User-selectable in `RecipeExtractorView`:
    - `Auto (Recipe API -> Claude)`
    - `Recipe API Only`
    - `Claude Only`

## Why these endpoints

Per recipe-api docs:

- `/health` and `/api/v1/dinner` are public and do not require a key.
- `/api/v1/categories` requires a key but is free.

This allows complete key onboarding and connectivity checks without consuming metered detail/generation credits.

## Usage

1. Open **Settings**.
2. Go to **Recipe Extraction**.
3. Tap **Recipe API Setup & Test**.
4. Enter `rapi_...` key and tap **Save & Validate Key**.
5. Run smoke tests:
   - Health
   - Dinner sample
   - Auth categories
