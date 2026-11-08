// Generates lib/health-data.js from the app's own Swift tables, so the web shows
// exactly the FODMAP and diabetes information the iOS/macOS app shows:
//   Reczipes2/Models/FODMAPSubstitution.swift  FODMAPSubstitutionDatabase.allSubstitutions
//   Reczipes2/Models/FODMAPAnalyzer.swift      FODMAPFoodData.highFODMAPFoods + match exceptions
//   Reczipes2/Models/DiabetesAnalyzer.swift    keyword lists
// Run from web/:  node scripts/gen-health-data.mjs
// Never edit lib/health-data.js by hand: change the Swift table and re-run this.
// test/health.test.js fails when the generated file and the Swift source disagree.

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
export const SWIFT_MODELS = join(here, '..', '..', 'Reczipes2', 'Models');
export const OUT = join(here, '..', 'lib', 'health-data.js');

const CATEGORY = {
  oligosaccharides: 'Oligosaccharides',
  disaccharides: 'Disaccharides',
  monosaccharides: 'Monosaccharides',
  polyols: 'Polyols',
};
const CONFIDENCE = { high: 'Recommended', medium: 'Good Alternative', low: 'Limited Option' };
const LEVEL = { low: 'Low', moderate: 'Moderate', high: 'High' };

const strArg = (block, label) => {
  const m = block.match(new RegExp(`\\b${label}:\\s*"([^"]*)"`));
  return m ? m[1] : null;
};
const enumList = (src, map) => [...src.matchAll(/\.(\w+)/g)].map((m) => {
  if (!(m[1] in map)) throw new Error(`unknown enum case .${m[1]}`);
  return map[m[1]];
});

// Splits `text` at each `Name(` and returns the balanced-paren argument text of each call.
function calls(text, name) {
  const out = [];
  const re = new RegExp(`\\b${name}\\(`, 'g');
  let m;
  while ((m = re.exec(text))) {
    let depth = 1;
    let i = re.lastIndex;
    let inStr = false;
    for (; i < text.length && depth > 0; i++) {
      const c = text[i];
      if (c === '"') inStr = !inStr;
      else if (!inStr && c === '(') depth++;
      else if (!inStr && c === ')') depth--;
    }
    out.push(text.slice(re.lastIndex, i - 1));
    re.lastIndex = i;
  }
  return out;
}

function between(text, startMarker, endMarker) {
  const s = text.indexOf(startMarker);
  if (s < 0) throw new Error(`marker not found: ${startMarker}`);
  const e = text.indexOf(endMarker, s + startMarker.length);
  if (e < 0) throw new Error(`end marker not found after: ${startMarker}`);
  return text.slice(s + startMarker.length, e);
}

export function parseSubstitutions(swift) {
  const body = between(swift, 'private var allSubstitutions: [FODMAPSubstitution] {', '\n    }\n}');
  return calls(body, 'FODMAPSubstitution').map((block) => {
    const subsText = between(block, 'substitutes: [', '\n                ],');
    const catText = block.match(/fodmapCategories:\s*\[([^\]]*)\]/)[1];
    const substitutes = calls(subsText, 'SubstituteOption').map((s) => {
      const conf = s.match(/confidence:\s*\.(\w+)/);
      return {
        name: strArg(s, 'name'),
        quantity: strArg(s, 'quantity'),
        notes: strArg(s, 'notes'),
        confidence: CONFIDENCE[conf ? conf[1] : 'high'],
      };
    });
    const afterSubs = block.slice(block.indexOf(subsText) + subsText.length);
    return {
      originalIngredient: strArg(block, 'originalIngredient'),
      fodmapCategories: enumList(catText, CATEGORY),
      substitutes,
      explanation: strArg(afterSubs, 'explanation'),
      portionNote: strArg(afterSubs, 'portionNote'),
    };
  });
}

export function parseFoods(swift) {
  const body = between(swift, 'static let highFODMAPFoods: [FODMAPFoodData] = [', '\n    ]');
  return calls(body, 'FODMAPFoodData').map((b) => ({
    name: strArg(b, 'name'),
    categories: enumList(b.match(/categories:\s*\[([^\]]*)\]/)[1], CATEGORY),
    level: LEVEL[b.match(/level:\s*\.(\w+)/)[1]],
    servingSize: strArg(b, 'servingSize'),
    notes: strArg(b, 'notes'),
  }));
}

export function parseFoodExceptions(swift) {
  const body = between(swift, 'let exceptions: [String: [String]] = [', '\n        ]');
  const out = {};
  for (const m of body.matchAll(/"([^"]+)":\s*\[([^\]]*)\]/g)) {
    out[m[1]] = [...m[2].matchAll(/"([^"]*)"/g)].map((x) => x[1]);
  }
  return out;
}

function stringArray(swift, name) {
  const body = between(swift, `private let ${name} = [`, '\n    ]');
  return [...body.replace(/\/\/[^\n]*/g, '').matchAll(/"([^"]*)"/g)].map((m) => m[1]);
}

export function parseDiabetes(swift) {
  return {
    highSugar: stringArray(swift, 'highSugarKeywords'),
    refinedCarb: stringArray(swift, 'refinedCarbKeywords'),
    beneficial: stringArray(swift, 'beneficialKeywords'),
  };
}

export function buildData(dir = SWIFT_MODELS) {
  const read = (f) => readFileSync(join(dir, f), 'utf8');
  const analyzer = read('FODMAPAnalyzer.swift');
  return {
    fodmapSubstitutions: parseSubstitutions(read('FODMAPSubstitution.swift')),
    fodmapFoods: parseFoods(analyzer),
    fodmapFoodExceptions: parseFoodExceptions(analyzer),
    diabetesKeywords: parseDiabetes(read('DiabetesAnalyzer.swift')),
  };
}

export function render(data) {
  const j = (v) => JSON.stringify(v, null, 2);
  return `// GENERATED by scripts/gen-health-data.mjs from the app's Swift tables
// (Reczipes2/Models/FODMAPSubstitution.swift, FODMAPAnalyzer.swift, DiabetesAnalyzer.swift).
// Do not edit: change the Swift source and re-run the generator.

export const FODMAP_SUBSTITUTIONS = ${j(data.fodmapSubstitutions)};

export const FODMAP_FOODS = ${j(data.fodmapFoods)};

export const FODMAP_FOOD_EXCEPTIONS = ${j(data.fodmapFoodExceptions)};

export const DIABETES_KEYWORDS = ${j(data.diabetesKeywords)};
`;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const data = buildData();
  writeFileSync(OUT, render(data));
  console.log(
    `wrote ${OUT}: ${data.fodmapSubstitutions.length} substitutions, ${data.fodmapFoods.length} foods, ` +
      `${Object.keys(data.fodmapFoodExceptions).length} exception lists, ` +
      `${Object.values(data.diabetesKeywords).map((a) => a.length).join('/')} diabetes keywords`,
  );
}
