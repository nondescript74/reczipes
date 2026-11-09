// Amounts for readers who measure in metric. Used only where a recipe has no
// translation yet (a translated recipe's amounts are already in the reader's units)
// and the app gave no metricQuantity for the ingredient.

const VOLUME_ML = new Map([
  ['cup', 240], ['cups', 240], ['c', 240], ['c.', 240],
  ['fl oz', 30], ['fl. oz.', 30], ['fluid ounce', 30], ['fluid ounces', 30],
  ['pint', 475], ['pints', 475], ['pt', 475],
  ['quart', 950], ['quarts', 950], ['qt', 950],
  ['gallon', 3785], ['gallons', 3785], ['gal', 3785],
]);
const WEIGHT_G = new Map([
  ['oz', 28], ['oz.', 28], ['ounce', 28], ['ounces', 28],
  ['lb', 450], ['lb.', 450], ['lbs', 450], ['lbs.', 450], ['pound', 450], ['pounds', 450],
]);
// Spoons are metric already (15 ml, 5 ml); each language names them its own way.
const UNIT_WORDS = {
  fr: new Map([
    ['tbsp', 'c. à soupe'], ['tbsp.', 'c. à soupe'], ['tablespoon', 'c. à soupe'], ['tablespoons', 'c. à soupe'], ['tbs', 'c. à soupe'], ['T', 'c. à soupe'],
    ['tsp', 'c. à café'], ['tsp.', 'c. à café'], ['teaspoon', 'c. à café'], ['teaspoons', 'c. à café'], ['t', 'c. à café'],
    ['pinch', 'pincée'], ['pinches', 'pincées'], ['dash', 'trait'], ['clove', 'gousse'], ['cloves', 'gousses'],
    ['slice', 'tranche'], ['slices', 'tranches'], ['can', 'boîte'], ['cans', 'boîtes'], ['bunch', 'botte'],
  ]),
};

const FRACTIONS = { '¼': 0.25, '½': 0.5, '¾': 0.75, '⅓': 1 / 3, '⅔': 2 / 3, '⅛': 0.125, '⅜': 0.375, '⅝': 0.625, '⅞': 0.875 };

// "2", "2½", "2 ½", "1 1/2", "1/2", "1.5", "1,5" -> number; anything else -> null.
export function parseAmount(text) {
  if (typeof text !== 'string') return null;
  let s = text.trim().replace(',', '.');
  if (!s) return null;
  let total = 0;
  const frac = s.match(/[¼½¾⅓⅔⅛⅜⅝⅞]$/);
  if (frac) {
    total += FRACTIONS[frac[0]];
    s = s.slice(0, -1).trim();
    if (!s) return total;
  }
  let m = s.match(/^(\d+)\s+(\d+)\/(\d+)$/);
  if (m) return total + Number(m[1]) + Number(m[2]) / Number(m[3]);
  m = s.match(/^(\d+)\/(\d+)$/);
  if (m) return total + Number(m[1]) / Number(m[2]);
  m = s.match(/^\d+(\.\d+)?$/);
  if (m) return total + Number(s);
  return null;
}

// Rounded to what a cook measures: 5s under 250, 25s above, kilos/litres from 1000.
function round(v) {
  if (v < 250) return Math.max(5, Math.round(v / 5) * 5);
  return Math.round(v / 25) * 25;
}

function fmt(n, locale) {
  return new Intl.NumberFormat(locale, { maximumFractionDigits: 2 }).format(n);
}

// One amount ("2½", "2-3") in a metric unit, or null when it can't be converted.
export function toMetric(quantity, unit, locale = 'fr') {
  const u = (unit ?? '').trim().toLowerCase();
  const per = VOLUME_ML.get(u) ?? WEIGHT_G.get(u);
  if (!per) return null;
  const base = VOLUME_ML.has(u) ? 'ml' : 'g';
  const parts = String(quantity ?? '').split(/\s*(?:-|–|to|à)\s*/);
  if (parts.length > 2) return null;
  const values = parts.map(parseAmount);
  if (values.some((v) => v == null || v <= 0)) return null;
  const big = base === 'ml' ? 'l' : 'kg';
  const scaled = values.map((v) => round(v * per));
  if (scaled.every((v) => v >= 1000)) {
    return { quantity: scaled.map((v) => fmt(v / 1000, locale)).join('–'), unit: big };
  }
  return { quantity: scaled.map((v) => fmt(v, locale)).join('–'), unit: base };
}

// A unit word in the reader's language, where there is one; otherwise as written.
export function unitWord(unit, lang) {
  if (!unit) return unit;
  const words = UNIT_WORDS[lang];
  return words?.get(unit.trim()) ?? words?.get(unit.trim().toLowerCase()) ?? unit;
}
