// Reczipes web reader. No framework, no build step.
// All recipe text is user content from a public database: it is only ever
// placed into the page with textContent (via h()), never as HTML.

const main = document.getElementById('main');
const banner = document.getElementById('banner');
const sourceEl = document.getElementById('source');

function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat(Infinity)) {
    if (c == null || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}

let backTo = { href: '#/', label: 'All recipes' };
const cache = new Map();
async function getJSON(url) {
  if (cache.has(url)) return cache.get(url);
  const p = fetch(url).then(async (res) => {
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw Object.assign(new Error(body.error || `HTTP ${res.status}`), { status: res.status });
    return body;
  });
  cache.set(url, p);
  p.catch(() => cache.delete(url));
  return p;
}

function store(key, value) {
  try {
    if (value === undefined) return localStorage.getItem(key);
    localStorage.setItem(key, value);
  } catch {
    return null;
  }
}

const fmtDate = (iso) => {
  if (!iso) return null;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : d.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
};

function setTab(name) {
  for (const a of document.querySelectorAll('.tabs a')) {
    if (a.dataset.tab === name) a.setAttribute('aria-current', 'page');
    else a.removeAttribute('aria-current');
  }
}

function render(...nodes) {
  main.replaceChildren(...nodes);
}

function errorView(err) {
  return h('div', { class: 'empty' },
    h('p', {}, err.status === 404 ? 'That recipe isn’t available.' : 'Recipes couldn’t be loaded right now.'),
    h('p', {}, h('a', { href: '#/' }, 'Back to all recipes')));
}

// ---------- Status banner ----------
async function loadStatus() {
  try {
    const s = await getJSON('/api/status');
    if (s.source === 'fixtures') {
      banner.replaceChildren(h('p', { class: 'banner' },
        'Preview mode: these are sample recipes. Live recipes from the app appear once the site is connected to iCloud.'));
      sourceEl.textContent = 'Showing sample data.';
    } else {
      if (s.lastError) {
        banner.replaceChildren(h('p', { class: 'banner' },
          `Couldn’t refresh from iCloud just now; showing recipes as of ${fmtDate(s.loadedAt) ?? 'earlier'}.`));
      }
      sourceEl.textContent = s.loadedAt ? `Updated ${new Date(s.loadedAt).toLocaleString()}.` : '';
    }
  } catch {
    /* status is advisory */
  }
}

// ---------- Recipe list ----------
const searchIcon = () => {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  svg.innerHTML = '<circle cx="11" cy="11" r="7" fill="none" stroke="currentColor" stroke-width="2"/><path d="M20 20l-4-4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>';
  return svg;
};

function recipeCard(r) {
  return h('li', {},
    h('a', { class: 'card', href: `#/recipe/${encodeURIComponent(r.id)}` },
      r.imageURL
        ? h('img', { class: 'card__img', src: r.imageURL, alt: '', loading: 'lazy' })
        : h('div', { class: 'card__ph', 'aria-hidden': 'true' }, r.title.replace(/^sample:\s*/i, '').charAt(0).toUpperCase()),
      h('div', { class: 'card__body' },
        h('h2', { class: 'card__title' }, r.title),
        h('span', { class: 'card__meta' }, [r.yield, r.ingredientCount ? `${r.ingredientCount} ingredients` : null].filter(Boolean).join(' · ')))));
}

async function showRecipes(query = '') {
  setTab('recipes');
  backTo = { href: '#/', label: 'All recipes' };
  document.title = 'Recipes · Reczipes';
  let recipes;
  try {
    recipes = await getJSON('/api/recipes');
  } catch (e) {
    return render(errorView(e));
  }
  const list = h('ul', { class: 'grid' });
  const count = h('p', { class: 'muted' });
  const input = h('input', {
    type: 'search', placeholder: 'Search by recipe or ingredient', 'aria-label': 'Search recipes',
    value: query, autocomplete: 'off',
  });
  const apply = () => {
    const terms = input.value.toLowerCase().split(/\s+/).filter(Boolean);
    const hits = recipes.filter((r) => terms.every((t) => r.search.includes(t)));
    list.replaceChildren(...hits.map(recipeCard));
    count.textContent = terms.length
      ? `${hits.length} of ${recipes.length} recipes`
      : `${recipes.length} recipe${recipes.length === 1 ? '' : 's'}`;
    if (!hits.length) list.replaceChildren(h('li', { class: 'empty' }, terms.length ? 'No recipes match that search.' : 'No recipes have been shared yet.'));
    const q = input.value.trim();
    history.replaceState(null, '', q ? `#/?q=${encodeURIComponent(q)}` : '#/');
  };
  input.addEventListener('input', apply);
  render(
    h('div', { class: 'page-head' }, h('h1', {}, 'Recipes'), count),
    h('div', { class: 'search' }, searchIcon(), input),
    list,
  );
  apply();
}

// ---------- Recipe detail ----------
function qtyText(i, metric) {
  const useMetric = metric && i.metricQuantity;
  const q = useMetric ? i.metricQuantity : i.quantity;
  const u = useMetric ? i.metricUnit : i.unit;
  return [q, u].filter(Boolean).join(' ');
}

const NOTE_LABEL = { tip: 'Tip', substitution: 'Substitution', warning: 'Warning', timing: 'Timing', general: 'Note' };

function toggleDone(e) {
  const li = e.currentTarget;
  li.classList.toggle('done');
  li.setAttribute('aria-checked', li.classList.contains('done'));
}

let wakeLock = null;
async function setWakeLock(on, btn) {
  try {
    if (on) {
      wakeLock = await navigator.wakeLock.request('screen');
      wakeLock.addEventListener('release', () => btn.setAttribute('aria-pressed', 'false'));
    } else if (wakeLock) {
      await wakeLock.release();
      wakeLock = null;
    }
    btn.setAttribute('aria-pressed', String(on));
  } catch {
    btn.setAttribute('aria-pressed', 'false');
  }
}

async function showRecipe(id) {
  setTab('recipes');
  let r;
  try {
    r = await getJSON(`/api/recipes/${encodeURIComponent(id)}`);
  } catch (e) {
    return render(h('a', { class: 'back', href: backTo.href }, `← ${backTo.label}`), errorView(e));
  }
  document.title = `${r.title} · Reczipes`;

  const hasMetric = r.ingredientSections.some((s) => s.ingredients.some((i) => i.metricQuantity));
  let metric = hasMetric && store('reczipes.metric') === '1';
  // Ticked-off ingredients survive a redraw (e.g. switching to metric).
  const doneIng = new Set();
  const toggleIng = (e) => {
    toggleDone(e);
    const k = e.currentTarget.dataset.key;
    if (e.currentTarget.classList.contains('done')) doneIng.add(k); else doneIng.delete(k);
  };
  const ingPanel = h('section', { class: 'panel ingredients-panel', 'aria-labelledby': 'ing-h' });

  const drawIngredients = () => {
    ingPanel.replaceChildren(...[
      h('h2', { id: 'ing-h' }, 'Ingredients'),
      r.ingredientSections.map((s, si) => [
        s.title ? h('h3', {}, s.title) : null,
        h('ul', { class: 'ingredients' }, s.ingredients.map((i, ii) =>
          h('li', { class: doneIng.has(`${si}.${ii}`) ? 'done' : null, 'data-key': `${si}.${ii}`, role: 'checkbox', 'aria-checked': String(doneIng.has(`${si}.${ii}`)), tabindex: '0', onclick: toggleIng, onkeydown: (e) => { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); toggleIng(e); } } },
            qtyText(i, metric) ? h('span', { class: 'qty' }, qtyText(i, metric) + ' ') : null,
            i.name,
            i.preparation ? h('span', { class: 'prep' }, `, ${i.preparation}`) : null))),
        s.transitionNote ? h('p', { class: 'transition' }, s.transitionNote) : null,
      ]),
    ].flat(Infinity).filter(Boolean));
  };
  drawIngredients();

  const metricBtn = hasMetric
    ? h('button', { class: 'btn', type: 'button', 'aria-pressed': String(metric), onclick: () => {
        metric = !metric;
        store('reczipes.metric', metric ? '1' : '0');
        metricBtn.setAttribute('aria-pressed', String(metric));
        drawIngredients();
      } }, 'Metric')
    : null;
  const wakeBtn = 'wakeLock' in navigator
    ? h('button', { class: 'btn', type: 'button', 'aria-pressed': 'false', onclick: (e) => setWakeLock(e.currentTarget.getAttribute('aria-pressed') !== 'true', e.currentTarget) }, 'Keep screen on')
    : null;

  const facts = [r.yield, r.sharedByName ? `Shared by ${r.sharedByName}` : null, fmtDate(r.sharedDate)].filter(Boolean);

  render(
    h('a', { class: 'back', href: backTo.href }, `← ${backTo.label}`),
    h('article', {},
      h('header', { class: `recipe-hero${r.imageURL ? ' has-img' : ''}` },
        r.imageURL ? h('img', { src: r.imageURL, alt: '' }) : null,
        h('div', {},
          h('h1', {}, r.title),
          facts.length ? h('ul', { class: 'facts' }, facts.map((f) => h('li', {}, f))) : null,
          r.headerNotes ? h('p', { class: 'header-notes' }, r.headerNotes) : null)),
      h('div', { class: 'toolbar' },
        metricBtn, wakeBtn,
        h('button', { class: 'btn', type: 'button', onclick: () => window.print() }, 'Print')),
      h('div', { class: 'recipe-body' },
        ingPanel,
        h('section', { class: 'panel', 'aria-labelledby': 'steps-h' },
          h('h2', { id: 'steps-h' }, 'Method'),
          r.instructionSections.map((s) => [
            s.title ? h('h3', {}, s.title) : null,
            h('ol', { class: 'steps' }, s.steps.map((st) =>
              h('li', { role: 'checkbox', 'aria-checked': 'false', tabindex: '0', onclick: toggleDone, onkeydown: (e) => { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); toggleDone(e); } } },
                h('span', { class: 'num', 'aria-hidden': 'true' }, String(st.n)),
                h('span', {}, st.text)))),
          ]),
          r.notes.length
            ? h('div', { class: 'notes' }, r.notes.map((n) =>
                h('div', { class: `note note--${n.type}` }, h('b', {}, NOTE_LABEL[n.type] ?? 'Note'), n.text)))
            : null,
          r.reference ? h('p', { class: 'reference' }, 'Source: ', /^https?:\/\/\S+$/.test(r.reference) ? h('a', { href: r.reference, rel: 'noopener noreferrer', target: '_blank' }, r.reference) : r.reference) : null))),
  );
  main.focus({ preventScroll: true });
  window.scrollTo(0, 0);
}

