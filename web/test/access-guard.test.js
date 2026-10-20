// Lane 37 — the second lock on the Reczipes web site. Ported from
// eml-corpus-tree/test/access-guard.test.mjs. A guard that has only seen passing input is not known to
// guard anything (M-3), so most of this file is refusals. Signatures are real RS256 over a key pair
// minted here; the certs endpoint is a stub, so nothing here touches the network.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  accessGuard, verifyAccessJwt, guardConfig, extractToken, isLoopbackHost, hostName, b64urlEncode, whoami,
} from '../lib/access-guard.js';

const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const KID = 'kid-test-1';
const JWK = { ...publicKey.export({ format: 'jwk' }), kid: KID, alg: 'RS256', use: 'sig' };
const OTHER = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });

const PUBLIC = 'reczipes.industriallystrong.com';
const LEGACY = 'reczipes-production.up.railway.app';
const ENV = {
  RECZIPES_PUBLIC_HOST: PUBLIC,
  CF_ACCESS_TEAM_DOMAIN: 'example.cloudflareaccess.com',
  CF_ACCESS_AUD: 'aud-abc123',
  CF_ACCESS_EMAILS: 'z@example.com, Second@Example.com',
  RECZIPES_LEGACY_HOSTS: LEGACY,
};
const POLICY_ENV = { ...ENV, CF_ACCESS_EMAILS: 'ACCESS_POLICY' };
const NOW = 1_800_000_000_000;
const now = () => NOW;
const fetchCerts = async () => [JWK];

function sign(payload, { key = privateKey, kid = KID, alg = 'RS256' } = {}) {
  const h = b64urlEncode(JSON.stringify({ alg, kid, typ: 'JWT' }));
  const p = b64urlEncode(JSON.stringify(payload));
  const sig = crypto.sign('RSA-SHA256', Buffer.from(`${h}.${p}`), key);
  return `${h}.${p}.${b64urlEncode(sig)}`;
}
const good = (over = {}) => ({
  iss: 'https://example.cloudflareaccess.com', aud: ['aud-abc123'], email: 'z@example.com',
  iat: NOW / 1000 - 60, exp: NOW / 1000 + 3600, ...over,
});

/** Drive the middleware with a fake req/res. Railway's proxy is the default peer. */
async function run(headers, { env = ENV, fc = fetchCerts, url = '/api/recipes', peer = '100.64.0.2' } = {}) {
  const req = { headers: { host: PUBLIC, ...headers }, url, method: 'GET', socket: { remoteAddress: peer } };
  let status = null, body = null, passed = false, hdrs = {};
  const res = {
    writeHead(code, h = {}) { status = code; hdrs = h; },
    end(s) { try { body = s ? JSON.parse(s) : null; } catch { body = s; } },
  };
  const lines = [];
  await accessGuard({ env, fetchCerts: fc, now, log: (l) => lines.push(l) })(req, res, () => { passed = true; });
  return { status, body, passed, req, lines, headers: hdrs };
}

test('hostName / isLoopbackHost', () => {
  assert.equal(hostName('127.0.0.1:8080'), '127.0.0.1');
  assert.equal(hostName('[::1]:8080'), '[::1]');
  assert.equal(hostName('Reczipes.IndustriallyStrong.com'), PUBLIC);
  assert.equal(isLoopbackHost('localhost:8080'), true);
  assert.equal(isLoopbackHost(PUBLIC), false);
  assert.equal(isLoopbackHost(''), false);
});

test('guardConfig: partial configuration is not configuration — every missing name is listed', () => {
  assert.equal(guardConfig(ENV).ok, true);
  const c = guardConfig({ RECZIPES_PUBLIC_HOST: 'x.example', CF_ACCESS_EMAILS: '' });
  assert.equal(c.ok, false);
  assert.deepEqual(c.missing, ['CF_ACCESS_TEAM_DOMAIN', 'CF_ACCESS_AUD', 'CF_ACCESS_EMAILS']);
  const t = guardConfig({ ...ENV, CF_ACCESS_TEAM_DOMAIN: 'https://Team.cloudflareaccess.com/' });
  assert.equal(t.issuer, 'https://team.cloudflareaccess.com');
  assert.equal(t.certsUrl, 'https://team.cloudflareaccess.com/cdn-cgi/access/certs');
  assert.equal(guardConfig(POLICY_ENV).emails, null, 'ACCESS_POLICY = the Access policy is the list');
  assert.equal(guardConfig({ ...ENV, RECZIPES_LEGACY_HOSTS: PUBLIC }).legacyHosts.has(PUBLIC), false,
    'the public host can never be a legacy host (that would be a redirect loop)');
});

