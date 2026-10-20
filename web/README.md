# Reczipes web

Reczipes in any browser — Safari, Chrome, Brave, Firefox, on any computer or phone, no Apple device needed.
Lane 37 (Reczipes2), **Web workstream**. Status: **LIVE, sign-in required** at **https://reczipes.industriallystrong.com** (from 2026-10-20;
behind Cloudflare Access — see *Who can see it*). The old address `reczipes-production.up.railway.app` redirects there. Railway project `reczipes-web`, reading the
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
- Light and dark mode, phone to desktop, keyboard accessible. Read-only. Sign-in is a one-time code e-mailed by Cloudflare (see below).

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

## Who can see it — Cloudflare Access (from 2026-10-20)

Same pattern as the Japan 2027 trip page and hvhoa-jena: **two locks, one door.**

1. **Cloudflare (the edge).** DNS `CNAME reczipes → nqdp8rwy.up.railway.app`, **Proxied**, plus `TXT _railway-verify.reczipes`
   (Railway's domain check). Zero Trust → Access → Applications → self-hosted **`Reczipes`**
   (`reczipes.industriallystrong.com`, session 24 h, all identity providers = one-time PIN by e-mail), policy
   **`Reczipes guests`** — Allow · Emails. On 2026-10-20 it was set to the Japan 2027 guest list (operator: "the same user list for now") —
   10 e-mails, read back after saving; it is its own policy, so the two lists can now differ.
   **To let someone in:** add their e-mail to `Reczipes guests`. **To remove:** delete it (their session lasts until it expires).
2. **This process (the origin).** `lib/access-guard.js` (ported from `eml-corpus-tree/server/access-guard.mjs`, with the
   JPNTWN2027 viewer's changes) verifies the Access JWT itself — RS256 against the team certs, `iss`, `aud`, `exp`/`nbf`, an
   e-mail claim — on **every** request except `/healthz`. Railway also answers on its own hostnames, which Cloudflare never sees;
   this is what keeps those closed. Fails closed: missing configuration ⇒ `403 GUARD_NOT_CONFIGURED`.
3. **The old address.** A request for `reczipes-production.up.railway.app` (`RECZIPES_LEGACY_HOSTS`) gets a `302` to the same path on
   the new host, so old links and bookmarks reach the login. It never serves recipes. Any other host ⇒ `403 HOST_NOT_SERVED`.
4. **Open tabs.** A page loaded before the switch keeps its old script; its next request fails and it shows "couldn't be loaded" —
   a refresh takes the reader to the login. From this version on, the page reloads itself once (at most once a minute) when an API
   call is redirected to the login or answered 401, so an expired session lands on the login by itself.

Live counts now need a signed-in browser: `/api/status` is behind the login like everything else (only `/healthz` is open, and
it says only `{"ok":true}`).

## Run it

```bash
cd web
npm start            # http://localhost:8080 — sample data unless CLOUDKIT_API_TOKEN is set
npm test             # node:test — decoding, store, and the Access guard (refusals, legacy redirect, end-to-end socket)
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
| `RECZIPES_PUBLIC_HOST` | — | `reczipes.industriallystrong.com` (required for any non-local request) |
| `CF_ACCESS_TEAM_DOMAIN` | — | `headydiscy.cloudflareaccess.com` |
| `CF_ACCESS_AUD` | — | the `Reczipes` Access app's Application Audience (AUD) tag (Railway variable; not in the repo) |
| `CF_ACCESS_EMAILS` | — | `ACCESS_POLICY` = the Access policy is the list; or a comma list, enforced here too |
| `RECZIPES_LEGACY_HOSTS` | — | `reczipes-production.up.railway.app` — redirected to the public host |

Locally (`npm start` / `npm run dev`) the browser on the same machine passes as *loopback* without a token.

## Operator steps to go live (only Z can do these)

1. **CloudKit API token.** CloudKit Console → container `iCloud.com.headydiscy.reczipes` → **Production** →
   Tokens & Keys → API Tokens → new token (name it `reczipes-web`, sign-in callback not needed). Copy it.
2. **Railway** (done 2026-10-15). Project `reczipes-web`, service from `nondescript74/reczipes` `main` (auto-deploys on push),
   **Root Directory `/web`**, **Healthcheck Path `/healthz`**, start command auto-detected (`npm start`), variable
   `CLOUDKIT_API_TOKEN` (+ the five Access variables above, 2026-10-20), domains `reczipes-production.up.railway.app` (now redirect only) and
   `reczipes.industriallystrong.com` (port 8080). Railway no longer lets new services use a
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
lib/access-guard.js  Cloudflare Access JWT verification, legacy-host redirect (the second lock)
public/              the page (index.html, app.css, app.js — no framework)
fixtures/sample.json sample data in CloudKit response shape (scripts/make-fixtures.mjs)
test/                node:test suite
MVP.md               the MVP definition — Z's to fill in
```

**Book pictures (app builds from 2026-10-17).** The app no longer puts picture bytes in the book record. Each picture is its own public `SharedBookPicture` record (`bookID`, `bookRecordName`, `pictureID`, `kind` cover|interior, `title`, `caption`, `order`, `sourcePage`, `linkedRecipeIDs`, `image` CKAsset, `imageHash`); `bookData.images` keeps metadata only. The store queries `SharedBookPicture` alongside the other two types and joins pictures to books by `bookRecordName` (fallback `bookID`); a failed picture query logs and leaves books without pictures rather than failing the load. Legacy inline `bookImages` still decode for older shares.