// ---------- Books ----------
// Set through CSSOM, not a style attribute: the CSP forbids inline styles.
function swatch(color) {
  const el = h('div', { class: 'book-swatch', 'aria-hidden': 'true' });
  el.style.background = /^#[0-9a-f]{3,8}$/i.test(color ?? '') ? color : 'var(--accent)';
  return el;
}

const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;

function bookCover(b, cls) {
  return b.coverURL ? h('img', { class: cls, src: b.coverURL, alt: '', loading: 'lazy' }) : swatch(b.color);
}

async function showBooks() {
  setTab('books');
  document.title = 'Books · Reczipes';
  let books;
  try {
    books = await getJSON('/api/books');
  } catch (e) {
    return render(errorView(e));
  }
  render(
    h('div', { class: 'page-head' }, h('h1', {}, 'Books'), h('p', { class: 'muted' }, plural(books.length, 'book'))),
    books.length
      ? h('ul', { class: 'grid' }, books.map((b) => h('li', {},
          h('a', { class: 'card', href: `#/book/${encodeURIComponent(b.id)}` },
            bookCover(b, 'card__img'),
            h('div', { class: 'card__body' },
              h('h2', { class: 'card__title' }, b.name),
              h('span', { class: 'card__meta' },
                [b.webCount ? plural(b.webCount, 'recipe') : 'No recipes yet', b.sharedByName ? `by ${b.sharedByName}` : null].filter(Boolean).join(' · ')),
              b.description ? h('p', { class: 'card__desc' }, b.description) : null)))))
      : h('p', { class: 'empty' }, 'No books have been shared yet.'),
  );
}