test('extractToken: header first, then the CF_Authorization cookie, else null', () => {
  assert.equal(extractToken({ 'cf-access-jwt-assertion': ' t1 ' }), 't1');
  assert.equal(extractToken({ cookie: 'a=1; CF_Authorization=t2; b=2' }), 't2');
  assert.equal(extractToken({ cookie: 'a=1' }), null);
  assert.equal(extractToken({}), null);
});

test('MUST-NOT-TRIP: /healthz passes bare, with no token and the guard unconfigured', async () => {
  const r = await run({ host: 'healthcheck.railway.app' }, { env: {}, url: '/healthz' });
  assert.equal(r.passed, true);
  assert.equal(r.req.access.via, 'health');
});

test('MUST-TRIP: /healthz is matched exactly — /healthz/x and /healthzz are guarded', async () => {
  for (const url of ['/healthz/x', '/healthzz', '/api/healthz']) {
    const r = await run({}, { url });
    assert.equal(r.passed, false, url);
    assert.equal(r.status, 401, url);
  }
});

test('MUST-NOT-TRIP: loopback peer + loopback Host + no Cloudflare marker passes as local', async () => {
  const r = await run({ host: '127.0.0.1:8080' }, { peer: '127.0.0.1' });
  assert.equal(r.passed, true);
  assert.equal(r.req.access.via, 'loopback');
  assert.equal(whoami(r.req, ENV).served_to, null);
});

test('MUST-TRIP: a loopback Host from a NON-loopback peer (Railway proxy) is not local', async () => {
  const r = await run({ host: 'localhost' });
  assert.equal(r.passed, false);
  assert.equal(r.status, 403);
  assert.equal(r.body.error, 'HOST_NOT_SERVED');
});

test('MUST-TRIP: loopback peer + loopback Host but a Cloudflare marker is not local', async () => {
  const r = await run({ host: '127.0.0.1:8080', 'cf-ray': 'abc' }, { peer: '127.0.0.1' });
  assert.equal(r.passed, false);
  assert.equal(r.status, 403);
});

test('MUST-TRIP: public Host and NO token -> 401 NO_ACCESS_TOKEN', async () => {
  const r = await run({});
  assert.equal(r.passed, false);
  assert.equal(r.status, 401);
  assert.equal(r.body.error, 'NO_ACCESS_TOKEN');
  assert.match(r.lines[0], /REFUSED 401 NO_ACCESS_TOKEN/);
});

test('MUST-TRIP: the index page and static files are guarded too, not only the API', async () => {
  for (const url of ['/', '/index.html', '/app.js', '/api/status', '/api/access/whoami']) {
    const r = await run({}, { url });
    assert.equal(r.passed, false, url);
    assert.equal(r.status, 401, url);
  }
});

test('MUST-TRIP: guard unconfigured -> 403 GUARD_NOT_CONFIGURED, fail closed', async () => {
  const r = await run({ 'cf-access-jwt-assertion': sign(good()) }, { env: {} });
  assert.equal(r.passed, false);
  assert.equal(r.status, 403);
  assert.equal(r.body.error, 'GUARD_NOT_CONFIGURED');
  assert.deepEqual(r.body.missing, ['RECZIPES_PUBLIC_HOST', 'CF_ACCESS_TEAM_DOMAIN', 'CF_ACCESS_AUD', 'CF_ACCESS_EMAILS']);
});

test('MUST-TRIP: an unknown Host (e.g. a new *.up.railway.app) -> 403 HOST_NOT_SERVED, even with a token', async () => {
  const r = await run({ host: 'something-else.up.railway.app', 'cf-access-jwt-assertion': sign(good()) });
  assert.equal(r.status, 403);
  assert.equal(r.body.error, 'HOST_NOT_SERVED');
});

