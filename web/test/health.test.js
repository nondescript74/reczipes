import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  substitutionFor, fodmapFoodFor, fodmapSubstitutions, fodmapIsSafe,
  diabetesScore, diabetesSuitability, normDiabeticInfo, recipeHealth,
} from '../lib/health.js';
import { decodeSharedRecipe, collapseCopies } from '../lib/decode.js';
import { buildData, render, OUT, SWIFT_MODELS } from '../scripts/gen-health-data.mjs';

const recipe = (...names) => ({
  ingredientSections: [{ title: null, ingredients: names.map((n) => (typeof n === 'string' ? { name: n } : n)) }],
});

// Drift check: the committed tables must be what the generator makes from the Swift source.
// Skipped where the Swift tree is absent (a deploy that ships web/ alone).
test('health-data.js matches the app Swift tables', { skip: !existsSync(join(SWIFT_MODELS, 'FODMAPSubstitution.swift')) }, () => {
  const data = buildData();
  assert.equal(readFileSync(OUT, 'utf8'), render(data), 'run: node scripts/gen-health-data.mjs');
  assert.equal(data.fodmapSubstitutions.length, 23);
  assert.equal(data.fodmapSubstitutions.reduce((n, s) => n + s.substitutes.length, 0), 61);
  assert.equal(data.fodmapFoods.length, 53);
  assert.ok(data.fodmapSubstitutions.every((s) => s.explanation && s.fodmapCategories.length));
});

test('substitution lookup is the app substring match, first table entry wins', () => {
  assert.equal(substitutionFor('Red Onion').originalIngredient, 'onion');
  assert.equal(substitutionFor('garlic cloves').originalIngredient, 'garlic');
  assert.equal(substitutionFor('whole milk').originalIngredient, 'milk');
  assert.equal(substitutionFor('pineapple').originalIngredient, 'apple'); // as in the app
  assert.equal(substitutionFor('rice'), null);
});

test('high-FODMAP food match honours word boundaries and exceptions', () => {
  assert.equal(fodmapFoodFor('apples').name, 'apple');
  assert.equal(fodmapFoodFor('pineapple'), null);
  assert.equal(fodmapFoodFor('apple cider vinegar'), null);
  assert.equal(fodmapFoodFor('coconut milk'), null);
  assert.equal(fodmapFoodFor('cherry tomatoes'), null);
  assert.equal(fodmapFoodFor('wheat flour').name, 'wheat');
});

test('recipe FODMAP analysis: level by count, safe flag from the analyzer', () => {
  assert.deepEqual(fodmapSubstitutions(recipe('rice', 'salt')), {
    substitutions: [], overallLevel: 'Low', isSafeWithoutSubstitutions: true, hasSubstitutions: false,
  });
  const two = fodmapSubstitutions(recipe({ quantity: '1', unit: 'large', name: 'onion' }, 'garlic', 'rice'));
  assert.equal(two.overallLevel, 'Moderate');
  assert.equal(two.isSafeWithoutSubstitutions, false);
  assert.deepEqual(two.substitutions.map((g) => [g.key, g.substitution.originalIngredient]), [['0.0', 'onion'], ['0.1', 'garlic']]);
  assert.deepEqual(two.substitutions[0].ingredient, { quantity: '1', unit: 'large', name: 'onion' });
  assert.equal(fodmapSubstitutions(recipe('onion', 'garlic', 'honey')).overallLevel, 'High');
  // Preparation counts for the safe flag (FODMAPAnalyzer reads it) but not for substitutions.
  const prep = recipe({ name: 'rice', preparation: 'cooked with garlic' });
  assert.equal(fodmapIsSafe(prep), false);
  assert.equal(fodmapSubstitutions(prep).hasSubstitutions, false);
});

