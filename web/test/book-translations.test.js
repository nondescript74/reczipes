// Book descriptions in the reader's language; book names never translated.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { decodeBookTranslations, decodeSharedBook } from '../lib/decode.js';

const bookRecord = (data) => ({
  recordName: 'R1',
  fields: { bookData: { value: JSON.stringify(data) }, name: { value: data.name } },
});

test('a book keeps its name and carries its description translations', () => {
  const b = decodeSharedBook(bookRecord({
    id: 'B1', name: 'Doulat Premji', bookDescription: 'Recipes by my mom', recipeIDs: [],
    translations: { fr: { bookDescription: 'Recettes de ma mère', source: 'x', model: 'm' } },
  }));
  assert.equal(b.name, 'Doulat Premji');
  assert.equal(b.description, 'Recipes by my mom');
  assert.deepEqual(b.translations, { fr: { description: 'Recettes de ma mère' } });
});

test('no English description, blank or odd entries: nothing kept', () => {
  assert.equal(decodeBookTranslations({ name: 'X', translations: { fr: { bookDescription: 'Y' } } }), undefined);
  assert.equal(decodeBookTranslations({ bookDescription: 'D', translations: { fr: { bookDescription: '  ' } } }), undefined);
  assert.equal(decodeBookTranslations({ bookDescription: 'D', translations: { '../x': { bookDescription: 'Y' } } }), undefined);
  assert.equal(decodeBookTranslations({ bookDescription: 'D' }), undefined);
});
