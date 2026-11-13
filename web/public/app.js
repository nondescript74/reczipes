// Reczipes web reader. No framework, no build step.
// All recipe text is user content from a public database: it is only ever
// placed into the page with textContent (via h()), never as HTML.

import { t, tn, lang, language, setLang, LANGUAGES } from './i18n.js';
import { toMetric, unitWord, metricPhrase } from './units.js';

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

let backTo = { href: '#/', label: t('All recipes') };

// Recipe text in the reader's language: the app publishes each recipe in every app
// language (translations), already lined up with the English. Missing → English.
// Titles stay as their owner entered them, in whatever language (Z, 2026-11-09);
// only the text under them follows the reader.
const trOf = (r) => r?.translations?.[lang()] ?? null;
const localSummary = (r) => {
  const tr = trOf(r);
  return tr ? { ...r, yield: tr.yield ?? r.yield, headerNotes: tr.headerNotes ?? r.headerNotes } : r;
};
// A book's description in the reader's language (the name stays as entered).
const localBook = (b) => {
  const d = b?.translations?.[lang()]?.description;
  return d ? { ...b, description: d } : b;
};
function localRecipe(r) {
  const tr = trOf(r);
  if (!tr) return r;
  return {
    ...r,
    headerNotes: tr.headerNotes ?? r.headerNotes,
    yield: tr.yield ?? r.yield,
    ingredientSections: tr.ingredientSections,
    instructionSections: tr.instructionSections,
    notes: tr.notes,
    translated: true,
  };
}
const localRecipes = (list) => list.map(localSummary);
const cache = new Map();

// The site sits behind Cloudflare Access. When the sign-in lapses, an API call is redirected to the
// Access login on another origin, which fetch reports as a network error (or the server answers 401).
// Reload the page then, so the browser itself shows the login — at most once a minute, so a real
// outage can't loop.
function reloadForSignIn() {
  try {
    const last = Number(sessionStorage.getItem('reczipes.signinReload') || 0);
    if (Date.now() - last < 60_000) return false;
    sessionStorage.setItem('reczipes.signinReload', String(Date.now()));
  } catch {
    /* no storage: still reload once for this page load */
    if (reloadForSignIn.done) return false;
    reloadForSignIn.done = true;
  }
  location.reload();
  return true;
}

