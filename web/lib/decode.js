// Turns CloudKit Web Services record dictionaries into the plain recipe/book
// objects the browser renders.
//
// The data contract is set by the Swift app, not by this file:
//   SharedRecipe.recipeData        JSON of CloudKitRecipe   (Reczipes2/Models/SharedContentModels.swift)
//   SharedRecipe.mainImage         CKAsset
//   SharedRecipeBook.bookData      JSON of CloudKitRecipeBook
//   SharedRecipeBook.recipePreviews JSON of [RecipePreviewData] (Reczipes2/Views/CloudKitRecipePreview.swift)
//   SharedRecipeBook.coverImage    CKAsset
// Sections/ingredients/steps/notes come from Reczipes2/Models/RecipeDisplayItem.swift.

// Swift's JSONEncoder default date strategy (.deferredToDate) writes seconds
// since 2001-01-01T00:00:00Z. CloudKit TIMESTAMP fields arrive as ms since 1970.
const APPLE_EPOCH_OFFSET_S = 978307200;

export function swiftDateToISO(value) {
  if (value == null) return null;
  if (typeof value === 'number') {
    return new Date((value + APPLE_EPOCH_OFFSET_S) * 1000).toISOString();
  }
  if (typeof value === 'string') {
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
  }
  return null;
}

function fieldValue(record, name) {
  const f = record?.fields?.[name];
  return f ? f.value : undefined;
}

function parseJSONField(record, name) {
  const raw = fieldValue(record, name);
  if (typeof raw !== 'string' || raw.length === 0) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

// CloudKit asset downloadURLs carry a ${f} placeholder for the file name.
export function assetURL(record, name) {
  const asset = fieldValue(record, name);
  const url = asset?.downloadURL;
  if (typeof url !== 'string') return null;
  return url.replace('${f}', encodeURIComponent(name + '.jpg'));
}

const str = (v) => (typeof v === 'string' && v.trim().length > 0 ? v.trim() : null);
const NOTE_TYPES = new Set(['tip', 'substitution', 'warning', 'timing', 'general']);

function normIngredient(i) {
  if (!i || typeof i !== 'object') return null;
  const name = str(i.name);
  if (!name) return null;
  return {
    quantity: str(i.quantity),
    unit: str(i.unit),
    name,
    preparation: str(i.preparation),
    metricQuantity: str(i.metricQuantity),
    metricUnit: str(i.metricUnit),
  };
}

function normIngredientSection(s) {
  if (!s || typeof s !== 'object') return null;
  const ingredients = (Array.isArray(s.ingredients) ? s.ingredients : []).map(normIngredient).filter(Boolean);
  const transitionNote = str(s.transitionNote);
  if (ingredients.length === 0 && !transitionNote) return null;
  return { title: str(s.title), ingredients, transitionNote };
}

function normInstructionSection(s) {
  if (!s || typeof s !== 'object') return null;
  const steps = (Array.isArray(s.steps) ? s.steps : [])
    .filter((st) => st && str(st.text))
    .map((st, idx) => ({ n: Number.isInteger(st.stepNumber) ? st.stepNumber : idx + 1, text: st.text.trim() }))
    .sort((a, b) => a.n - b.n);
  if (steps.length === 0) return null;
  return { title: str(s.title), steps };
}

function normNote(n) {
  if (!n || typeof n !== 'object' || !str(n.text)) return null;
  return { type: NOTE_TYPES.has(n.type) ? n.type : 'general', text: n.text.trim() };
}

// A SharedRecipe record -> recipe object, or null if the record is unusable.
export function decodeSharedRecipe(record) {
  if (!record || record.serverErrorCode) return null;
  const data = parseJSONField(record, 'recipeData');
  if (!data) return null;
  const title = str(data.title) ?? str(fieldValue(record, 'title'));
  if (!title) return null;

  const sharedDateField = fieldValue(record, 'sharedDate');
  const sharedDate =
    typeof sharedDateField === 'number'
      ? new Date(sharedDateField).toISOString()
      : swiftDateToISO(data.sharedDate);

  return {
    recordName: record.recordName,
    id: str(data.id) ?? record.recordName,
    title,
    headerNotes: str(data.headerNotes),
    yield: str(data.yield),
    reference: str(data.reference),
    ingredientSections: (Array.isArray(data.ingredientSections) ? data.ingredientSections : [])
      .map(normIngredientSection)
      .filter(Boolean),
    instructionSections: (Array.isArray(data.instructionSections) ? data.instructionSections : [])
      .map(normInstructionSection)
      .filter(Boolean),
    notes: (Array.isArray(data.notes) ? data.notes : []).map(normNote).filter(Boolean),
    sharedByName: str(fieldValue(record, 'sharedByName')) ?? str(data.sharedByUserName),
    sharedDate,
    imageURL: assetURL(record, 'mainImage'),
  };
}

export function decodeSharedBook(record) {
  if (!record || record.serverErrorCode) return null;
  const data = parseJSONField(record, 'bookData');
  if (!data) return null;
  const name = str(data.name) ?? str(fieldValue(record, 'name'));
  if (!name) return null;
  const previews = parseJSONField(record, 'recipePreviews');

  const sharedDateField = fieldValue(record, 'sharedDate');
  return {
    recordName: record.recordName,
    id: str(data.id) ?? record.recordName,
    name,
    description: str(data.bookDescription),
    color: str(data.color),
    recipeIDs: (Array.isArray(data.recipeIDs) ? data.recipeIDs : []).filter((x) => typeof x === 'string'),
    previews: (Array.isArray(previews) ? previews : [])
      .filter((p) => p && str(p.title))
      .map((p) => ({ id: str(p.id), title: p.title.trim(), headerNotes: str(p.headerNotes), yield: str(p.recipeYield) })),
    sharedByName: str(fieldValue(record, 'sharedByName')) ?? str(data.sharedByUserName),
    sharedDate:
      typeof sharedDateField === 'number' ? new Date(sharedDateField).toISOString() : swiftDateToISO(data.sharedDate),
    coverURL: assetURL(record, 'coverImage'),
  };
}

// The list view needs a light summary, not the whole recipe.
export function summarize(recipe) {
  const ingredientNames = recipe.ingredientSections.flatMap((s) => s.ingredients.map((i) => i.name));
  return {
    id: recipe.id,
    title: recipe.title,
    yield: recipe.yield,
    headerNotes: recipe.headerNotes,
    sharedByName: recipe.sharedByName,
    sharedDate: recipe.sharedDate,
    imageURL: recipe.imageURL,
    ingredientCount: ingredientNames.length,
    // Lower-cased haystack for client-side search by title or ingredient.
    search: [recipe.title, recipe.headerNotes ?? '', ...ingredientNames].join(' \u0001 ').toLowerCase(),
  };
}

// The app can share the same recipe more than once (the Swift side tries to
// de-dupe, but older records exist). Keep the newest record per recipe id.
// This is a read-side view only — nothing is ever deleted (Lane 37 rule 1).
export function newestPerId(items) {
  const byId = new Map();
  for (const it of items) {
    const prev = byId.get(it.id);
    if (!prev || (it.sharedDate ?? '') > (prev.sharedDate ?? '')) byId.set(it.id, it);
  }
  return [...byId.values()];
}