test('diabetes score follows DiabetesAnalyzer weights and bands', () => {
  assert.deepEqual(diabetesScore(recipe('spinach', 'olive oil')), {
    riskScore: 0, suitability: 'Excellent', isDiabeticFriendly: true,
    highSugarIngredients: [], refinedCarbIngredients: [], beneficialIngredients: ['spinach', 'olive oil'],
  });
  const cake = diabetesScore(recipe('sugar', 'all-purpose flour', 'honey', 'butter'));
  // sugar 3 + flour 3 (high-sugar list) + honey 3 = 9, flour also refined carb 2 = 11
  assert.equal(cake.riskScore, 11);
  assert.equal(cake.suitability, 'Avoid');
  assert.equal(cake.isDiabeticFriendly, false);
  assert.deepEqual(cake.refinedCarbIngredients, ['all-purpose flour']);
  // unit and preparation are read too, as in the app
  assert.deepEqual(diabetesScore(recipe({ name: 'rice', preparation: 'white rice' })).highSugarIngredients, ['white rice']);
  assert.deepEqual([0, 3, 4, 6, 7, 10, 11].map(diabetesSuitability), ['Excellent', 'Good', 'Moderate', 'Moderate', 'Caution', 'Caution', 'Avoid']);
});

const analysis = {
  id: 'A', recipeId: 'R', lastUpdated: '2026-11-01T12:00:00Z',
  estimatedGlycemicLoad: { value: 14.5, explanation: 'Moderate load from rice.' },
  glycemicImpactFactors: [],
  carbCount: { totalCarbs: 45, netCarbs: 41, fiber: 4 },
  fiberContent: { total: 4 }, sugarBreakdown: { total: 3 },
  diabeticGuidance: [{ id: 'g', title: 'Pair with protein', summary: 'Slows absorption', detailedExplanation: 'Longer text', icon: 'fork.knife', color: {}, practicalTips: ['Add dal'] }],
  substitutionSuggestions: [{ id: 's', originalIngredient: 'white rice', substitute: 'brown rice', reason: 'More fiber' }],
  sources: [
    { id: 'x', title: 'Glycemic index', organization: 'ADA', url: 'https://diabetes.org/gi', publishDate: '2024-01-01T00:00:00Z', credibilityScore: 'high' },
    { id: 'y', title: 'Bad link', url: 'javascript:alert(1)' },
  ],
  consensusLevel: 'moderateConsensus',
};

test('published analysis is normalised to what the page shows; unsafe links dropped', () => {
  const info = normDiabeticInfo(JSON.stringify(analysis));
  assert.equal(info.lastUpdated, '2026-11-01T12:00:00.000Z');
  assert.equal(info.consensusLevel, 'moderateConsensus');
  assert.deepEqual(info.glycemicLoad, { value: 14.5, explanation: 'Moderate load from rice.' });
  assert.deepEqual(info.carbs, { totalCarbs: 45, netCarbs: 41, fiber: 4 });
  assert.deepEqual(info.guidance[0].practicalTips, ['Add dal']);
  assert.equal(info.substitutions[0].substitute, 'brown rice');
  assert.equal(info.sources[0].url, 'https://diabetes.org/gi');
  assert.equal(info.sources[1].url, null);
  assert.equal(normDiabeticInfo('not json'), null);
  assert.equal(normDiabeticInfo(undefined), null);
  assert.equal(normDiabeticInfo('{}'), null);
});

test('decodeSharedRecipe reads diabeticInfoJSON; copies carry the analysis to the kept one', () => {
  const rec = (id, date, extra = {}) => ({
    recordName: id,
    fields: {
      recipeData: { value: JSON.stringify({ id, title: 'Rice', sharedDate: date, ingredientSections: [{ ingredients: [{ name: 'white rice' }] }], instructionSections: [], notes: [], ...extra }) },
    },
  });
  const withInfo = decodeSharedRecipe(rec('A', 100, { diabeticInfoJSON: JSON.stringify(analysis) }));
  const without = decodeSharedRecipe(rec('B', 200));
  assert.equal(withInfo.diabeticInfo.carbs.netCarbs, 41);
  assert.equal(without.diabeticInfo, null);
  const { kept } = collapseCopies([without, withInfo]);
  assert.equal(kept.length, 1);
  assert.equal(kept[0].id, 'B'); // newest kept
  assert.equal(kept[0].diabeticInfo.carbs.netCarbs, 41);
  const h = recipeHealth(kept[0]);
  assert.equal(h.diabetes.suitability, 'Moderate'); // white rice: high sugar 3 + refined carb 2
  assert.equal(h.fodmap.overallLevel, 'Low');
});