test('legacy host: 302 to the same path on the public host, no data, no token needed', async () => {
  const r = await run({ host: LEGACY }, { url: '/recipes?q=chai' });
  assert.equal(r.passed, false, 'never served');
  assert.equal(r.status, 302);
  assert.equal(r.headers.location, `https://${PUBLIC}/recipes?q=chai`);
  assert.match(String(r.body), /moved to https:\/\/reczipes\.industriallystrong\.com\//);
  const api = await run({ host: LEGACY }, { url: '/api/recipes' });
  assert.equal(api.status, 302, 'the API on the old host redirects too — it never answers with recipes');
});

test('legacy host is not honoured when the guard is unconfigured (fail closed first)', async () => {
  const r = await run({ host: LEGACY }, { env: { RECZIPES_LEGACY_HOSTS: LEGACY } });
  assert.equal(r.status, 403);
  assert.equal(r.body.error, 'GUARD_NOT_CONFIGURED');
});

test('MUST-NOT-TRIP: a valid token from an allowed identity passes and names the self', async () => {
  const r = await run({ 'cf-access-jwt-assertion': sign(good()) });
  assert.equal(r.passed, true);
  assert.equal(r.req.access.via, 'cloudflare-access');
  assert.equal(r.req.access.email, 'z@example.com');
  const w = whoami(r.req, ENV);
  assert.equal(w.served_to, 'z@example.com');
  assert.equal(w.public_host, PUBLIC);
});

test('MUST-NOT-TRIP: the token in the CF_Authorization cookie is as good as the header', async () => {
  const r = await run({ cookie: `CF_Authorization=${sign(good())}` });
  assert.equal(r.passed, true);
});

test('MUST-NOT-TRIP: e-mail comparison is case-insensitive on both sides', async () => {
  const r = await run({ 'cf-access-jwt-assertion': sign(good({ email: 'SECOND@example.com' })) });
  assert.equal(r.passed, true);
  assert.equal(r.req.access.email, 'second@example.com');
});

test('ACCESS_POLICY: any e-mail the Access app let in passes — but the token is still fully verified', async () => {
  const ok = await run({ 'cf-access-jwt-assertion': sign(good({ email: 'guest@example.org' })) }, { env: POLICY_ENV });
  assert.equal(ok.passed, true);
  assert.equal(ok.req.access.email, 'guest@example.org');
  const noEmail = await run({ 'cf-access-jwt-assertion': sign(good({ email: undefined })) }, { env: POLICY_ENV });
  assert.equal(noEmail.status, 401);
  assert.equal(noEmail.body.error, 'NO_EMAIL_CLAIM');
  const otherApp = await run({ 'cf-access-jwt-assertion': sign(good({ aud: ['japan2027-aud'] })) }, { env: POLICY_ENV });
  assert.equal(otherApp.status, 401);
  assert.equal(otherApp.body.error, 'WRONG_AUDIENCE', "a token from another Access app (e.g. Japan 2027) does not open this one");
  const none = await run({}, { env: POLICY_ENV });
  assert.equal(none.status, 401);
});

for (const [name, payload, expect] of [
  ['expired token', good({ exp: NOW / 1000 - 1 }), 'EXPIRED'],
  ['wrong audience', good({ aud: ['someone-else'] }), 'WRONG_AUDIENCE'],
  ['wrong issuer', good({ iss: 'https://evil.cloudflareaccess.com' }), 'WRONG_ISSUER'],
  ['missing email claim', good({ email: undefined }), 'NO_EMAIL_CLAIM'],
  ['not-yet-valid (nbf far ahead)', good({ nbf: NOW / 1000 + 3600 }), 'NOT_YET_VALID'],
]) {
  test(`MUST-TRIP: ${name} -> 401 ${expect}`, async () => {
    const r = await run({ 'cf-access-jwt-assertion': sign(payload) });
    assert.equal(r.passed, false);
    assert.equal(r.status, 401);
    assert.equal(r.body.error, expect);
  });
}

test('MUST-TRIP: an identity NOT in an explicit list -> 403 EMAIL_NOT_AUTHORIZED', async () => {
  const r = await run({ 'cf-access-jwt-assertion': sign(good({ email: 'stranger@example.com' })) });
  assert.equal(r.status, 403);
  assert.equal(r.body.error, 'EMAIL_NOT_AUTHORIZED');
});

test('MUST-TRIP: a token signed by an unpublished key -> BAD_SIGNATURE / UNKNOWN_KID, never a pass', async () => {
  const forged = await verifyAccessJwt(sign(good(), { key: OTHER.privateKey }), guardConfig(ENV), { fetchCerts, now });
  assert.equal(forged.reason, 'BAD_SIGNATURE');
  const unknown = await verifyAccessJwt(sign(good(), { kid: 'kid-nobody' }), guardConfig(ENV), { fetchCerts, now });
  assert.equal(unknown.reason, 'UNKNOWN_KID');
});

test('MUST-TRIP: alg=none and non-RS256 are refused before any key is consulted', async () => {
  let consulted = 0;
  const fc = async () => { consulted++; return [JWK]; };
  const h = b64urlEncode(JSON.stringify({ alg: 'none', kid: KID }));
  const p = b64urlEncode(JSON.stringify(good()));
  const r = await verifyAccessJwt(`${h}.${p}.`, guardConfig(ENV), { fetchCerts: fc, now });
  assert.match(r.reason, /^ALG_NOT_ALLOWED/);
  assert.equal(consulted, 0);
  const m = await verifyAccessJwt('not.a.jwt.at.all', guardConfig(ENV), { fetchCerts: fc, now });
  assert.equal(m.reason, 'MALFORMED_TOKEN');
});

test('MUST-TRIP: certs unreachable -> 401 CERTS_UNREACHABLE', async () => {
  const fc = async () => { throw new Error('ENOTFOUND'); };
  const r = await run({ 'cf-access-jwt-assertion': sign(good()) }, { fc });
  assert.equal(r.status, 401);
  assert.match(r.body.error, /^CERTS_UNREACHABLE/);
});

test('key rotation: an unknown kid forces ONE refetch, and a key that then appears verifies', async () => {
  let calls = 0;
  const fc = async (url, { force } = {}) => { calls++; return (force || calls > 1) ? [JWK] : []; };
  const r = await verifyAccessJwt(sign(good()), guardConfig(ENV), { fetchCerts: fc, now });
  assert.equal(r.ok, true);
  assert.equal(calls, 2);
});

// End to end: the real server.js on a real socket, configured like Railway. Requests come from
// 127.0.0.1 here, so they carry a non-loopback Host (as Railway's proxy delivers them) — the token
// path is what's exercised. Certs are unreachable (example domain), so even a token cannot pass:
// the point is that NOTHING but /healthz and the legacy redirect answers without one.
test('end to end: server.js refuses everything but /healthz; the old host redirects', async (t) => {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const port = 18000 + Math.floor(Math.random() * 1000);
  const child = spawn(process.execPath, [path.join(here, '..', 'server.js')], {
    env: { ...process.env, ...ENV, CF_ACCESS_TEAM_DOMAIN: 'invalid.invalid', PORT: String(port), RECZIPES_DATA: 'fixtures', CLOUDKIT_API_TOKEN: '' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  t.after(() => child.kill());
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('server did not start')), 5000);
    child.stdout.on('data', (d) => { if (String(d).includes('listening')) { clearTimeout(timer); resolve(); } });
  });
  const get = (p, host) => new Promise((resolve, reject) => {
    import('node:http').then(({ default: http }) => {
      http.get({ port, path: p, headers: { host } }, (res) => {
        let b = ''; res.on('data', (c) => { b += c; }); res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: b }));
      }).on('error', reject);
    });
  });
  const h = await get('/healthz', 'healthcheck.railway.app');
  assert.equal(h.status, 200);
  assert.deepEqual(JSON.parse(h.body), { ok: true });
  for (const p of ['/', '/app.js', '/api/recipes', '/api/books', '/api/status', '/api/access/whoami']) {
    const r = await get(p, PUBLIC);
    assert.equal(r.status, 401, p);
    assert.equal(JSON.parse(r.body).error, 'NO_ACCESS_TOKEN', p);
    assert.doesNotMatch(r.body, /ingredients|recipeData/i, `${p} leaks nothing`);
  }
  const legacy = await get('/api/recipes', LEGACY);
  assert.equal(legacy.status, 302);
  assert.equal(legacy.headers.location, `https://${PUBLIC}/api/recipes`);
  const other = await get('/', 'reczipes-production-abc.up.railway.app');
  assert.equal(other.status, 403);
});