async function getJSON(url) {
  if (cache.has(url)) return cache.get(url);
  const p = fetch(url, { credentials: 'same-origin', redirect: 'manual' }).then(async (res) => {
    if (res.type === 'opaqueredirect' || res.status === 401) {
      reloadForSignIn();
      throw Object.assign(new Error('Sign-in needed'), { status: 401 });
    }
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw Object.assign(new Error(body.error || `HTTP ${res.status}`), { status: res.status });
    return body;
  }, (err) => {
    if (navigator.onLine !== false) reloadForSignIn(); // offline is not a sign-in problem
    throw err;
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
  return Number.isNaN(d.getTime()) ? null : d.toLocaleDateString(lang(), { year: 'numeric', month: 'short', day: 'numeric' });
};

function setTab(name) {
  for (const a of document.querySelectorAll('.tabs a')) {
    if (a.dataset.tab === name) a.setAttribute('aria-current', 'page');
    else a.removeAttribute('aria-current');
  }
}

function render(...nodes) {
  main.replaceChildren(...nodes.flat(Infinity).filter((n) => n != null && n !== false));
}

function errorView(err) {
  return h('div', { class: 'empty' },
    h('p', {}, err.status === 404 ? t('That recipe isn’t available.') : t('Recipes couldn’t be loaded right now.')),
    h('p', {}, h('a', { href: '#/' }, t('Back to all recipes'))));
}

// ---------- Status banner ----------
async function loadStatus() {
  try {
    const s = await getJSON('/api/status');
    if (s.source === 'fixtures') {
      banner.replaceChildren(h('p', { class: 'banner' },
        t('Preview mode: these are sample recipes. Live recipes from the app appear once the site is connected to iCloud.')));
      sourceEl.textContent = t('Showing sample data.');
    } else {
      if (s.lastError) {
        banner.replaceChildren(h('p', { class: 'banner' },
          t('Couldn’t refresh from iCloud just now; showing recipes as of {date}.', { date: fmtDate(s.loadedAt) ?? t('earlier') })));
      }
      sourceEl.textContent = s.loadedAt ? t('Updated {date}.', { date: new Date(s.loadedAt).toLocaleString(lang()) }) : '';
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
        h('span', { class: 'card__meta' }, [r.yield, r.ingredientCount ? t('{n} ingredients', { n: r.ingredientCount }) : null].filter(Boolean).join(' · ')))));
}

async function showRecipes(query = '') {
  setTab('recipes');
  backTo = { href: '#/', label: t('All recipes') };
  document.title = `${t('Recipes')} · Reczipes`;
  let recipes;
  try {
    recipes = localRecipes(await getJSON('/api/recipes'));
  } catch (e) {
    return render(errorView(e));
  }
  const list = h('ul', { class: 'grid' });
  const count = h('p', { class: 'muted' });
  const input = h('input', {
    type: 'search', placeholder: t('Search by recipe or ingredient'), 'aria-label': t('Search recipes'),
    value: query, autocomplete: 'off',
  });
  const apply = () => {
    const terms = input.value.toLowerCase().split(/\s+/).filter(Boolean);
    const hits = recipes.filter((r) => terms.every((t) => r.search.includes(t)));
    list.replaceChildren(...hits.map(recipeCard));
    count.textContent = terms.length
      ? t('{hits} of {total} recipes', { hits: hits.length, total: recipes.length })
      : tn(recipes.length, '{n} recipe', '{n} recipes');
    if (!hits.length) list.replaceChildren(h('li', { class: 'empty' }, terms.length ? t('No recipes match that search.') : t('No recipes have been shared yet.')));
    const q = input.value.trim();
    history.replaceState(null, '', q ? `#/?q=${encodeURIComponent(q)}` : '#/');
  };
  input.addEventListener('input', apply);
  render(
    h('div', { class: 'page-head' }, h('h1', {}, t('Recipes')), count),
    h('div', { class: 'search' }, searchIcon(), input),
    list,
  );
  apply();
}

// ---------- Recipe detail ----------
// Metric: the app's own metric amount when it gave one, else a plain conversion of
// cups, ounces and pounds (spoons are metric already). Unit words in the reader's language.
function metricOf(i) {
  if (i.metricQuantity) return { quantity: i.metricQuantity, unit: i.metricUnit };
  return toMetric(i.quantity, i.unit, lang());
}
function qtyText(i, metric) {
  const m = metric ? metricOf(i) : null;
  const q = m ? m.quantity : i.quantity;
  const u = m ? m.unit : unitWord(i.unit, lang());
  return [q, u].filter(Boolean).join(' ');
}
// Readers in any language but English start in metric; each language remembers its own choice.
const metricKey = () => `reczipes.metric.${lang()}`;
function metricPreferred() {
  const saved = store(metricKey());
  if (saved != null) return saved === '1';
  if (lang() === 'en') return store('reczipes.metric') === '1'; // the choice made before languages
  return true;
}

const NOTE_LABEL = { tip: 'Tip', substitution: 'Substitution', warning: 'Warning', timing: 'Timing', general: 'Note' }; // keys for t()

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
    r = localRecipe(await getJSON(`/api/recipes/${encodeURIComponent(id)}`));
  } catch (e) {
    return render(h('a', { class: 'back', href: backTo.href }, `← ${backTo.label}`), errorView(e));
  }
  document.title = `${r.title} · Reczipes`;

  // A translated recipe already gives amounts in the reader's units: no switch.
  const hasMetric = !r.translated && r.ingredientSections.some((s) => s.ingredients.some((i) => metricOf(i)));
  let metric = hasMetric && metricPreferred();
  // Ticked-off ingredients survive a redraw (e.g. switching to metric).
  const doneIng = new Set();
  const toggleIng = (e) => {
    toggleDone(e);
    const k = e.currentTarget.dataset.key;
    if (e.currentTarget.classList.contains('done')) doneIng.add(k); else doneIng.delete(k);
  };
  const ingPanel = h('section', { class: 'panel ingredients-panel', 'aria-labelledby': 'ing-h' });
  const health = r.health ?? null;
  const fodmapKeys = new Set((health?.fodmap?.substitutions ?? []).map((g) => g.key));

  const drawIngredients = () => {
    ingPanel.replaceChildren(...[
      h('h2', { id: 'ing-h' }, t('Ingredients')),
      r.ingredientSections.map((s, si) => [
        s.title ? h('h3', {}, s.title) : null,
        h('ul', { class: 'ingredients' }, s.ingredients.map((i, ii) =>
          h('li', { class: doneIng.has(`${si}.${ii}`) ? 'done' : null, 'data-key': `${si}.${ii}`, role: 'checkbox', 'aria-checked': String(doneIng.has(`${si}.${ii}`)), tabindex: '0', onclick: toggleIng, onkeydown: (e) => { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); toggleIng(e); } } },
            qtyText(i, metric) ? h('span', { class: 'qty' }, qtyText(i, metric) + ' ') : null,
            i.name,
            i.preparation ? h('span', { class: 'prep' }, `, ${i.preparation}`) : null,
            fodmapKeys.has(`${si}.${ii}`) ? fodmapFlag(`${si}.${ii}`) : null))),
        s.transitionNote ? h('p', { class: 'transition' }, s.transitionNote) : null,
      ]),
    ].flat(Infinity).filter(Boolean));
  };
  drawIngredients();

  // The FODMAP panel shows the same amounts, so it follows the Metric switch too.
  const fodmap = health ? fodmapPanel(health.fodmap, r, metric) : null;

  const metricBtn = hasMetric
    ? h('button', { class: 'btn', type: 'button', 'aria-pressed': String(metric), onclick: () => {
        metric = !metric;
        store(metricKey(), metric ? '1' : '0');
        metricBtn.setAttribute('aria-pressed', String(metric));
        drawIngredients();
        fodmap?.setMetric(metric);
      } }, t('Metric'))
    : null;
  const wakeBtn = 'wakeLock' in navigator
    ? h('button', { class: 'btn', type: 'button', 'aria-pressed': 'false', onclick: (e) => setWakeLock(e.currentTarget.getAttribute('aria-pressed') !== 'true', e.currentTarget) }, t('Keep screen on'))
    : null;

  const facts = [r.yield, r.sharedByName ? t('Shared by {name}', { name: r.sharedByName }) : null, fmtDate(r.sharedDate)].filter(Boolean);

  render(
    h('a', { class: 'back', href: backTo.href }, `← ${backTo.label}`),
    // Untranslated recipe text is English whatever the page language (screen readers, spelling).
    h('article', { lang: r.translated || lang() === 'en' ? null : 'en' },
      h('header', { class: `recipe-hero${r.imageURL ? ' has-img' : ''}` },
        r.imageURL ? h('img', { src: r.imageURL, alt: '' }) : null,
        h('div', {},
          h('h1', {}, r.title),
          facts.length ? h('ul', { class: 'facts' }, facts.map((f) => h('li', {}, f))) : null,
          r.headerNotes ? h('p', { class: 'header-notes' }, r.headerNotes) : null)),
      h('div', { class: 'toolbar' },
        metricBtn, wakeBtn,
        h('button', { class: 'btn', type: 'button', onclick: () => window.print() }, t('Print'))),
      health ? h('div', { class: 'health-area' }, fodmap, diabetesPanel(health)) : null,
      h('div', { class: 'recipe-body' },
        ingPanel,
        h('section', { class: 'panel', 'aria-labelledby': 'steps-h' },
          h('h2', { id: 'steps-h' }, t('Method')),
          r.instructionSections.map((s) => [
            s.title ? h('h3', {}, s.title) : null,
            h('ol', { class: 'steps' }, s.steps.map((st) =>
              h('li', { role: 'checkbox', 'aria-checked': 'false', tabindex: '0', onclick: toggleDone, onkeydown: (e) => { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); toggleDone(e); } } },
                h('span', { class: 'num', 'aria-hidden': 'true' }, String(st.n)),
                h('span', {}, st.text)))),
          ]),
          r.notes.length
            ? h('div', { class: 'notes' }, r.notes.map((n) =>
                h('div', { class: `note note--${n.type}` }, h('b', {}, t(NOTE_LABEL[n.type] ?? 'Note')), n.text)))
            : null,
          r.reference ? h('p', { class: 'reference' }, t('Source: '), /^https?:\/\/\S+$/.test(r.reference) ? h('a', { href: r.reference, rel: 'noopener noreferrer', target: '_blank' }, r.reference) : r.reference) : null))),
  );
  main.focus({ preventScroll: true });
  window.scrollTo(0, 0);
}

