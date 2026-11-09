import { test } from 'node:test';
import assert from 'node:assert/strict';
import { decodeSharedRecipe, summarize } from '../lib/decode.js';
import { toMetric, parseAmount, unitWord } from '../public/units.js';

const english = {
  id: '3A79BC31-EA99-46D3-A1DF-FDE65E2EB505',
  title: 'Bajrani Raab',
  yield: 'Makes approximately 2½ cups (625 mL)',
  ingredientSections: [{ ingredients: [
    { quantity: '2½', unit: 'cups', name: 'water' },
    { quantity: '', unit: '', name: '   ' }, // blank row: dropped by the reader, English and French alike
    { quantity: '1', unit: 'tbsp', name: 'butter' },
  ] }],
  instructionSections: [{ steps: [
    { stepNumber: 2, text: 'Add milk and serve hot.' },
    { stepNumber: 1, text: 'Boil water and jaggery.' },
  ] }],
  notes: [{ type: 'general', text: 'Jaggery is unrefined cane sugar.' }],
  sharedDate: 0,
};
const french = {
  title: 'Bajrani Raab', yield: 'Donne environ 625 ml', headerNotes: null,
  ingredientSections: [{ title: null, transitionNote: null, ingredients: [
    { quantity: '625', unit: 'ml', name: 'eau', preparation: null },
    { quantity: null, unit: null, name: '', preparation: null },
    { quantity: '1', unit: 'c. à soupe', name: 'beurre', preparation: null },
  ] }],
  instructionSections: [{ title: null, steps: ['Ajouter le lait et servir chaud.', "Faire bouillir l'eau et le jaggery."] }],
  notes: ['Le jaggery est un sucre de canne non raffiné.'],
  source: 'abc', model: 'claude-opus-5-5', metric: true,
};
const record = (data) => ({ recordName: 'r1', fields: { recipeData: { value: JSON.stringify(data) } } });

test('a translation lines up with the English item for item, through the same filters', () => {
  const r = decodeSharedRecipe(record({ ...english, translationsJSON: JSON.stringify({ fr: french }) }));
  const fr = r.translations.fr;
  assert.equal(fr.yield, 'Donne environ 625 ml');
  assert.deepEqual(r.ingredientSections[0].ingredients.map((i) => i.name), ['water', 'butter']);
  assert.deepEqual(fr.ingredientSections[0].ingredients.map((i) => [i.quantity, i.unit, i.name]), [['625', 'ml', 'eau'], ['1', 'c. à soupe', 'beurre']]);
  // Steps sorted by step number in both, so step 1 is "Boil…" / "Faire bouillir…".
  assert.deepEqual(r.instructionSections[0].steps.map((s) => s.text), ['Boil water and jaggery.', 'Add milk and serve hot.']);
  assert.deepEqual(fr.instructionSections[0].steps.map((s) => s.text), ["Faire bouillir l'eau et le jaggery.", 'Ajouter le lait et servir chaud.']);
  assert.equal(fr.notes[0].type, 'general');
  assert.equal(fr.metric, true);
});

test('a translation that does not line up is dropped, the English stays', () => {
  const short = { ...french, instructionSections: [{ title: null, steps: ['Une seule étape.'] }] };
  const r = decodeSharedRecipe(record({ ...english, translationsJSON: JSON.stringify({ fr: short }) }));
  assert.equal(r.translations, null);
  assert.equal(r.title, 'Bajrani Raab');
});

test('a blank translated line falls back to the English so nothing shifts', () => {
  const blank = structuredClone(french);
  blank.ingredientSections[0].ingredients[2].name = '';
  blank.instructionSections[0].steps[0] = '';
  const fr = decodeSharedRecipe(record({ ...english, translationsJSON: JSON.stringify({ fr: blank }) })).translations.fr;
  assert.deepEqual(fr.ingredientSections[0].ingredients.map((i) => i.name), ['eau', 'butter']);
  assert.equal(fr.instructionSections[0].steps.length, 2);
});

test('no translations, bad JSON or odd keys: nothing breaks', () => {
  assert.equal(decodeSharedRecipe(record(english)).translations, null);
  assert.equal(decodeSharedRecipe(record({ ...english, translationsJSON: '{oops' })).translations, null);
  assert.equal(decodeSharedRecipe(record({ ...english, translationsJSON: JSON.stringify({ '<x>': french }) })).translations, null);
});

test('cards carry the translated title and yield; search finds French words', () => {
  const s = summarize(decodeSharedRecipe(record({ ...english, translationsJSON: JSON.stringify({ fr: french }) })));
  assert.deepEqual(s.translations.fr, { title: 'Bajrani Raab', yield: 'Donne environ 625 ml', headerNotes: null });
  assert.ok(s.search.includes('beurre'));
  assert.equal(summarize(decodeSharedRecipe(record(english))).translations, null);
});

test('amounts: parsed, converted, rounded the way a cook measures', () => {
  assert.equal(parseAmount('2½'), 2.5);
  assert.equal(parseAmount('1 1/2'), 1.5);
  assert.equal(parseAmount('1/2'), 0.5);
  assert.equal(parseAmount('1,5'), 1.5);
  assert.equal(parseAmount('a few'), null);
  assert.deepEqual(toMetric('2½', 'cups'), { quantity: '600', unit: 'ml' });
  assert.deepEqual(toMetric('½', 'cup'), { quantity: '120', unit: 'ml' });
  assert.deepEqual(toMetric('8', 'oz'), { quantity: '225', unit: 'g' });
  assert.deepEqual(toMetric('2', 'lb'), { quantity: '900', unit: 'g' });
  assert.deepEqual(toMetric('3', 'lb', 'fr'), { quantity: '1,35', unit: 'kg' });
  assert.deepEqual(toMetric('1-2', 'cups', 'fr'), { quantity: '240–475', unit: 'ml' });
  assert.deepEqual(toMetric('5', 'cups', 'fr'), { quantity: '1,2', unit: 'l' });
  assert.equal(toMetric('1', 'tbsp'), null); // spoons are metric already
  assert.equal(toMetric('some', 'cups'), null);
});

test('unit words in French; English untouched', () => {
  assert.equal(unitWord('tbsp', 'fr'), 'c. à soupe');
  assert.equal(unitWord('tsp', 'fr'), 'c. à café');
  assert.equal(unitWord('T', 'fr'), 'c. à soupe');
  assert.equal(unitWord('pinch', 'fr'), 'pincée');
  assert.equal(unitWord('tbsp', 'en'), 'tbsp');
  assert.equal(unitWord('handful', 'fr'), 'handful');
});