// A book page has views: Recipes (cards, first 10), Index (A–Z, generated from the
// book's current recipes — never stored page numbers), and, when the app published
// them, Contents (the book's sections in order), Pictures and Glossary.
const BOOK_VIEWS = [
  ['recipes', 'Recipes'],
  ['index', 'Index'],
  ['contents', 'Contents'],
  ['pictures', 'Pictures'],
  ['glossary', 'Glossary'],
];

const letterOf = (title) => {
  const c = title.normalize('NFD').replace(/[̀-ͯ]/g, '').trim().charAt(0).toUpperCase();
  return /[A-Z]/.test(c) ? c : '#';
};

function bookIndexView(inBook) {
  if (!inBook.length) return h('p', { class: 'empty' }, 'This book has no recipes on the web yet.');
  const groups = new Map();
  for (const r of inBook) {
    const k = letterOf(r.title);
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(r);
  }
  const letters = [...groups.keys()].sort((a, b) => (a === '#') - (b === '#') || a.localeCompare(b));
  return h('div', { class: 'book-index' },
    h('nav', { class: 'az', 'aria-label': 'Jump to letter' },
      letters.map((k) => h('a', { href: '#', onclick: (ev) => { ev.preventDefault(); document.getElementById(`idx-${k}`)?.scrollIntoView({ behavior: 'smooth' }); } }, k))),
    letters.map((k) => h('section', { class: 'idx-group', id: `idx-${k}` },
      h('h2', {}, k),
      h('ul', { class: 'idx-list' }, groups.get(k).map((r) =>
        h('li', {}, h('a', { href: `#/recipe/${encodeURIComponent(r.id)}` }, r.title)))))));
}

