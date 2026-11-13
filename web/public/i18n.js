// Interface language for the web reader: English or French, chosen from the flag in the
// header (same choice as the app's toolbar flag). Recipe content is the owner's text and is
// never translated. Keys are the English text; {name} marks a value filled in at run time.

export const LANGUAGES = [
  { code: 'en', flag: '🇺🇸', name: 'English' },
  { code: 'fr', flag: '🇫🇷', name: 'Français' },
];

const FR = {
  // header, footer, page shell
  'Skip to content': 'Aller au contenu',
  'Reczipes home': 'Accueil Reczipes',
  'Sections': 'Sections',
  'Recipes': 'Recettes',
  'Books': 'Livres',
  'Loading recipes…': 'Chargement des recettes…',
  'Recipes shared from the Reczipes app for iPhone, iPad and Mac.': "Recettes partagées depuis l'app Reczipes pour iPhone, iPad et Mac.",
  'Language': 'Langue',
  'Language: {name}': 'Langue : {name}',
  // status
  'All recipes': 'Toutes les recettes',
  'That recipe isn’t available.': 'Cette recette n’est pas disponible.',
  'Recipes couldn’t be loaded right now.': 'Les recettes n’ont pas pu être chargées pour le moment.',
  'Back to all recipes': 'Retour à toutes les recettes',
  'Preview mode: these are sample recipes. Live recipes from the app appear once the site is connected to iCloud.':
    "Mode aperçu : ce sont des recettes d'exemple. Les vraies recettes de l'app apparaîtront une fois le site connecté à iCloud.",
  'Showing sample data.': "Données d'exemple affichées.",
  'Couldn’t refresh from iCloud just now; showing recipes as of {date}.': 'Impossible d’actualiser depuis iCloud pour le moment ; recettes affichées au {date}.',
  'earlier': 'précédemment',
  'Updated {date}.': 'Mis à jour le {date}.',
  // recipe list
  '{n} ingredients': '{n} ingrédients',
  'Search by recipe or ingredient': 'Rechercher par recette ou ingrédient',
  'Search recipes': 'Rechercher des recettes',
  '{hits} of {total} recipes': '{hits} sur {total} recettes',
  '{n} recipe': '{n} recette',
  '{n} recipes': '{n} recettes',
  'No recipes match that search.': 'Aucune recette ne correspond à cette recherche.',
  'No recipes have been shared yet.': "Aucune recette n'a encore été partagée.",
  // recipe page
  'Tip': 'Astuce',
  'Substitution': 'Substitution',
  'Warning': 'Mise en garde',
  'Timing': 'Durée',
  'Note': 'Note',
  'Ingredients': 'Ingrédients',
  'Metric': 'Métrique',
  'Keep screen on': "Garder l'écran allumé",
  'Shared by {name}': 'Partagée par {name}',
  'Print': 'Imprimer',
  'Method': 'Préparation',
  'Source: ': 'Source : ',
  'Show': 'Afficher',
  'Hide': 'Masquer',
  // FODMAP
  'FODMAP substitute available': 'Substitut FODMAP disponible',
  '⇄ FODMAP substitute': '⇄ Substitut FODMAP',
  'FODMAP Friendly Options': 'Options adaptées aux FODMAP',
  '✓ This recipe is already low FODMAP!': '✓ Cette recette est déjà pauvre en FODMAP !',
  '{n} ingredient can be substituted': '{n} ingrédient peut être remplacé',
  '{n} ingredients can be substituted': '{n} ingrédients peuvent être remplacés',
  'Substitute with:': 'Remplacer par :',
  'Low': 'Faible',
  'Moderate': 'Modéré',
  'High': 'Élevé',
  'Recommended': 'Recommandé',
  'Good Alternative': 'Bonne alternative',
  'Limited Option': 'Option limitée',
  'Oligosaccharides': 'Oligosaccharides',
  'Disaccharides': 'Disaccharides',
  'Monosaccharides': 'Monosaccharides',
  'Polyols': 'Polyols',
  // diabetes
  'Diabetic-Friendly Analysis': 'Analyse adaptée au diabète',
  'Informational Only. ': 'À titre informatif uniquement. ',
  'This analysis is not medical advice. Consult your healthcare provider.': "Cette analyse n'est pas un avis médical. Consultez votre médecin.",
  'Ingredient check': 'Vérification des ingrédients',
  'Higher sugar or refined carbs: ': 'Sucres ou glucides raffinés : ',
  'Helpful: ': 'Favorables : ',
  'Excellent': 'Excellent',
  'Good': 'Bon',
  'Caution': 'Prudence',
  'Avoid': 'À éviter',
  'Verified': 'Vérifié',
  'Limited': 'Limité',
  'Review': 'À revoir',
  'Medium': 'Moyen',
  'Glycemic Impact': 'Impact glycémique',
  'Glycemic load {n} of 30': 'Charge glycémique {n} sur 30',
  'Carbohydrate Breakdown': 'Répartition des glucides',
  'Total Carbs': 'Glucides totaux',
  'Net Carbs': 'Glucides nets',
  'Fiber': 'Fibres',
  'Tips:': 'Astuces :',
  'Healthier Alternatives': 'Alternatives plus saines',
  'Based on {n} unverified source': 'D’après {n} source non vérifiée',
  'Based on {n} unverified sources': 'D’après {n} sources non vérifiées',
  'Suggested by Claude from memory, not looked up. Check a source before relying on it.':
    'Suggérées de mémoire par Claude, sans recherche. Vérifiez une source avant de vous y fier.',
  ' · Last updated: {date}': ' · Dernière mise à jour : {date}',
  'No Claude analysis has been published for this recipe yet. The Reczipes app adds one automatically, usually within a day.':
    'Aucune analyse Claude n’a encore été publiée pour cette recette. L’app Reczipes en ajoute une automatiquement, en général dans la journée.',
  // books
  '{n} book': '{n} livre',
  '{n} books': '{n} livres',
  'No recipes yet': 'Pas encore de recettes',
  'by {name}': 'par {name}',
  'No books have been shared yet.': "Aucun livre n'a encore été partagé.",
  'Index': 'Index',
  'Contents': 'Sommaire',
  'Pictures': 'Images',
  'Glossary': 'Glossaire',
  'This book has no recipes on the web yet.': "Ce livre n'a pas encore de recettes sur le web.",
  'Jump to letter': 'Aller à la lettre',
  'Covers': 'Couvertures',
  'Inside the book': 'Dans le livre',
  'Search the glossary': 'Rechercher dans le glossaire',
  ' See also: {terms}.': ' Voir aussi : {terms}.',
  'No glossary entries match that search.': 'Aucune entrée du glossaire ne correspond à cette recherche.',
  '{name} sections': 'Sections de {name}',
  'Search {name}': 'Rechercher dans {name}',
  '{hits} of {total}': '{hits} sur {total}',
  'No recipes in this book match that search.': 'Aucune recette de ce livre ne correspond à cette recherche.',
  'Show all {what}': 'Afficher les {what}',
  '← All books': '← Tous les livres',
};