// ---------- FODMAP and diabetes (same content as the app's recipe page) ----------
// Panels open/closed state is remembered per viewer, like the app's Show/Hide.
function rememberedDetails(key, cls, defaultOpen, summary, ...body) {
  const saved = store(key);
  const d = h('details', { class: cls, open: saved == null ? defaultOpen : saved === '1' },
    h('summary', { 'data-show': t('Show'), 'data-hide': t('Hide') }, summary), ...body);
  d.addEventListener('toggle', () => store(key, d.open ? '1' : '0'));
  return d;
}

const chip = (text, tone) => h('span', { class: `chip chip--${tone}` }, t(text));
const LEVEL_TONE = { Low: 'ok', Moderate: 'warn', High: 'bad' };
const CONFIDENCE_TONE = { Recommended: 'ok', 'Good Alternative': 'warn', 'Limited Option': 'caution' };
const FODMAP_ICON = { Oligosaccharides: '🧅', Disaccharides: '🥛', Monosaccharides: '🍯', Polyols: '🍎' };

function fodmapFlag(key) {
  return h('button', {
    type: 'button', class: 'fodmap-flag', title: t('FODMAP substitute available'),
    onclick: (e) => {
      e.stopPropagation();
      const card = document.getElementById(`fodmap-${key}`);
      if (!card) return;
      card.closest('details.health')?.setAttribute('open', '');
      card.open = true;
      card.scrollIntoView({ behavior: 'smooth', block: 'center' });
    },
    onkeydown: (e) => e.stopPropagation(),
  }, t('⇄ FODMAP substitute'));
}

