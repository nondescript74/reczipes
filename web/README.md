# Reczipes web

Reczipes in any browser — Safari, Chrome, Brave, Firefox, on any computer or phone, no Apple device needed.
Lane 37 (Reczipes2), **Web workstream**. Status: **Phase 0 LIVE** at https://reczipes-production.up.railway.app (Railway project `reczipes-web`), reading the
CloudKit **Production** public database. As of 2026-10-17 12:15 MT: 888 `SharedRecipe` records → **729 recipes shown**
(155 merged-library copies folded), **19 books**; *A Spicy Touch* shows 118 recipes. Live state: `GET /api/status`.

## What it does today

- **Recipes:** every recipe shared to the public catalogue from the iOS/macOS app, searchable by title or ingredient.
- **Recipe page:** ingredients (with metric toggle where the app stored metric), method, tips/substitutions/warnings,
  tap-to-tick ingredients and steps, *Keep screen on* while cooking (where the browser supports it), print layout.
- **Books:** compact cards (count = recipes actually on the web); each book opens its own page with views:
  - **Recipes** — the first 10 recipes, "Show all N", and search across the whole book.
  - **Index** — A–Z of the book's *current* recipes with letter jumps, generated on every load (never stored page numbers).
  - **Contents**, **Pictures**, **Glossary** — shown only when the app published them with the book (see *Book content*).
  The recipe page's back link returns to the book view it came from.
- Light and dark mode, phone to desktop, keyboard accessible. No account, no sign-in, read-only.

## How it gets recipes

The app already publishes shared recipes to the CloudKit **public** database of container
`iCloud.com.headydiscy.reczipes` (`CloudKitSharingService.swift`):

| record type | fields read here |
|---|---|
| `SharedRecipe` | `recipeData` (JSON of `CloudKitRecipe`), `mainImage` (asset), `sharedByName`, `sharedDate` |
| `SharedRecipeBook` | `bookData` (JSON of `CloudKitRecipeBook`), `recipePreviews`, `coverImage` (asset), `sharedByName`, `sharedDate` |

The server reads those over CloudKit Web Services with an **API token** (public-database reads need no user sign-in),
decodes them (`lib/decode.js` mirrors `SharedContentModels.swift` and `RecipeDisplayItem.swift`), caches for 5 minutes,
and serves a small JSON API to the page. The token never reaches the browser.

### Book content (optional fields; contract for the app)

Older app builds publish none of these and their books still work. When present, the site reads:

| where | field | shape |
|---|---|---|
| `bookData` JSON | `tableOfContents` | `[{ id, title, order, itemType, itemID }]` — `itemType` `heading` (a chapter/sub-heading row), `recipe` (itemID = recipe id), `image` (itemID = an `images[].id`); other types are listed as plain text |
| `bookData` JSON | `images` | `[{ id, title, caption, kind, order }]` — `kind` `cover` or `interior` (default); **no image bytes** |
| `bookData` JSON | `glossary` | `[{ id, term, localName, definition, relatedTerms, order }]` — **no image bytes** |
| record field | `bookImages` | CKAsset **list**, one asset per `images[]` entry, same order (pictures without an asset are skipped) |

`bookImages` is a new field on `SharedRecipeBook`: it has to exist in the Production schema (add in Development, deploy to
Production) before the app can write it. Keep image bytes out of `bookData` — the whole record is capped at ~1 MB.

**Consequence:** the web shows exactly what has been shared from the app — nothing private. To put a recipe on the web,
share it from the app. A private-library view would need iCloud sign-in in the browser (a later phase; see `MVP.md`).

**Read-only, never destructive.** If the same recipe was shared more than once, the page shows the newest copy.
Copies under *different* ids (e.g. from merging a Mac and an iPhone library) are shown once when their title **and**
ingredient names match; same-title recipes with different ingredients stay separate (Lane 37 rule 1: a title match
is not identity). Old links to a folded copy open the kept one. `/api/status` reports `collapsedCopies`. Nothing is
ever deleted.

## Data source is always named

| situation | what the page says |
|---|---|
| no `CLOUDKIT_API_TOKEN` set | "Preview mode: these are sample recipes." (`fixtures/sample.json`) |
| live, refresh OK | footer: "Updated <time>" |
| live, refresh failed | banner: "Couldn't refresh from iCloud just now; showing recipes as of <date>" |
| live, never loaded | error page — it does **not** fall back to sample data |

`GET /api/status` reports the source, counts, load time and last error.

## Run it

```bash
cd web
npm start            # http://localhost:8080 — sample data unless CLOUDKIT_API_TOKEN is set
npm test             # 17 tests: decoding, pagination, error handling, store behaviour
```

No dependencies (Node ≥ 20). No build step.

| env var | default | |
|---|---|---|
| `CLOUDKIT_API_TOKEN` | — | from CloudKit Console (the long value under *API Access*); absent ⇒ sample data; surrounding whitespace ignored |
| `CLOUDKIT_CONTAINER` | `iCloud.com.headydiscy.reczipes` | |
| `CLOUDKIT_ENVIRONMENT` | `production` | App Store/TestFlight builds write to production |
| `CACHE_TTL_SECONDS` | `300` | |
| `PORT` | `8080` | Railway sets this |
| `RECZIPES_DATA` | — | `fixtures` forces sample data |

## Operator steps to go live (only Z can do these)

1. **CloudKit API token.** CloudKit Console → container `iCloud.com.headydiscy.reczipes` → **Production** →
   Tokens & Keys → API Tokens → new token (name it `reczipes-web`, sign-in callback not needed). Copy it.
2. **Railway** (done 2026-10-15). Project `reczipes-web`, service from `nondescript74/reczipes` `main` (auto-deploys on push),
   **Root Directory `/web`**, **Healthcheck Path `/healthz`**, start command auto-detected (`npm start`), variable
   `CLOUDKIT_API_TOKEN`, domain `reczipes-production.up.railway.app`. Railway no longer lets new services use a
   `railway.json` config file, so these live in the service settings.
3. Open `<domain>/api/status`: expect `"source":"cloudkit"`, `"lastError":null` and non-zero counts.
4. In the app, share a recipe; within 5 minutes it appears on the site.

## Unverified until step 3 runs (stated, not assumed)

- The live CloudKit response shape. `fixtures/sample.json` was built from the Swift source, not captured from CloudKit
  (MTA M-13); `lib/decode.js` matches the documented Web Services record format. The first live `/api/status` is the check.
- ~~Production schema allows the unfiltered query~~ — checked 2026-10-15: `recordName` is Queryable on both types, and a direct
  query with the production token returned real `SharedRecipe` records.
- That CloudKit image `downloadURL`s are served from `*.icloud-content.com` (allowed in the CSP). If images don't show, check the browser console for a CSP block.

## Files

```
server.js            HTTP server, JSON API, static files, security headers
lib/cloudkit.js      CloudKit Web Services public-DB query client (read-only, paginated)
lib/decode.js        CloudKit records → recipe / book objects (mirrors the Swift Codable types)
lib/store.js         cache, refresh, source/error reporting
public/              the page (index.html, app.css, app.js — no framework)
fixtures/sample.json sample data in CloudKit response shape (scripts/make-fixtures.mjs)
test/                node:test suite
MVP.md               the MVP definition — Z's to fill in
```
