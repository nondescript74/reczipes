// Holds the decoded catalogue in memory and refreshes it from CloudKit.
//
// Two sources, and the page always says which one it is showing:
//   "cloudkit"  live public database
//   "fixtures"  bundled sample data (no token configured, or RECZIPES_DATA=fixtures)
// A failed live refresh keeps the last good catalogue and reports the error;
// it never quietly substitutes sample data for real data (MTA M-19).

import { readFile } from 'node:fs/promises';
import { decodeSharedRecipe, decodeSharedBook, decodeSharedBookPicture, attachBookPictures, newestPerId, collapseCopies, summarize, dropOwnerDeleted } from './decode.js';

export function createStore({ cloudkit, fixturesPath, ttlMs = 5 * 60 * 1000, now = () => Date.now() }) {
  const source = cloudkit ? 'cloudkit' : 'fixtures';
  let state = null; // { recipes, books, byId, loadedAt }
  let lastError = null;
  let inflight = null;

  async function loadRaw() {
    if (cloudkit) {
      const [recipeRecords, bookRecords, pictureRecords] = await Promise.all([
        cloudkit.queryAll('SharedRecipe'),
        cloudkit.queryAll('SharedRecipeBook'),
        // Picture records exist only once an app build from 2026-10-17 has shared a book
        // with pictures; a missing record type must not take the whole catalogue down.
        cloudkit.queryAll('SharedBookPicture').catch((err) => {
          console.error('[SharedBookPicture]', err.message);
          return [];
        }),
      ]);
      return { recipeRecords, bookRecords, pictureRecords };
    }
    const json = JSON.parse(await readFile(fixturesPath, 'utf8'));
    return {
      recipeRecords: json.SharedRecipe ?? [],
      bookRecords: json.SharedRecipeBook ?? [],
      pictureRecords: json.SharedBookPicture ?? [],
    };
  }

  function build({ recipeRecords, bookRecords, pictureRecords = [] }) {
    const liveRecipes = dropOwnerDeleted(recipeRecords.map(decodeSharedRecipe).filter(Boolean));
    const liveBooks = dropOwnerDeleted(bookRecords.map(decodeSharedBook).filter(Boolean));
    const uniqueById = newestPerId(liveRecipes.live);
    const { kept, alias } = collapseCopies(uniqueById);
    const recipes = kept.sort((a, b) => a.title.localeCompare(b.title, undefined, { sensitivity: 'base' }));
    const pictures = pictureRecords.map(decodeSharedBookPicture).filter(Boolean);
    const books = attachBookPictures(
      newestPerId(liveBooks.live),
      pictures,
    ).sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
    const byId = new Map(recipes.map((r) => [r.id.toUpperCase(), r]));
    // Links to a collapsed copy (old URLs, book entries) resolve to the kept recipe.
    for (const [dropped, keptId] of alias) byId.set(dropped, byId.get(keptId.toUpperCase()));
    return {
      recipes,
      books,
      byId,
      skipped: { recipes: recipeRecords.length - recipes.length, books: bookRecords.length - books.length },
      collapsedCopies: alias.size,
      ownerDeleted: { recipes: liveRecipes.deletedCount, books: liveBooks.deletedCount },
      rawCounts: { recipes: recipeRecords.length, books: bookRecords.length, pictures: pictureRecords.length },
      loadedAt: new Date(now()).toISOString(),
      loadedAtMs: now(),
    };
  }


  // A book's recipe list: the previews the app wrote, else its bare recipe ids. Each
  // entry resolves through byId (so folded copies point at the kept recipe); entries
  // whose recipe is not in the public catalogue are counted but not linked.
  function bookWithEntries({ previews, recipeIDs, ...b }) {
    const base = previews.length
      ? previews
      : recipeIDs.map((id) => ({ id, title: state.byId.get(id.toUpperCase())?.title ?? null }));
    const seen = new Set();
    const entries = [];
    for (const p of base) {
      const target = p.id ? state.byId.get(p.id.toUpperCase()) : null;
      if (target) {
        if (seen.has(target.id)) continue;
        seen.add(target.id);
        entries.push({ id: target.id, title: target.title, available: true });
      } else if (p.title) {
        entries.push({ id: p.id, title: p.title, available: false });
      }
    }
    return { ...b, recipeCount: Math.max(recipeIDs.length, previews.length), entries };
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
        collapsedCopies: state?.collapsedCopies ?? 0,
        ownerDeleted: state?.ownerDeleted ?? { recipes: 0, books: 0 },
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
      return state.books.map((b) => {
        const { entries, sections, images, glossary, ...rest } = bookWithEntries(b);
        return {
          ...rest,
          webCount: entries.filter((e) => e.available).length,
          pictureCount: images.length,
          glossaryCount: glossary.length,
        };
      });
    },
    async getBook(id) {
      await ensure();
      const b = state.books.find((x) => x.id.toUpperCase() === String(id).toUpperCase());
      if (!b) return null;
      const full = bookWithEntries(b);
      // Contents rows that name a recipe resolve like entries do (folded copies -> kept recipe).
      const sections = full.sections.map((s) => {
        if (s.itemType !== 'recipe') return s;
        const target = s.itemID ? state.byId.get(s.itemID) : null;
        return { ...s, itemID: target ? target.id : s.itemID, available: Boolean(target) };
      });
      return { ...full, sections, webCount: full.entries.filter((e) => e.available).length };
    },
  };
}