// The flagged ingredient as the recipe page shows it, looked up by key: it carries the
// app's own metric amount, and a translated recipe's words (both line up item for item).
function flaggedIngredient(g, r) {
  const [si, ii] = String(g.key).split('.').map(Number);
  const s = r?.ingredientSections?.[si];
  const ing = s?.ingredients?.[ii];
  if (!ing) return { ing: g.ingredient, section: g.sectionTitle };
  return { ing, section: r.translated ? s.title : g.sectionTitle };
}
const ingLabel = (ing, metric) => [qtyText(ing, metric), ing.name].filter(Boolean).join(' ');
const subQty = (q, metric) => (metric ? metricPhrase(q, lang()) : q);

function fodmapPanel(f, r, metric = false) {
  if (!f?.hasSubstitutions) return null; // the app shows this section only when there is something to swap
  const n = f.substitutions.length;
  const amounts = []; // [element, text-for(metric)] redrawn when Metric is switched
  const amount = (el, textFor) => { el.textContent = textFor(metric); amounts.push([el, textFor]); return el; };
  const panel = rememberedDetails('reczipes.panel.fodmap', 'health health--fodmap', true,
    [h('span', { class: 'health__title' }, t('FODMAP Friendly Options')), chip(f.overallLevel, LEVEL_TONE[f.overallLevel])],
    f.isSafeWithoutSubstitutions
      ? h('p', { class: 'callout callout--ok' }, t('✓ This recipe is already low FODMAP!'))
      : h('p', { class: 'callout callout--warn' }, tn(n, '{n} ingredient can be substituted', '{n} ingredients can be substituted')),
    f.substitutions.map((g) => ({ g, ...flaggedIngredient(g, r) })).map(({ g, ing, section }) => h('details', { class: 'sub-card', id: `fodmap-${g.key}` },
      h('summary', {},
        h('span', { class: 'sub-card__warn', 'aria-hidden': 'true' }, '⚠'),
        h('span', { class: 'sub-card__ing' },
          amount(h('b', {}), (m) => ingLabel(ing, m)),
          section ? h('span', { class: 'muted' }, ` · ${section}`) : null,
          h('span', { class: 'sub-card__cats' }, g.substitution.fodmapCategories.map((c) => `${FODMAP_ICON[c] ?? ''} ${t(c)}`).join('   ')))),
      h('div', { class: 'sub-card__body' },
        h('p', { class: 'muted' }, g.substitution.explanation),
        g.substitution.portionNote ? h('p', { class: 'portion' }, '📏 ', g.substitution.portionNote) : null,
        h('p', { class: 'sub-card__with' }, t('Substitute with:')),
        h('ul', { class: 'sub-options' }, g.substitution.substitutes.map((o) => h('li', {},
          h('span', { class: 'sub-options__name' }, o.name, ' ', chip(o.confidence, CONFIDENCE_TONE[o.confidence] ?? 'warn')),
          o.quantity ? amount(h('span', { class: 'sub-options__qty' }), (m) => subQty(o.quantity, m)) : null,
          o.notes ? h('span', { class: 'sub-options__notes' }, o.notes) : null)))))));
  panel.setMetric = (m) => { metric = m; amounts.forEach(([el, textFor]) => { el.textContent = textFor(m); }); };
  return panel;
}

