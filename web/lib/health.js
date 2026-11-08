// FODMAP and diabetes information for a recipe, matching what the iOS/macOS app shows.
// Each function is a line-for-line port of the Swift it names; the tables come from
// health-data.js, which scripts/gen-health-data.mjs generates from the Swift source.
//
//   fodmapSubstitutions  FODMAPSubstitutionDatabase.analyzeRecipe   (Models/FODMAPSubstitution.swift)
//   fodmapIsSafe         FODMAPAnalyzer.analyzeRecipe(...).isSafe    (Models/FODMAPAnalyzer.swift)
//   diabetesScore        DiabetesAnalyzer.analyzeRecipe              (Models/DiabetesAnalyzer.swift)
//   normDiabeticInfo     DiabeticInfo, as the app publishes it in CloudKitRecipe.diabeticInfoJSON
//
// The app's "Diabetic-Friendly Analysis" is written by Claude on the owner's device; the web
// never runs that analysis, it only shows the copy the app published.

import { FODMAP_SUBSTITUTIONS, FODMAP_FOODS, FODMAP_FOOD_EXCEPTIONS, DIABETES_KEYWORDS } from './health-data.js';

export const FODMAP_CATEGORY_ICON = {
  Oligosaccharides: '🧅',
  Disaccharides: '🥛',
  Monosaccharides: '🍯',
  Polyols: '🍎',
};

// FODMAPSubstitutionDatabase.getSubstitutions: first table entry whose name is contained
// in the ingredient name (plain substring, as in the app).
export function substitutionFor(ingredientName) {
  const lower = String(ingredientName ?? '').toLowerCase();
  return FODMAP_SUBSTITUTIONS.find((s) => lower.includes(s.originalIngredient.toLowerCase())) ?? null;
}

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const FOOD_PATTERNS = FODMAP_FOODS.map((f) => new RegExp(`\\b${escapeRe(f.name.toLowerCase())}s?\\b`, 'i'));

// FODMAPFoodData.getFODMAPData: exceptions first, then a word-boundary match.
export function fodmapFoodFor(text) {
  const lower = String(text ?? '').toLowerCase();
  const i = FODMAP_FOODS.findIndex((food, idx) => {
    const ex = FODMAP_FOOD_EXCEPTIONS[food.name.toLowerCase()];
    if (ex && ex.some((e) => lower.includes(e))) return false;
    return FOOD_PATTERNS[idx].test(lower);
  });
  return i < 0 ? null : FODMAP_FOODS[i];
}

// FODMAPAnalyzer.analyzeRecipe(...).isSafe: no ingredient name or preparation matches a
// high-FODMAP food (any match makes the total score > 0, so the recommendation is not "safe").
export function fodmapIsSafe(recipe) {
  for (const s of recipe.ingredientSections ?? []) {
    for (const i of s.ingredients ?? []) {
      if (fodmapFoodFor(i.name)) return false;
      if (i.preparation && fodmapFoodFor(i.preparation)) return false;
    }
  }
  return true;
}

// FODMAPSubstitutionDatabase.analyzeRecipe -> RecipeFODMAPSubstitutions.
export function fodmapSubstitutions(recipe) {
  const groups = [];
  (recipe.ingredientSections ?? []).forEach((section, si) => {
    (section.ingredients ?? []).forEach((ingredient, ii) => {
      const substitution = substitutionFor(ingredient.name);
      if (substitution) {
        groups.push({
          key: `${si}.${ii}`,
          sectionTitle: section.title ?? null,
          ingredient: { quantity: ingredient.quantity ?? null, unit: ingredient.unit ?? null, name: ingredient.name },
          substitution,
        });
      }
    });
  });
  const level = groups.length === 0 ? 'Low' : groups.length <= 2 ? 'Moderate' : 'High';
  return {
    substitutions: groups,
    overallLevel: level,
    isSafeWithoutSubstitutions: fodmapIsSafe(recipe),
    hasSubstitutions: groups.length > 0,
  };
}

// DiabetesAnalyzer.extractIngredientNames: name, then preparation, then unit.
function diabetesTerms(recipe) {
  const names = [];
  for (const s of recipe.ingredientSections ?? []) {
    for (const i of s.ingredients ?? []) {
      names.push(i.name);
      if (i.preparation) names.push(i.preparation);
      if (i.unit) names.push(i.unit);
    }
  }
  return names;
}

function findMatches(terms, keywords) {
  const matches = [];
  for (const t of terms) {
    const lower = String(t).toLowerCase();
    if (keywords.some((k) => lower.includes(k.toLowerCase())) && !matches.includes(t)) matches.push(t);
  }
  return matches;
}

