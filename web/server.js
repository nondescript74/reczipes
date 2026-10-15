// Reczipes web — read-only browser for recipes shared from the Reczipes2 app.
// Zero dependencies: Node >= 20 (global fetch, node:http). Railway runs `npm start`.

import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createCloudKitClient } from './lib/cloudkit.js';
import { createStore } from './lib/store.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(here, 'public');

const env = process.env;
const PORT = Number(env.PORT) || 8080;
const CONTAINER = env.CLOUDKIT_CONTAINER || 'iCloud.com.headydiscy.reczipes';
const CK_ENV = env.CLOUDKIT_ENVIRONMENT || 'production';
const useFixtures = env.RECZIPES_DATA === 'fixtures' || !env.CLOUDKIT_API_TOKEN;

const cloudkit = useFixtures
  ? null
  : createCloudKitClient({ container: CONTAINER, environment: CK_ENV, apiToken: env.CLOUDKIT_API_TOKEN });

const store = createStore({
  cloudkit,
  fixturesPath: path.join(here, 'fixtures', 'sample.json'),
  ttlMs: (Number(env.CACHE_TTL_SECONDS) || 300) * 1000,
});

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.webmanifest': 'application/manifest+json',
  '.json': 'application/json; charset=utf-8',
};

const SECURITY_HEADERS = {
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'strict-origin-when-cross-origin',
  'x-frame-options': 'DENY',
  // Images come from CloudKit asset hosts; everything else is same-origin.
  'content-security-policy':
    "default-src 'self'; img-src 'self' data: https://*.icloud-content.com https://*.icloud.com https://*.apple-cloudkit.com; " +
    "style-src 'self' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; script-src 'self'; connect-src 'self'; " +
    "base-uri 'none'; frame-ancestors 'none'",
};

function send(res, status, body, headers = {}) {
  res.writeHead(status, { ...SECURITY_HEADERS, ...headers });
  res.end(body);
}

function sendJSON(res, status, obj, cache = 'no-store') {
  send(res, status, JSON.stringify(obj), { 'content-type': 'application/json; charset=utf-8', 'cache-control': cache });
}

async function serveStatic(res, urlPath) {
  const rel = urlPath === '/' ? '/index.html' : urlPath;
  const file = path.normalize(path.join(PUBLIC_DIR, rel));
  if (!file.startsWith(PUBLIC_DIR + path.sep)) return false;
  try {
    const st = await stat(file);
    if (!st.isFile()) return false;
    const body = await readFile(file);
    const ext = path.extname(file);
    send(res, 200, body, {
      'content-type': MIME[ext] ?? 'application/octet-stream',
      'cache-control': ext === '.html' ? 'no-cache' : 'public, max-age=300',
    });
    return true;
  } catch {
    return false;
  }
}

async function handle(req, res) {
  const url = new URL(req.url, 'http://localhost');
  const p = url.pathname;

  if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, 'Method not allowed');

  if (p === '/healthz') return sendJSON(res, 200, { ok: true });

  if (p === '/api/status') {
    return sendJSON(res, 200, { ...(await store.status()), container: CONTAINER, environment: useFixtures ? null : CK_ENV });
  }

  if (p.startsWith('/api/')) {
    try {
      if (p === '/api/recipes') return sendJSON(res, 200, await store.listRecipes(), 'public, max-age=60');
      if (p === '/api/books') return sendJSON(res, 200, await store.listBooks(), 'public, max-age=60');
      const m = p.match(/^\/api\/recipes\/([A-Za-z0-9-]{1,64})$/);
      if (m) {
        const r = await store.getRecipe(m[1]);
        return r ? sendJSON(res, 200, r, 'public, max-age=60') : sendJSON(res, 404, { error: 'Recipe not found' });
      }
      return sendJSON(res, 404, { error: 'Not found' });
    } catch (err) {
      console.error('[api]', p, err.message);
      return sendJSON(res, 503, { error: 'Recipes are temporarily unavailable', detail: err.message });
    }
  }

  if (await serveStatic(res, p)) return;
  // Client-side routes fall back to the app shell.
  if (!path.extname(p) && (await serveStatic(res, '/'))) return;
  send(res, 404, 'Not found', { 'content-type': 'text/plain; charset=utf-8' });
}

const server = http.createServer((req, res) => {
  handle(req, res).catch((err) => {
    console.error('[server]', err);
    if (!res.headersSent) send(res, 500, 'Internal error');
  });
});

server.listen(PORT, () => {
  console.log(
    `reczipes-web listening on :${PORT} — data source: ${
      useFixtures ? 'SAMPLE FIXTURES (no CLOUDKIT_API_TOKEN set)' : `CloudKit ${CONTAINER} / ${CK_ENV} / public`
    }`,
  );
  store.refresh().catch((err) => console.error('[startup refresh]', err.message));
});