const SUIT_TONE = { Excellent: 'ok', Good: 'ok', Moderate: 'warn', Caution: 'caution', Avoid: 'bad' };
const CONSENSUS = {
  strongConsensus: ['Verified', 'ok'], moderateConsensus: ['Moderate', 'info'],
  limitedEvidence: ['Limited', 'warn'], needsReview: ['Review', 'bad'],
};
const glTone = (v) => (v <= 10 ? 'ok' : v <= 20 ? 'warn' : 'bad');
const glWord = (v) => (v <= 10 ? 'Low' : v <= 20 ? 'Medium' : 'High');
const grams = (v) => `${Math.trunc(v)}g`;

function diabetesPanel(health) {
  const score = health.diabetes;
  const info = health.diabeticInfo;
  const consensus = info ? CONSENSUS[info.consensusLevel] ?? CONSENSUS.needsReview : null;
  const concerns = [...score.highSugarIngredients, ...score.refinedCarbIngredients.filter((x) => !score.highSugarIngredients.includes(x))];

  const check = h('div', { class: 'dcheck' },
    h('div', { class: 'dcheck__head' }, h('b', {}, t('Ingredient check')), chip(score.suitability, SUIT_TONE[score.suitability])),
    concerns.length ? h('p', {}, h('span', { class: 'muted' }, t('Higher sugar or refined carbs: ')), concerns.join(', ')) : null,
    score.beneficialIngredients.length ? h('p', {}, h('span', { class: 'muted' }, t('Helpful: ')), score.beneficialIngredients.join(', ')) : null);

  let analysis;
  if (info) {
    const bar = h('div', { class: `glbar__fill glbar--${info.glycemicLoad ? glTone(info.glycemicLoad.value) : 'ok'}` });
    if (info.glycemicLoad) bar.style.width = `${Math.min(100, (info.glycemicLoad.value / 30) * 100)}%`;
    analysis = [
      info.glycemicLoad ? h('div', { class: `dcard dcard--${glTone(info.glycemicLoad.value)}` },
        h('div', { class: 'dcard__head' }, h('b', {}, t('Glycemic Impact')),
          h('span', { class: `gl gl--${glTone(info.glycemicLoad.value)}` }, h('b', {}, String(Math.trunc(info.glycemicLoad.value))), h('small', {}, t(glWord(info.glycemicLoad.value))))),
        h('div', { class: 'glbar', role: 'img', 'aria-label': t('Glycemic load {n} of 30', { n: Math.trunc(info.glycemicLoad.value) }) }, bar),
        info.glycemicLoad.explanation ? h('p', { class: 'muted' }, info.glycemicLoad.explanation) : null) : null,
      info.carbs ? h('div', { class: 'dcard' },
        h('b', {}, t('Carbohydrate Breakdown')),
        h('dl', { class: 'carbs' },
          h('div', {}, h('dt', {}, t('Total Carbs')), h('dd', {}, grams(info.carbs.totalCarbs))),
          h('div', {}, h('dt', {}, t('Net Carbs')), h('dd', {}, grams(info.carbs.netCarbs))),
          h('div', {}, h('dt', {}, t('Fiber')), h('dd', {}, grams(info.carbs.fiber))))) : null,
      info.guidance.map((g) => h('details', { class: 'guide' },
        h('summary', {}, h('b', {}, g.title), g.summary ? h('span', { class: 'muted guide__sum' }, g.summary) : null),
        g.detailedExplanation ? h('p', {}, g.detailedExplanation) : null,
        g.practicalTips.length ? [h('p', { class: 'guide__tips' }, t('Tips:')), h('ul', {}, g.practicalTips.map((tip) => h('li', {}, tip)))] : null)),
      info.substitutions.length ? h('div', { class: 'alts' },
        h('h3', {}, t('Healthier Alternatives')),
        h('ul', {}, info.substitutions.map((x) => h('li', {},
          h('s', {}, x.originalIngredient), ' → ', h('b', {}, x.substitute),
          x.reason ? h('span', { class: 'muted alts__why' }, x.reason) : null)))) : null,
      h('details', { class: 'dsources' },
        h('summary', {}, tn(info.sources.length, 'Based on {n} unverified source', 'Based on {n} unverified sources'),
          info.lastUpdated ? h('span', { class: 'muted' }, t(' · Last updated: {date}', { date: fmtDate(info.lastUpdated) })) : null),
        // Claude names these from memory, without web access (operator 2026-11-13: say so).
        h('p', { class: 'muted dsources__note' }, t('Suggested by Claude from memory, not looked up. Check a source before relying on it.')),
        info.sources.length ? h('ul', {}, info.sources.map((src) => h('li', {},
          src.url ? h('a', { href: src.url, rel: 'noopener noreferrer', target: '_blank' }, src.title) : src.title,
          src.organization ? h('span', { class: 'muted' }, ` — ${src.organization}`) : null,
          src.publishDate ? h('span', { class: 'muted' }, ` · ${fmtDate(src.publishDate)}`) : null))) : null),
    ];
  } else {
    analysis = h('p', { class: 'muted dnone' },
      t('No Claude analysis has been published for this recipe yet. The Reczipes app adds one automatically, usually within a day.'));
  }

  return rememberedDetails('reczipes.panel.diabetes', 'health health--diabetes', true,
    [h('span', { class: 'health__title' }, t('Diabetic-Friendly Analysis')), consensus ? chip(consensus[0], consensus[1]) : null],
    h('p', { class: 'callout callout--info' }, h('b', {}, t('Informational Only. ')), t('This analysis is not medical advice. Consult your healthcare provider.')),
    check,
    analysis);
}