export function diabetesSuitability(score) {
  if (score === 0) return 'Excellent';
  if (score <= 3) return 'Good';
  if (score <= 6) return 'Moderate';
  if (score <= 10) return 'Caution';
  return 'Avoid';
}

// DiabetesAnalyzer.analyzeRecipe -> DiabetesScore.
export function diabetesScore(recipe) {
  const terms = diabetesTerms(recipe);
  const highSugar = findMatches(terms, DIABETES_KEYWORDS.highSugar);
  const refinedCarb = findMatches(terms, DIABETES_KEYWORDS.refinedCarb);
  const beneficial = findMatches(terms, DIABETES_KEYWORDS.beneficial);
  const riskScore = Math.max(0, highSugar.length * 3 + refinedCarb.length * 2 - beneficial.length);
  const suitability = diabetesSuitability(riskScore);
  return {
    riskScore,
    suitability,
    isDiabeticFriendly: suitability === 'Excellent' || suitability === 'Good',
    highSugarIngredients: highSugar,
    refinedCarbIngredients: refinedCarb,
    beneficialIngredients: beneficial,
  };
}

// ---------- Published Diabetic-Friendly Analysis ----------

const s = (v) => (typeof v === 'string' && v.trim() ? v.trim() : null);
const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
const arr = (v) => (Array.isArray(v) ? v : []);
const CONSENSUS = new Set(['strongConsensus', 'moderateConsensus', 'limitedEvidence', 'needsReview']);
const CREDIBILITY = new Set(['high', 'medium', 'low']);
const APPLE_EPOCH_OFFSET_S = 978307200;

// The app encodes the cached analysis with ISO-8601 dates; tolerate Swift's default
// (seconds since 2001) too.
function dateISO(v) {
  if (typeof v === 'number') return new Date((v + APPLE_EPOCH_OFFSET_S) * 1000).toISOString();
  if (typeof v === 'string') {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
  }
  return null;
}

const httpURL = (v) => (typeof v === 'string' && /^https?:\/\/\S+$/i.test(v.trim()) ? v.trim() : null);

// CloudKitRecipe.diabeticInfoJSON (a JSON string of DiabeticInfo) -> what the page renders,
// or null when absent or unusable. Only the parts the app's DiabeticInfoView shows are kept.
export function normDiabeticInfo(raw) {
  if (typeof raw !== 'string' || raw.length === 0) return null;
  let d;
  try {
    d = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!d || typeof d !== 'object') return null;
  const carbs = d.carbCount && typeof d.carbCount === 'object' ? d.carbCount : null;
  const load = d.estimatedGlycemicLoad && num(d.estimatedGlycemicLoad.value) != null
    ? { value: d.estimatedGlycemicLoad.value, explanation: s(d.estimatedGlycemicLoad.explanation) }
    : null;
  const info = {
    lastUpdated: dateISO(d.lastUpdated),
    consensusLevel: CONSENSUS.has(d.consensusLevel) ? d.consensusLevel : 'needsReview',
    glycemicLoad: load,
    carbs: carbs
      ? { totalCarbs: num(carbs.totalCarbs) ?? 0, netCarbs: num(carbs.netCarbs) ?? 0, fiber: num(carbs.fiber) ?? 0 }
      : null,
    guidance: arr(d.diabeticGuidance)
      .filter((g) => g && s(g.title))
      .map((g) => ({
        title: s(g.title),
        summary: s(g.summary),
        detailedExplanation: s(g.detailedExplanation),
        practicalTips: arr(g.practicalTips).map(s).filter(Boolean),
      })),
    substitutions: arr(d.substitutionSuggestions)
      .filter((x) => x && s(x.originalIngredient) && s(x.substitute))
      .map((x) => ({ originalIngredient: s(x.originalIngredient), substitute: s(x.substitute), reason: s(x.reason) })),
    sources: arr(d.sources)
      .filter((x) => x && s(x.title))
      .map((x) => ({
        title: s(x.title),
        organization: s(x.organization),
        url: httpURL(x.url),
        publishDate: dateISO(x.publishDate),
        credibility: CREDIBILITY.has(x.credibilityScore) ? x.credibilityScore : null,
      })),
  };
  if (!info.glycemicLoad && !info.carbs && info.guidance.length === 0 && info.substitutions.length === 0) return null;
  return info;
}

// Everything the recipe page needs, computed once per recipe.
export function recipeHealth(recipe) {
  return {
    fodmap: fodmapSubstitutions(recipe),
    diabetes: diabetesScore(recipe),
    diabeticInfo: recipe.diabeticInfo ?? null,
  };
}
