import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { KEYS_FR } from '../public/i18n.js';

const app = readFileSync(new URL('../public/app.js', import.meta.url), 'utf8');
const html = readFileSync(new URL('../public/index.html', import.meta.url), 'utf8');

// Every interface string the page asks for has a French text.
test('every t()/tn() key and data-i18n attribute has French', () => {
  const keys = new Set();
  for (const m of app.matchAll(/\bt\('((?:[^'\\]|\\.)*)'/g)) keys.add(m[1]);
  for (const m of app.matchAll(/\btn\([^,]+,\s*'((?:[^'\\]|\\.)*)',\s*'((?:[^'\\]|\\.)*)'/g)) { keys.add(m[1]); keys.add(m[2]); }
  for (const m of app.matchAll(/PLURAL = \{([^}]*)\}/g)) for (const k of m[1].matchAll(/'([^']+)'/g)) keys.add(k[1]);
  for (const m of html.matchAll(/data-i18n(?:-aria)?="([^"]+)"/g)) keys.add(m[1]);
  // labels and data words passed through t() as variables
  for (const k of ['Tip', 'Substitution', 'Warning', 'Timing', 'Note', 'Recipes', 'Index', 'Contents', 'Pictures', 'Glossary',
    'Low', 'Moderate', 'High', 'Medium', 'Excellent', 'Good', 'Caution', 'Avoid', 'Verified', 'Limited', 'Review',
    'Recommended', 'Good Alternative', 'Limited Option', 'Oligosaccharides', 'Disaccharides', 'Monosaccharides', 'Polyols']) keys.add(k);
  const missing = [...keys].filter((k) => !(k in KEYS_FR));
  assert.deepEqual(missing, []);
  assert.ok(keys.size > 80, `only ${keys.size} keys found`);
});

test('French keeps every {placeholder} of its English key', () => {
  const ph = (s) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort();
  for (const [en, fr] of Object.entries(KEYS_FR)) assert.deepEqual(ph(fr), ph(en), en);
});

test('no English sentence is left as a bare literal in rendered text', () => {
  // h(tag, attrs, 'Capitalised literal') without t() would show English in French mode.
  const bare = [...app.matchAll(/h\('(?:p|h1|h2|h3|b|dt|span|a|button|small|summary|li)',\s*\{[^}]*\},\s*'([A-Z][^']{2,})'/g)].map((m) => m[1]);
  assert.deepEqual(bare, []);
});