// ---------- Books ----------
// Set through CSSOM, not a style attribute: the CSP forbids inline styles.
function swatch(color) {
  const el = h('div', { class: 'book-swatch', 'aria-hidden': 'true' });
  el.style.background = /^#[0-9a-f]{3,8}$/i.test(color ?? '') ? color : 'var(--accent)';
  return el;
}

const PLURAL = { book: ['{n} book', '{n} books'], recipe: ['{n} recipe', '{n} recipes'] };
const plural = (n, word) => tn(n, ...PLURAL[word]);

function bookCover(b, cls) {
  return b.coverURL ? h('img', { class: cls, src: b.coverURL, alt: '', loading: 'lazy' }) : swatch(b.color);
}

async function showBooks() {
  setTab('books');
  document.title = `${t('Books')} · Reczipes`;
  let books;
  try {
    books = (await getJSON('/api/books')).map(localBook);
  } catch (e) {
    return render(errorView(e));
  }
  render(
    h('div', { class: 'page-head' }, h('h1', {}, t('Books')), h('p', { class: 'muted' }, plural(books.length, 'book'))),
    books.length
      ? h('ul', { class: 'grid' }, books.map((b) => h('li', {},
          h('a', { class: 'card', href: `#/book/${encodeURIComponent(b.id)}` },
            bookCover(b, 'card__img'),
            h('div', { class: 'card__body' },
              h('h2', { class: 'card__title' }, b.name),
              h('span', { class: 'card__meta' },
                [b.webCount ? plural(b.webCount, 'recipe') : t('No recipes yet'), b.sharedByName ? t('by {name}', { name: b.sharedByName }) : null].filter(Boolean).join(' · ')),
              b.description ? h('p', { class: 'card__desc' }, b.description) : null)))))
      : h('p', { class: 'empty' }, t('No books have been shared yet.')),
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
  if (!inBook.length) return h('p', { class: 'empty' }, t('This book has no recipes on the web yet.'));
  const groups = new Map();
  for (const r of inBook) {
    const k = letterOf(r.title);
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(r);
  }
  const letters = [...groups.keys()].sort((a, b) => (a === '#') - (b === '#') || a.localeCompare(b));
  return h('div', { class: 'book-index' },
    h('nav', { class: 'az', 'aria-label': t('Jump to letter') },
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
    } else if (s.itemType === 'glossary' && book.glossary.length) {
      rows.push(h('li', { class: 'toc-recipe' }, h('a', { href: `#/book/${encodeURIComponent(book.id)}?view=glossary` }, s.title)));
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
    covers.length ? [h('h2', { class: 'pics-head' }, t('Covers')), h('ul', { class: 'pics' }, covers.map(fig))] : null,
    inside.length ? [h('h2', { class: 'pics-head' }, t('Inside the book')), h('ul', { class: 'pics' }, inside.map(fig))] : null);
}

function bookGlossaryView(book) {
  const input = h('input', { type: 'search', placeholder: t('Search the glossary'), 'aria-label': t('Search the glossary'), autocomplete: 'off' });
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
          h('dd', {}, g.definition, g.relatedTerms.length ? h('span', { class: 'muted' }, t(' See also: {terms}.', { terms: g.relatedTerms.join(', ') })) : null),
        ])
      : [h('p', { class: 'empty' }, t('No glossary entries match that search.'))]));
  };
  input.addEventListener('input', apply);
  apply();
  return h('div', {}, book.glossary.length > 8 ? h('div', { class: 'search' }, searchIcon(), input) : null, list);
}

