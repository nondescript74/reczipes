# Reczipes web — MVP definition

**Owner: Z.** This file is the MVP, and only Z defines it. Claude drafted the structure and the inventory below
from the app's own feature set (Reczipes2/Views); nothing here is decided until Z marks it.
Lane 37 (Reczipes2), Web workstream. Opened 2026-10-15.

**Why:** the app reaches Z and iOS testers (e.g. Carol) but not people without an Apple device — first, Z's sister.
Goal: put Reczipes in front of browser users (Safari, Chrome, Brave…) and, through them, others.

## Decisions taken (Z, 2026-10-15)

- Tracked as a **sub-track of Lane 37**, not a new lane.
- Code lives in **`reczipes/web/`** (same repo as the app; shares the data contract).
- **First release for the sister: browse and read.** Editing/adding comes later.
- Hosting: **Railway**.

## Phases (proposed — Z to confirm or reorder)

| phase | what | sign-in | status |
|---|---|---|---|
| **0** | Reader over the CloudKit public catalogue (recipes + books shared from the app) | none | **built, sample data; awaiting API token + Railway deploy** |
| 1 | **Z's MVP** — whatever Z marks below | ? | not started |
| 2 | Write path for browser users (add / edit / save their own) | needed | not started |
| 3 | Full parity candidates (extraction, allergens, meals…) | needed | not started |

## Sign-in options for phases 2–3 (decision needed before phase 2)

1. **Sign in with Apple ID in the browser (CloudKit JS).** Works in any browser; the sister needs a free Apple ID,
   not an Apple device. Her data lands in the same iCloud container as the app, so the app and the web stay one system.
2. **Separate web accounts** (email/password or Google) with a Railway database. Easiest for non-Apple users;
   becomes a second system that must sync with CloudKit.
3. **Shared family space** (Z invites people; they read and add to a shared library) — either on 1 or 2.

## Feature inventory — mark each: MVP / later / never

From the app as it stands. "Web cost" is Claude's rough read, for Z to override.

| # | feature (app) | web cost | Z: MVP / later / never |
|---|---|---|---|
| 1 | Browse + search shared recipes (SharedRecipesBrowserView) | **done (phase 0)** | |
| 2 | Recipe detail, metric toggle, print (RecipeDetailView) | **done (phase 0)** | |
| 3 | Shared recipe books (SharedRecipeBookListView) | **done (phase 0)** | |
| 4 | Cooking mode — step-by-step, large text, screen on (CookingModeView) | low | |
| 5 | Filters: course, cuisine, tags (RecipeFilterBar, CourseSearchView) | low–medium (needs those fields shared) | |
| 6 | Serving scaling | medium | |
| 7 | Share a recipe link by text/email (web URL per recipe) | low | |
| 8 | Add a recipe by typing it (CreateRecipeView) | needs sign-in | |
| 9 | Extract a recipe from a photo (RecipeExtractorView — Claude API) | medium + sign-in; server holds the API key | |
| 10 | Extract from a web link (LinkExtractionView) | medium + sign-in | |
| 11 | Batch photo extraction (BatchImageExtractorView) | high | |
| 12 | Personal books — create/edit (BookEditorView) | needs sign-in | |
| 13 | Allergen profile + recipe flags (AllergenProfileView) | medium | |
| 14 | FODMAP / diabetic analysis (FODMAP*, Diabetic*) | medium–high | |
| 15 | Meals / meal planning (MealsView) | medium + sign-in | |
| 16 | Recipe comparison / mashup (RecipeComparisonView, RecipeMashupView) | medium | |
| 17 | Aunt Shahsultan's recipe book as a featured book | low once shared from the app | |
| 18 | Install to home screen (PWA) / offline reading | low–medium | |
| 19 | Private library view of Z's own (unshared) recipes | needs Apple ID sign-in (option 1) | |

## Z's MVP (write here)

- 
- 
- 

**Audience for the MVP:** sister · family · testers · public? —
**Done means:** —
