// Holds the decoded catalogue in memory and refreshes it from CloudKit.
//
// Two sources, and the page always says which one it is showing:
//   "cloudkit"  live public database
//   "fixtures"  bundled sample data (no token configured, or RECZIPES_DATA=fixtures)
// A failed live refresh keeps the last good catalogue and reports the error;
// it never quietly substitutes sample data for real data (MTA M-19).

import { readFile } from 'node:fs/promises';
import { decodeSharedRecipe, decodeSharedBook, newestPerId, summarize } from './decode.js';

export function createStore({ cloudkit, fixturesPath, ttlMs = 5 * 60 * 1000, now = () => Date.now() }) {
  const source = cloudkit ? 'cloudkit' : 'fixtures';
  let state = null; // { recipes, books, byId, loadedAt }
  let lastError = null;
  let inflight = null;

  async function loadRaw() {
    if (cloudkit) {
      const [recipeRecords, bookRecords] = await Promise.all([
        cloudkit.queryAll('SharedRecipe'),
        cloudkit.queryAll('SharedRecipeBook'),
      ]);
      return { recipeRecords, bookRecords };
    }
    const json = JSON.parse(await readFile(fixturesPath, 'utf8'));
    return { recipeRecords: json.SharedRecipe ?? [], bookRecords: json.SharedRecipeBook ?? [] };
  }

  function build({ recipeRecords, bookRecords }) {
    const recipes = newestPerId(recipeRecords.map(decodeSharedRecipe).filter(Boolean)).sort((a, b) =>
      a.title.localeCompare(b.title, undefined, { sensitivity: 'base' }),
    );
    const books = newestPerId(bookRecords.map(decodeSharedBook).filter(Boolean)).sort((a, b) =>
      a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }),
    );
    const byId = new Map(recipes.map((r) => [r.id.toUpperCase(), r]));
    return {
      recipes,
      books,
      byId,
      skipped: { recipes: recipeRecords.length - recipes.length, books: bookRecords.length - books.length },
      rawCounts: { recipes: recipeRecords.length, books: bookRecords.length },
      loadedAt: new Date(now()).toISOString(),
      loadedAtMs: now(),
    };
  }

  async function refresh() {
    if (!inflight) {
      inflight = (async () => {
        try {
          state = build(await loadRaw());
          lastError = null;
        } catch (err) {
          lastError = { message: err.message, at: new Date(now()).toISOString() };
          if (!state) throw err;
        } finally {
          inflight = null;
        }
      })();
    }
    return inflight;
  }

  async function ensure() {
    if (!state) return refresh();
    if (now() - state.loadedAtMs > ttlMs) refresh().catch(() => {}); // stale-while-revalidate
  }

  return {
    source,
    refresh,
    async status() {
      try {
        await ensure();
      } catch {
        /* reported below */
      }
      return {
        source,
        loaded: Boolean(state),
        loadedAt: state?.loadedAt ?? null,
        counts: state ? { recipes: state.recipes.length, books: state.books.length } : null,
        rawCounts: state?.rawCounts ?? null,
        lastError,
      };
    },
    async listRecipes() {
      await ensure();
      return state.recipes.map(summarize);
    },
    async getRecipe(id) {
      await ensure();
      return state.byId.get(String(id).toUpperCase()) ?? null;
    },
    async listBooks() {
      await ensure();
      return state.books.map(({ previews, recipeIDs, ...b }) => {
        // Prefer the previews the app wrote; fall back to the bare recipe ids.
        const base = previews.length
          ? previews
          : recipeIDs.map((id) => ({ id, title: state.byId.get(id.toUpperCase())?.title ?? null }));
        // Only link entries whose recipe is itself shared and therefore readable here.
        const entries = base
          .map((p) => ({ ...p, available: Boolean(p.id && state.byId.has(p.id.toUpperCase())) }))
          .filter((p) => p.title);
        return { ...b, recipeCount: Math.max(recipeIDs.length, previews.length), entries };
      });
    },
  };
}
