# Communal Recipe Library — Implementation Spec

**Status:** DRAFT / awaiting operator approval before implementation.
**AS-OF:** 2026-07-01 · Repo HEAD `a8d6693` · Author: CLAW (Claude / S5).
**Maturity:** SOURCE-DERIVED. Every current-state claim below is `file:line`-grounded from read-only
inspection of the mounted repo. No behavioral claim is runtime-verified yet.

---

## 1. Goal (operator directive, verbatim intent)

> "When a user updates or installs the app, all the CloudKit recipes from all the other users and
> themselves should be available to them in the app." — **"Every recipe from every user, available to
> everyone if they choose to have that."**

Interpretation (locked with operator):

- **Opt-in on both sides.** A recipe enters the communal pool only if its owner chooses to share it
  (contributor consent). A user sees the pool only if they choose to participate (consumer consent).
- **Read-only communal + "Save a copy."** Others' recipes are viewed read-only; the user can copy one
  into their own editable recipes.
- **Fully communal when opted in.** No 400-cap, no self-exclusion — all shared recipes from all users
  (including the current user's own shared recipes) are available.

---

## 2. Current state (grounded)

### 2.1 Two public-DB corpora exist

| Corpus (CKRecord type) | Writer | Reader | Consent-gated? |
|---|---|---|---|
| `"RecipeX"` | `RecipeXCloudKitSyncService.syncRecipe` (`Models/RecipeXCloudKitSyncService.swift:209,178`) | **nobody** — type appears once in whole repo (the write) | **No** — `needsCloudSync` defaults `true`; pushes every recipe unconditionally |
| `"sharedRecipe"` (`CloudKitRecordType.sharedRecipe`) | `CloudKitSharingService` share flow | `fetchSharedRecipes` / `syncCommunityRecipesForViewing` / `SharedRecipesBrowserView` | **Yes** — via `SharingPreferences.shareAllRecipes` + per-recipe `SharedRecipe.isActive` |

**Consequence:** the `RecipeX` public push is a write-only, non-consensual corpus that nothing reads —
both a privacy violation of "if they choose" and dead weight. **Decision: deprecate it** (operator-approved).

### 2.2 Consumer-side machinery already built

- `CloudKitSharingService.syncCommunityRecipesForViewing(modelContext:limit:)`
  (`Models/CloudKitSharingService.swift:1732`) — fetches shared recipes with full cursor pagination
  (`limit: Int.max` = all), upserts into `CachedSharedRecipe`, prunes entries missing from CloudKit or
  older than 30 days (`:1796-1808`). **Currently calls `fetchSharedRecipes(limit:excludeCurrentUser: true)`
  (`:1742`) and is not invoked at launch.**
- `fetchSharedRecipes(limit:excludeCurrentUser:)` (`:808`) — cursor pagination in 100-batches; predicate
  `sharedBy != currentUserID` when excluding self (`:817-818`).
- `importSharedRecipe(_:modelContext:)` (`:2573`) — "Save a copy": builds a `RecipeX` from a
  `CloudKitRecipe`. Already wired into `SharedRecipesBrowserView` (`Views/SharedRecipesBrowserView.swift:255`).
- Browse UI `SharedRecipesBrowserView` fetches with a hard `limit: 100` (`:235`).

### 2.3 Consent model

- `SharingPreferences` (`Models/SharingPreferences.swift:19`): `shareAllRecipes=false`,
  `shareAllBooks=false`, `allowOthersToSeeMyName=true`, `displayName`. **No consumer opt-in flag exists.**
- Contributor toggle UI: `SharingSettingsView` "Auto-Share New Recipes" → `shareAllRecipes`
  (`Views/SharingSettingsView.swift:398-412`), `shareAllRecipes()`/`unshareAllRecipes()`.

---

## 3. Gap list → changes

| # | Gap | Change | Files |
|---|---|---|---|
| G1 | No consumer opt-in flag | Add `browseCommunity: Bool = false` to `SharingPreferences` (+ init) | `Models/SharingPreferences.swift` |
| G2 | Community sync excludes self | Add `includeSelf` param to `syncCommunityRecipesForViewing`; pass `excludeCurrentUser: !includeSelf` | `Models/CloudKitSharingService.swift:1732-1743` |
| G3 | No launch/update hydration | On startup, if `browseCommunity`, run `syncCommunityRecipesForViewing(limit: .max, includeSelf: true)` in a detached Task | `Reczipes2App.swift` startup pipeline (~`:282-296`) |
| G4 | Browse capped at 100 | Back `SharedRecipesBrowserView` with the `CachedSharedRecipe` store (hydrated in full) instead of a live `limit:100` fetch; add pull-to-refresh calling the full sync | `Views/SharedRecipesBrowserView.swift:235` |
| G5 | Non-consensual RecipeX push | Deprecate: remove the `startAutomaticSync` launch call site; stop new `RecipeX` public writes. Keep the type read-free. | call site of `RecipeXCloudKitSyncService.startAutomaticSync` (locate in `Reczipes2App`), `Models/RecipeXCloudKitSyncService.swift` |
| G6 | Opt-in UX | Add a "Browse community library" toggle in `SharingSettingsView` bound to `browseCommunity`; first enable triggers an initial hydrate | `Views/SharingSettingsView.swift` |

### 3.1 Default for `browseCommunity`
Recommend **default `false`** (privacy-preserving; user opts in), consistent with `shareAllRecipes=false`.
First-launch onboarding can surface the choice. **Open item O1** — confirm default.

---

## 4. Behavior after change

**Install/update + opted-in:** at launch, the app fetches every `sharedRecipe` from all users (incl. the
user's own shared ones), caches them locally (`CachedSharedRecipe`), and shows them in the browser,
read-only, each with "Save a copy." Cache refreshes on launch and pull-to-refresh; 30-day pruning stays.

**Not opted-in:** no communal fetch; app behaves as a private recipe manager. No recipe is published unless
`shareAllRecipes` (or a per-recipe share) is on.

**RecipeX public push:** gone. Sharing flows solely through the consent-gated `sharedRecipe` path. This
makes the former R2 (`serverRecordChanged` conflict resolution on `RecipeX`) **moot** — task removed.

---

## 5. CloudKit schema / ops considerations

- Fetching all uses `NSPredicate(value: true)` / `sharedBy` filtering — `sharedRecipe` record type and the
  `sharedBy` field must be **queryable** in the CloudKit **Production** environment (Dashboard schema).
  Verify before release. (Recipe-manager entitlement currently `aps-environment=development` — separate
  release-blocker R3 in the architecture map.)
- Scale: "all recipes" grows unbounded. Cursor pagination handles fetch, but full local caching of a large
  communal pool has storage/perf cost. **Open item O2** — cap the cache size (e.g. N most-recent) or accept
  unbounded with the 30-day prune as the only bound. Recommend a soft cap (e.g. 2,000 most-recent by
  `sharedDate`) with "load more."
- Image assets: `syncCommunityRecipesForViewing` already carries `imageData` through (`:1778,1787`).
  Bulk image download at launch is bandwidth-heavy — **Open item O3**: defer image fetch to on-demand
  (thumbnail lazy-load) vs eager.

---

## 6. Test plan (Swift Testing, mirror existing `Reczipes2Tests` style)

1. `browseCommunity` defaults false; toggling persists (mirror `SharingUIBehaviorTests`).
2. Gating: hydration is a no-op when `browseCommunity == false`.
3. `syncCommunityRecipesForViewing(includeSelf: true)` calls `fetchSharedRecipes(excludeCurrentUser: false)`
   (inject a fake/seam over the CloudKit fetch — see O4).
4. Upsert semantics: existing cached recipe updated, new one inserted, missing one pruned.
5. `importSharedRecipe` produces a `RecipeX` with expected fields (extend existing coverage).
6. Regression: no code path writes a `"RecipeX"` CKRecord after G5.

**Open item O4** — `CloudKitSharingService` is a `shared` singleton hitting live CloudKit; tests need a
seam (protocol/injectable fetch). Small refactor; scope in implementation.

---

## 7. Rollout / back-compat

- Existing already-pushed public `RecipeX` records become orphaned (never read). **Open item O5** — leave
  them (harmless) vs a one-time cleanup pass. Recommend leave; optional admin cleanup later.
- `SharingPreferences` schema add is additive with a default → safe under the existing
  `Reczipes2MigrationPlan`; no destructive migration.

---

## 8. Open items for operator

- **O1** `browseCommunity` default: `false` (recommended) vs `true`.
- **O2** Communal cache size: soft cap (recommended ~2,000) vs unbounded.
- **O3** Images: lazy on-demand (recommended) vs eager at hydrate.
- **O4** Accept the small testability refactor (fetch seam) — yes/no.
- **O5** Orphaned public `RecipeX` records: leave (recommended) vs cleanup pass.

---

## 9. Implementation order (after approval)

1. G1 `browseCommunity` (+ migration-safe default) → build.
2. G2 include-self param → build.
3. G5 deprecate RecipeX push (remove launch call) → build.
4. G3 launch hydration hook (gated) → build.
5. G4 + G6 browse-from-cache + opt-in toggle UI → build.
6. Tests (§6) → run suite.
7. Full build + targeted test run in Xcode (runtime-verify), update architecture map §0a/§0b.