function bookContentsView(book, byId) {
  const pics = new Map(book.images.filter((i) => i.id).map((i) => [i.id, i]));
  const rows = [];
  for (const s of book.sections) {
    if (s.itemType === 'heading') {
      rows.push(h('li', { class: 'toc-heading' }, h('h2', {}, s.title)));
    } else if (s.itemType === 'recipe') {
      const r = s.available && s.itemID ? byId.get(s.itemID) : null;
      rows.push(h('li', { class: 'toc-recipe' }, r ? h('a', { href: `#/recipe/${encodeURIComponent(r.id)}` }, r.title) : h('span', { class: 'na' }, s.title)));
    } else if (s.itemType === 'image') {
      const pic = s.itemID ? pics.get(s.itemID) : null;
      rows.push(h('li', { class: 'toc-image' },
        pic ? h('figure', {}, h('img', { src: pic.url, alt: pic.title ?? s.title, loading: 'lazy' }), h('figcaption', {}, pic.caption ?? pic.title ?? s.title)) : h('span', { class: 'na' }, s.title)));
    } else {
      rows.push(h('li', { class: 'toc-other' }, s.title));
    }
  }
  return h('ol', { class: 'toc' }, rows);
}

function bookPicturesView(book) {
  const covers = book.images.filter((i) => i.kind === 'cover');
  const inside = book.images.filter((i) => i.kind !== 'cover');
  const fig = (i) => h('li', {},
    h('a', { href: i.url, target: '_blank', rel: 'noopener noreferrer' },
      h('figure', { class: 'pic' },
        h('img', { src: i.url, alt: i.title ?? '', loading: 'lazy' }),
        i.title || i.caption ? h('figcaption', {}, i.title ? h('b', {}, i.title) : null, i.caption && i.caption !== i.title ? ` ${i.caption}` : null) : null)));
  return h('div', {},
    covers.length ? [h('h2', { class: 'pics-head' }, 'Covers'), h('ul', { class: 'pics' }, covers.map(fig))] : null,
    inside.length ? [h('h2', { class: 'pics-head' }, 'Inside the book'), h('ul', { class: 'pics' }, inside.map(fig))] : null);
}

function bookGlossaryView(book) {
  const input = h('input', { type: 'search', placeholder: 'Search the glossary', 'aria-label': 'Search the glossary', autocomplete: 'off' });
  const list = h('dl', { class: 'glossary' });
  const apply = () => {
    const terms = input.value.toLowerCase().split(/\s+/).filter(Boolean);
    const hits = book.glossary.filter((g) => {
      const hay = [g.term, g.localName, g.definition, ...g.relatedTerms].filter(Boolean).join(' ').toLowerCase();
      return terms.every((t) => hay.includes(t));
    });
    list.replaceChildren(...(hits.length
      ? hits.flatMap((g) => [
          h('dt', {}, g.term, g.localName ? h('span', { class: 'muted' }, ` — ${g.localName}`) : null),
          h('dd', {}, g.definition, g.relatedTerms.length ? h('span', { class: 'muted' }, ` See also: ${g.relatedTerms.join(', ')}.`) : null),
        ])
      : [h('p', { class: 'empty' }, 'No glossary entries match that search.')]));
  };
  input.addEventListener('input', apply);
  apply();
  return h('div', {}, book.glossary.length > 8 ? h('div', { class: 'search' }, searchIcon(), input) : null, list);
}