const TABLES = { fr: FR };
const STORAGE_KEY = 'reczipes.lang';

function saved() {
  try { return localStorage.getItem(STORAGE_KEY); } catch { return null; }
}

function initial() {
  const s = saved();
  if (LANGUAGES.some((l) => l.code === s)) return s;
  return (navigator.language || 'en').toLowerCase().startsWith('fr') ? 'fr' : 'en';
}

let current = initial();

export const lang = () => current;
export const language = () => LANGUAGES.find((l) => l.code === current) ?? LANGUAGES[0];

export function setLang(code) {
  if (!LANGUAGES.some((l) => l.code === code)) return;
  current = code;
  try { localStorage.setItem(STORAGE_KEY, code); } catch { /* per-viewer convenience only */ }
  document.documentElement.lang = code;
}

/** Translate an English key; {name} placeholders are filled from vars. Unknown keys stay English. */
export function t(key, vars = {}) {
  const text = TABLES[current]?.[key] ?? key;
  return text.replace(/\{(\w+)\}/g, (m, name) => (name in vars ? String(vars[name]) : m));
}

/** Singular/plural pick by count, then translate: tn(n, '{n} recipe', '{n} recipes'). */
export const tn = (n, one, many, vars = {}) => t(n === 1 ? one : many, { n, ...vars });

/** Every key with its French text, for tests. */
export const KEYS_FR = FR;
