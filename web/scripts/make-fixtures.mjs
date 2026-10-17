// Generates fixtures/sample.json in the exact shape CloudKit Web Services returns,
// with recipeData encoded the way Swift's JSONEncoder writes CloudKitRecipe.
// Sample content only — clearly labelled; not anyone's real recipes.
import { writeFileSync } from 'node:fs';
const swiftNow = (iso) => Date.parse(iso) / 1000 - 978307200;
const ing = (quantity, unit, name, preparation, metricQuantity, metricUnit) =>
  ({ id: crypto.randomUUID().toUpperCase(), quantity, unit, name, preparation, metricQuantity, metricUnit });
const step = (n, text) => ({ id: crypto.randomUUID().toUpperCase(), stepNumber: n, text });
const recipes = [
  { id: 'A1B2C3D4-0000-4000-8000-000000000001', title: 'Sample: Masala Chai', headerNotes: 'A sample recipe bundled with the web preview.', yield: 'Serves 2',
    ingredientSections: [{ id: crypto.randomUUID().toUpperCase(), title: null, ingredients: [
      ing('1 1/2', 'cups', 'water', null, '355', 'ml'), ing('1', 'cup', 'whole milk', null, '240', 'ml'),
      ing('2', 'tsp', 'loose black tea', null), ing('4', null, 'green cardamom pods', 'crushed'),
      ing('1', 'inch', 'fresh ginger', 'sliced', '2.5', 'cm'), ing('2', 'tsp', 'sugar', 'or to taste') ] }],
    instructionSections: [{ id: crypto.randomUUID().toUpperCase(), title: null, steps: [
      step(1, 'Bring the water, cardamom and ginger to a boil and simmer 3 minutes.'),
      step(2, 'Add the tea and simmer 1 minute.'), step(3, 'Add the milk and sugar; bring just to a boil.'), step(4, 'Strain into cups and serve hot.') ] }],
    notes: [{ id: crypto.randomUUID().toUpperCase(), type: 'tip', text: 'Let it rise to the boil twice for a stronger cup.' }],
    reference: 'Sample data', imageName: null, additionalImageNames: [], sharedByUserID: '_sample', sharedByUserName: 'Reczipes sample', sharedDate: swiftNow('2026-10-14T18:00:00Z') },
  { id: 'A1B2C3D4-0000-4000-8000-000000000002', title: 'Sample: Lemon Rice', headerNotes: null, yield: 'Serves 4',
    ingredientSections: [
      { id: crypto.randomUUID().toUpperCase(), title: 'Rice', ingredients: [ ing('1', 'cup', 'basmati rice', 'rinsed', '200', 'g'), ing('2', 'cups', 'water', null, '475', 'ml') ] },
      { id: crypto.randomUUID().toUpperCase(), title: 'Tempering', ingredients: [ ing('2', 'tbsp', 'oil'), ing('1', 'tsp', 'mustard seeds'), ing('10', null, 'curry leaves'), ing('1/4', 'tsp', 'turmeric'), ing('2', 'tbsp', 'lemon juice') ], transitionNote: 'Have everything measured before you heat the oil.' } ],
    instructionSections: [
      { id: crypto.randomUUID().toUpperCase(), title: 'Cook the rice', steps: [ step(1, 'Cook the rice in the water until tender; spread out to cool.') ] },
      { id: crypto.randomUUID().toUpperCase(), title: 'Finish', steps: [ step(1, 'Heat the oil, add mustard seeds and let them pop.'), step(2, 'Add curry leaves and turmeric, then the rice and lemon juice. Toss and salt to taste.') ] } ],
    notes: [{ id: crypto.randomUUID().toUpperCase(), type: 'substitution', text: 'Lime juice works in place of lemon.' }, { id: crypto.randomUUID().toUpperCase(), type: 'warning', text: 'Mustard seeds spatter — keep a lid handy.' }],
    reference: null, imageName: null, additionalImageNames: [], sharedByUserID: '_sample', sharedByUserName: 'Reczipes sample', sharedDate: swiftNow('2026-10-13T18:00:00Z') },
];
const rec = (recordName, r, sharedMs) => ({
  recordName, recordType: 'SharedRecipe',
  fields: {
    recipeData: { type: 'STRING', value: JSON.stringify(r) },
    title: { type: 'STRING', value: r.title },
    sharedBy: { type: 'STRING', value: r.sharedByUserID },
    sharedByName: { type: 'STRING', value: r.sharedByUserName },
    sharedDate: { type: 'TIMESTAMP', value: sharedMs },
  },
});
const older = { ...recipes[0], title: 'Sample: Masala Chai (older share)' };
const out = {
  _comment: 'SAMPLE DATA in CloudKit Web Services response shape. Regenerate with: node scripts/make-fixtures.mjs',
  SharedRecipe: [
    rec('sample-rec-1', recipes[0], Date.parse('2026-10-14T18:00:00Z')),
    rec('sample-rec-1-old', older, Date.parse('2026-09-01T18:00:00Z')),
    rec('sample-rec-2', recipes[1], Date.parse('2026-10-13T18:00:00Z')),
    { recordName: 'sample-broken', recordType: 'SharedRecipe', fields: { recipeData: { type: 'STRING', value: '{not json' } } },
  ],
  SharedRecipeBook: [{
    recordName: 'sample-book-1', recordType: 'SharedRecipeBook',
    fields: {
      bookData: { type: 'STRING', value: JSON.stringify({ id: 'B0000000-0000-4000-8000-000000000001', name: 'Sample: Weeknight Basics', bookDescription: 'A sample book.', coverImageName: null, recipeIDs: recipes.map((r) => r.id), color: '#B5562B', sharedByUserID: '_sample', sharedByUserName: 'Reczipes sample', sharedDate: swiftNow('2026-10-14T18:00:00Z'),
        // Optional book content (README "Book content")
        tableOfContents: [
          { id: 'D0000000-0000-4000-8000-000000000001', title: 'Chapter 1 — Everyday', order: 0, itemType: 'heading', itemID: 'D0000000-0000-4000-8000-000000000001' },
          ...recipes.map((r, i) => ({ id: `D0000000-0000-4000-8000-00000000001${i}`, title: r.title, order: i + 1, itemType: 'recipe', itemID: r.id })),
          { id: 'D0000000-0000-4000-8000-000000000009', title: 'The spice tin', order: 9, itemType: 'image', itemID: 'E0000000-0000-4000-8000-000000000002' },
        ],
        images: [
          { id: 'E0000000-0000-4000-8000-000000000001', title: 'Front cover', caption: null, kind: 'cover', order: 0 },
          { id: 'E0000000-0000-4000-8000-000000000002', title: 'The spice tin', caption: 'Cardamom, cumin and cloves.', kind: 'interior', order: 1 },
        ],
        glossary: [
          { id: 'F0000000-0000-4000-8000-000000000001', term: 'Cardamom', localName: 'Elchi', definition: 'Green pods of a ginger-family plant; crush lightly before use.', relatedTerms: ['Garam masala'], order: 0 },
          { id: 'F0000000-0000-4000-8000-000000000002', term: 'Ghee', localName: null, definition: 'Butter simmered until the milk solids brown, then strained.', relatedTerms: [], order: 1 },
        ],
      }) },
      bookImages: { type: 'ASSETID_LIST', value: [{ downloadURL: '/icon.svg?${f}' }, { downloadURL: '/icon.svg?${f}' }] },
      name: { type: 'STRING', value: 'Sample: Weeknight Basics' },
      sharedByName: { type: 'STRING', value: 'Reczipes sample' },
      sharedDate: { type: 'TIMESTAMP', value: Date.parse('2026-10-14T18:00:00Z') },
      recipePreviews: { type: 'STRING', value: JSON.stringify([...recipes.map((r) => ({ id: r.id, title: r.title, headerNotes: r.headerNotes, imageName: null, recipeYield: r.yield })), { id: 'C0000000-0000-4000-8000-00000000000F', title: 'Sample: A recipe in the book that is not shared', headerNotes: null, imageName: null, recipeYield: null }]) },
    },
  }],
};
writeFileSync(new URL('../fixtures/sample.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
console.log('wrote fixtures/sample.json');