async function showBook(id, view = 'recipes') {
  setTab('books');
  let book, recipes;
  try {
    [book, recipes] = await Promise.all([getJSON(`/api/books/${encodeURIComponent(id)}`).then(localBook), getJSON('/api/recipes').then(localRecipes)]);
  } catch (e) {
    return render(h('a', { class: 'back', href: '#/books' }, t('← All books')), errorView(e));
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
    ? h('nav', { class: 'subtabs', 'aria-label': t('{name} sections', { name: book.name }) },
        views.map(([k, label]) => h('a', { href: k === 'recipes' ? bookHref : `${bookHref}?view=${k}`, 'aria-current': k === view ? 'page' : null }, t(label))))
    : null;

  const count = h('p', { class: 'muted' });
  let body;
  if (view === 'recipes') {
    const list = h('ul', { class: 'grid' });
    const input = h('input', { type: 'search', placeholder: t('Search {name}', { name: book.name }), 'aria-label': t('Search {name}', { name: book.name }), autocomplete: 'off' });
    // Long books show the first 10; search always covers the whole book.
    const PREVIEW = 10;
    let showAll = false;
    const more = h('div', { class: 'more' });
    const apply = () => {
      const terms = input.value.toLowerCase().split(/\s+/).filter(Boolean);
      const hits = inBook.filter((r) => terms.every((t) => r.search.includes(t)));
      const shown = terms.length || showAll ? hits : hits.slice(0, PREVIEW);
      list.replaceChildren(...shown.map(recipeCard));
      count.textContent = terms.length ? t('{hits} of {total}', { hits: hits.length, total: plural(inBook.length, 'recipe') }) : plural(inBook.length, 'recipe');
      if (!hits.length) list.replaceChildren(h('li', { class: 'empty' }, terms.length ? t('No recipes in this book match that search.') : t('This book has no recipes on the web yet.')));
      more.replaceChildren(
        shown.length < hits.length
          ? h('button', { class: 'btn', type: 'button', onclick: () => { showAll = true; apply(); } }, t('Show all {what}', { what: plural(hits.length, 'recipe') }))
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
    h('a', { class: 'back', href: '#/books' }, t('← All books')),
    h('header', { class: book.coverURL ? 'book-head has-img' : 'book-head' },
      book.coverURL ? h('img', { class: 'book-head__img', src: book.coverURL, alt: '' }) : null,
      h('div', {},
        h('h1', {}, book.name),
        book.description ? h('p', { class: 'header-notes' }, book.description) : null,
        book.sharedByName ? h('p', { class: 'muted' }, t('Shared by {name}', { name: book.sharedByName })) : null,
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

// ---------- Language (flag in the header, same choice as the app's toolbar flag) ----------
function applyStaticText() {
  document.documentElement.lang = lang();
  for (const el of document.querySelectorAll('[data-i18n]')) el.textContent = t(el.dataset.i18n);
  for (const el of document.querySelectorAll('[data-i18n-aria]')) el.setAttribute('aria-label', t(el.dataset.i18nAria));
}

function languageMenu() {
  const holder = document.getElementById('lang');
  if (!holder) return;
  const cur = language();
  const button = h('button', {
    type: 'button', class: 'lang__btn', 'aria-haspopup': 'true', 'aria-expanded': 'false',
    title: t('Language'), 'aria-label': t('Language: {name}', { name: cur.name }),
  }, cur.flag);
  const menu = h('ul', { class: 'lang__menu', role: 'menu', hidden: true },
    LANGUAGES.map((l) => h('li', { role: 'none' },
      h('button', {
        type: 'button', role: 'menuitemradio', 'aria-checked': String(l.code === cur.code), lang: l.code,
        onclick: () => { close(); if (l.code !== lang()) { setLang(l.code); refreshLanguage(); } },
      }, h('span', { 'aria-hidden': 'true' }, l.flag), ` ${l.name}`))));
  function close() { menu.hidden = true; button.setAttribute('aria-expanded', 'false'); }
  button.addEventListener('click', (e) => {
    e.stopPropagation();
    menu.hidden = !menu.hidden;
    button.setAttribute('aria-expanded', String(!menu.hidden));
    if (!menu.hidden) menu.querySelector('[aria-checked="true"]')?.focus();
  });
  document.addEventListener('click', close);
  menu.addEventListener('keydown', (e) => { if (e.key === 'Escape') { close(); button.focus(); } });
  holder.replaceChildren(button, menu);
}

function refreshLanguage() {
  applyStaticText();
  languageMenu();
  backTo = { ...backTo, label: backTo.href === '#/' ? t('All recipes') : backTo.label };
  loadStatus();
  route();
}

applyStaticText();
languageMenu();
window.addEventListener('hashchange', route);
loadStatus();
route();