async function showBook(id, view = 'recipes') {
  setTab('books');
  let book, recipes;
  try {
    [book, recipes] = await Promise.all([getJSON(`/api/books/${encodeURIComponent(id)}`), getJSON('/api/recipes')]);
  } catch (e) {
    return render(h('a', { class: 'back', href: '#/books' }, '← All books'), errorView(e));
  }
  document.title = `${book.name} · Reczipes`;
  const bookHref = `#/book/${encodeURIComponent(book.id)}`;
  backTo = { href: view === 'recipes' ? bookHref : `${bookHref}?view=${view}`, label: book.name };
  const byId = new Map(recipes.map((r) => [r.id, r]));
  const inBook = book.entries
    .filter((e) => e.available && byId.has(e.id))
    .map((e) => byId.get(e.id))
    .sort((a, b) => a.title.localeCompare(b.title, undefined, { sensitivity: 'base' }));

  const has = {
    recipes: true,
    index: inBook.length > 0,
    contents: book.sections.length > 0,
    pictures: book.images.length > 0,
    glossary: book.glossary.length > 0,
  };
  if (!has[view]) view = 'recipes';
  const views = BOOK_VIEWS.filter(([k]) => has[k]);
  const nav = views.length > 1
    ? h('nav', { class: 'subtabs', 'aria-label': `${book.name} sections` },
        views.map(([k, label]) => h('a', { href: k === 'recipes' ? bookHref : `${bookHref}?view=${k}`, 'aria-current': k === view ? 'page' : null }, label)))
    : null;

  const count = h('p', { class: 'muted' });
  let body;
  if (view === 'recipes') {
    const list = h('ul', { class: 'grid' });
    const input = h('input', { type: 'search', placeholder: `Search ${book.name}`, 'aria-label': `Search ${book.name}`, autocomplete: 'off' });
    // Long books show the first 10; search always covers the whole book.
    const PREVIEW = 10;
    let showAll = false;
    const more = h('div', { class: 'more' });
    const apply = () => {
      const terms = input.value.toLowerCase().split(/\s+/).filter(Boolean);
      const hits = inBook.filter((r) => terms.every((t) => r.search.includes(t)));
      const shown = terms.length || showAll ? hits : hits.slice(0, PREVIEW);
      list.replaceChildren(...shown.map(recipeCard));
      count.textContent = terms.length ? `${hits.length} of ${plural(inBook.length, 'recipe')}` : plural(inBook.length, 'recipe');
      if (!hits.length) list.replaceChildren(h('li', { class: 'empty' }, terms.length ? 'No recipes in this book match that search.' : 'This book has no recipes on the web yet.'));
      more.replaceChildren(
        shown.length < hits.length
          ? h('button', { class: 'btn', type: 'button', onclick: () => { showAll = true; apply(); } }, `Show all ${plural(hits.length, 'recipe')}`)
          : '',
      );
    };
    input.addEventListener('input', apply);
    apply();
    body = [inBook.length > PREVIEW ? h('div', { class: 'search' }, searchIcon(), input) : null, list, more];
  } else {
    count.textContent = plural(inBook.length, 'recipe');
    body = view === 'index' ? bookIndexView(inBook)
      : view === 'contents' ? bookContentsView(book, byId)
      : view === 'pictures' ? bookPicturesView(book)
      : bookGlossaryView(book);
  }

  render(
    h('a', { class: 'back', href: '#/books' }, '← All books'),
    h('header', { class: book.coverURL ? 'book-head has-img' : 'book-head' },
      book.coverURL ? h('img', { class: 'book-head__img', src: book.coverURL, alt: '' }) : null,
      h('div', {},
        h('h1', {}, book.name),
        book.description ? h('p', { class: 'header-notes' }, book.description) : null,
        book.sharedByName ? h('p', { class: 'muted' }, `Shared by ${book.sharedByName}`) : null,
        count)),
    nav,
    body,
  );
  window.scrollTo(0, 0);
}

// ---------- Router ----------
function route() {
  const hash = location.hash.replace(/^#/, '') || '/';
  const [pathPart, queryPart] = hash.split('?');
  const m = pathPart.match(/^\/recipe\/(.+)$/);
  if (m) return showRecipe(decodeURIComponent(m[1]));
  const mb = pathPart.match(/^\/book\/(.+)$/);
  if (mb) return showBook(decodeURIComponent(mb[1]), new URLSearchParams(queryPart ?? '').get('view') ?? 'recipes');
  if (pathPart === '/books') return showBooks();
  return showRecipes(new URLSearchParams(queryPart ?? '').get('q') ?? '');
}

window.addEventListener('hashchange', route);
loadStatus();
route();
