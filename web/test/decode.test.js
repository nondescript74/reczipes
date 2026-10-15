import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { decodeSharedRecipe, decodeSharedBook, swiftDateToISO, assetURL, newestPerId, summarize } from '../lib/decode.js';
import { createCloudKitClient } from '../lib/cloudkit.js';
import { createStore } from '../lib/store.js';

const fixturesPath = new URL('../fixtures/sample.json', import.meta.url);
const fixtures = JSON.parse(readFileSync(fixturesPath, 'utf8'));

test('Swift reference-date seconds convert to ISO', () => {
  assert.equal(swiftDateToISO(0), '2001-01-01T00:00:00.000Z');
  assert.equal(swiftDateToISO(813693600), '2026-10-14T18:00:00.000Z');
  assert.equal(swiftDateToISO(null), null);
});

test('SharedRecipe record decodes sections, notes and metadata', () => {
  const r = decodeSharedRecipe(fixtures.SharedRecipe[2]);
  assert.equal(r.title, 'Sample: Lemon Rice');
  assert.equal(r.ingredientSections.length, 2);
  assert.equal(r.ingredientSections[1].transitionNote, 'Have everything measured before you heat the oil.');
  assert.deepEqual(r.instructionSections.map((s) => s.title), ['Cook the rice', 'Finish']);
  assert.deepEqual(r.notes.map((n) => n.type), ['substitution', 'warning']);
  assert.equal(r.sharedByName, 'Reczipes sample');
  assert.equal(r.sharedDate, '2026-10-13T18:00:00.000Z');
});

test('malformed recipeData is skipped, not thrown', () => {
  assert.equal(decodeSharedRecipe(fixtures.SharedRecipe[3]), null);
  assert.equal(decodeSharedRecipe({ recordName: 'x', serverErrorCode: 'NOT_FOUND' }), null);
});

test('steps are ordered by stepNumber and blank steps dropped', () => {
  const rec = {
    recordName: 'r',
    fields: { recipeData: { value: JSON.stringify({ id: 'X', title: 'T', ingredientSections: [], notes: [], instructionSections: [{ steps: [{ stepNumber: 2, text: 'b' }, { stepNumber: 1, text: 'a' }, { stepNumber: 3, text: '  ' }] }] }) } },
  };
  assert.deepEqual(decodeSharedRecipe(rec).instructionSections[0].steps, [{ n: 1, text: 'a' }, { n: 2, text: 'b' }]);
});

test('asset downloadURL placeholder is filled', () => {
  const rec = { fields: { mainImage: { value: { downloadURL: 'https://cvws.icloud-content.com/B/abc/${f}?o=1' } } } };
  assert.equal(assetURL(rec, 'mainImage'), 'https://cvws.icloud-content.com/B/abc/mainImage.jpg?o=1');
  assert.equal(assetURL({ fields: {} }, 'mainImage'), null);
});

test('duplicate shares of one recipe collapse to the newest (read-side only)', () => {
  const all = fixtures.SharedRecipe.map(decodeSharedRecipe).filter(Boolean);
  const kept = newestPerId(all);
  assert.equal(all.length, 3);
  assert.equal(kept.length, 2);
  assert.ok(kept.some((r) => r.title === 'Sample: Masala Chai'));
});

test('summary search covers title and ingredient names', () => {
  const s = summarize(decodeSharedRecipe(fixtures.SharedRecipe[0]));
  assert.ok(s.search.includes('cardamom'));
  assert.ok(s.search.includes('masala chai'));
  assert.equal(s.ingredientCount, 6);
});

test('book decodes with previews', () => {
  const b = decodeSharedBook(fixtures.SharedRecipeBook[0]);
  assert.equal(b.name, 'Sample: Weeknight Basics');
  assert.equal(b.previews.length, 3);
  assert.equal(b.recipeIDs.length, 2);
});

test('store over fixtures marks book entries available only when shared', async () => {
  const store = createStore({ cloudkit: null, fixturesPath });
  const [book] = await store.listBooks();
  assert.deepEqual(book.entries.map((e) => e.available), [true, true, false]);
  assert.equal((await store.listRecipes()).length, 2);
  assert.equal((await store.getRecipe('a1b2c3d4-0000-4000-8000-000000000002')).title, 'Sample: Lemon Rice');
  assert.equal((await store.status()).source, 'fixtures');
});

test('CloudKit client follows continuationMarker and sends the token', async () => {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, body: JSON.parse(init.body) });
    const page = calls.length;
    return {
      ok: true,
      status: 200,
      json: async () => (page === 1 ? { records: [{ recordName: 'a' }], continuationMarker: 'M1' } : { records: [{ recordName: 'b' }] }),
    };
  };
  const ck = createCloudKitClient({ container: 'iCloud.com.headydiscy.reczipes', environment: 'production', apiToken: 'TOKEN', fetchImpl });
  const recs = await ck.queryAll('SharedRecipe');
  assert.deepEqual(recs.map((r) => r.recordName), ['a', 'b']);
  assert.match(calls[0].url, /\/iCloud\.com\.headydiscy\.reczipes\/production\/public\/records\/query\?ckAPIToken=TOKEN$/);
  assert.equal(calls[0].body.query.recordType, 'SharedRecipe');
  assert.equal(calls[1].body.continuationMarker, 'M1');
});

test('CloudKit server error surfaces as an error with its code', async () => {
  const fetchImpl = async () => ({ ok: false, status: 421, json: async () => ({ serverErrorCode: 'AUTHENTICATION_REQUIRED', reason: 'bad token' }) });
  const ck = createCloudKitClient({ container: 'c', environment: 'production', apiToken: 't', fetchImpl });
  await assert.rejects(ck.queryAll('SharedRecipe'), (e) => e.code === 'AUTHENTICATION_REQUIRED');
});

test('a failed refresh keeps the last good catalogue and reports the error', async () => {
  let fail = false;
  const cloudkit = {
    async queryAll(type) {
      if (fail) throw new Error('network down');
      return type === 'SharedRecipe' ? fixtures.SharedRecipe : fixtures.SharedRecipeBook;
    },
  };
  let t = 0;
  const store = createStore({ cloudkit, fixturesPath, ttlMs: 10, now: () => t });
  assert.equal((await store.listRecipes()).length, 2);
  fail = true;
  t = 100;
  await store.refresh();
  const s = await store.status();
  assert.equal(s.source, 'cloudkit');
  assert.equal(s.counts.recipes, 2);
  assert.equal(s.lastError.message, 'network down');
});

test('first load failing with no prior data is an error, not sample data', async () => {
  const cloudkit = { async queryAll() { throw new Error('no token'); } };
  const store = createStore({ cloudkit, fixturesPath });
  await assert.rejects(store.listRecipes(), /no token/);
  const s = await store.status();
  assert.equal(s.loaded, false);
  assert.equal(s.source, 'cloudkit');
});
