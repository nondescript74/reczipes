/**
 * access-guard.js — the second lock on the Reczipes web site (Lane 37, 2026-10-20).
 *
 * Ported from eml-corpus-tree/server/access-guard.mjs (the hvhoa-jena guard, Lane 33), with the
 * differences the Japan 2027 trip page made (JPNTWN2027/viewer/access_guard.py, Lane 36):
 *
 * The site is served by Railway at RECZIPES_PUBLIC_HOST (reczipes.industriallystrong.com), proxied by
 * Cloudflare, behind a Cloudflare Access application. Cloudflare's edge is one check; this file is the
 * other. Railway also publishes the service at <name>.up.railway.app, which Cloudflare never sees, so
 * the process refuses every request that does not carry an Access JWT it has verified itself: RS256
 * signature against the team's published certs, `iss`, `aud`, `exp`/`nbf`, and an `email` claim.
 *
 * Differences from the Node original, each deliberate:
 *   * The process binds 0.0.0.0 (Railway requires it), not loopback. A request passes as LOCAL only if
 *     the socket peer is loopback AND the Host is loopback AND no Cloudflare marker is present. On
 *     Railway the peer is its proxy, never 127.0.0.1, so nothing passes there without a token.
 *   * CF_ACCESS_EMAILS may be the literal `ACCESS_POLICY`: the list of people allowed in is kept in the
 *     Access policy only (the Japan 2027 ruling, applied here by the operator 2026-10-20: "the same user
 *     list"). The token is still fully verified and must carry an e-mail; the AUD ties it to this one
 *     Access application, whose policy is the list. Any other value is a comma list enforced here too.
 *   * GET /healthz is exempt and returns only {"ok":true} (Railway's health check carries no token).
 *   * RECZIPES_LEGACY_HOSTS (comma list, e.g. reczipes-production.up.railway.app): the address the site
 *     was shared under before the lock. A request for one of these hosts gets a 302 to the same path on
 *     the public host — no data, only a pointer — so old links and bookmarks reach the Access login
 *     instead of an error. Any other unknown host is 403 HOST_NOT_SERVED, as before.
 *
 * Failure posture is CLOSED: configuration missing or partial -> 403 GUARD_NOT_CONFIGURED naming the
 * missing variables (M-28). The refusals are fixtures in test/access-guard.test.js (M-3).
 *
 * Environment:
 *   RECZIPES_PUBLIC_HOST   reczipes.industriallystrong.com
 *   CF_ACCESS_TEAM_DOMAIN  <team>.cloudflareaccess.com
 *   CF_ACCESS_AUD          the Access application's Application Audience (AUD) tag
 *   CF_ACCESS_EMAILS       ACCESS_POLICY, or comma-separated e-mails
 *   RECZIPES_LEGACY_HOSTS  optional; hosts redirected to the public host
 */
import crypto from 'node:crypto';

export const LOOPBACK_HOSTS = new Set(['127.0.0.1', 'localhost', '[::1]', '::1']);
export const LOOPBACK_PEERS = new Set(['127.0.0.1', '::1', '::ffff:127.0.0.1']);
export const JWT_HEADER = 'cf-access-jwt-assertion';
export const JWT_COOKIE = 'CF_Authorization';
export const POLICY_SENTINEL = 'ACCESS_POLICY';
export const HEALTH_PATH = '/healthz';
const CERTS_TTL_MS = 60 * 60 * 1000;

/** Host header without its port. `[::1]:8080` -> `[::1]`. */
export function hostName(hostHeader) {
  const h = String(hostHeader || '').trim().toLowerCase();
  if (!h) return '';
  if (h.startsWith('[')) { const i = h.indexOf(']'); return i > 0 ? h.slice(0, i + 1) : h; }
  const i = h.indexOf(':');
  return i > 0 ? h.slice(0, i) : h;
}

export function isLoopbackHost(hostHeader) {
  return LOOPBACK_HOSTS.has(hostName(hostHeader));
}

/** Read the guard's configuration. Returns { ok:true, ... } or { ok:false, missing:[...] }.
 *  Partial configuration is NOT configuration: every required field must be set.
 *  `emails` is null when the Access policy is the list (ACCESS_POLICY). */
export function guardConfig(env = process.env) {
  const missing = [];
  const publicHost = hostName(env.RECZIPES_PUBLIC_HOST);
  const teamDomain = String(env.CF_ACCESS_TEAM_DOMAIN || '').trim().toLowerCase().replace(/^https?:\/\//, '').replace(/\/+$/, '');
  const aud = String(env.CF_ACCESS_AUD || '').trim();
  const rawEmails = String(env.CF_ACCESS_EMAILS || '').trim();
  const emails = rawEmails === POLICY_SENTINEL
    ? null
    : new Set(rawEmails.split(',').map((s) => s.trim().toLowerCase()).filter(Boolean));
  const legacyHosts = new Set(String(env.RECZIPES_LEGACY_HOSTS || '').split(',').map(hostName).filter(Boolean));
  if (!publicHost) missing.push('RECZIPES_PUBLIC_HOST');
  if (!teamDomain) missing.push('CF_ACCESS_TEAM_DOMAIN');
  if (!aud) missing.push('CF_ACCESS_AUD');
  if (emails !== null && !emails.size) missing.push('CF_ACCESS_EMAILS');
  if (missing.length) return { ok: false, missing };
  legacyHosts.delete(publicHost);
  return {
    ok: true, publicHost, teamDomain, aud, emails, legacyHosts,
    issuer: `https://${teamDomain}`, certsUrl: `https://${teamDomain}/cdn-cgi/access/certs`,
  };
}

function b64urlDecode(s) {
  return Buffer.from(String(s).replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}
export function b64urlEncode(buf) {
  return Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** Token from the header Cloudflare sets, else the cookie the browser carries. */
export function extractToken(headers) {
  const h = headers[JWT_HEADER];
  if (h) return String(Array.isArray(h) ? h[0] : h).trim();
  const cookie = String(headers.cookie || '');
  for (const part of cookie.split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === JWT_COOKIE && v.length) return v.join('=').trim();
  }
  return null;
}

/** Default certs fetcher — network, cached for an hour. Injected in tests. */
export function makeCertsFetcher(fetchImpl = globalThis.fetch) {
  let cache = null; // { at, keys }
  return async function fetchCerts(url, { force = false } = {}) {
    if (!force && cache && Date.now() - cache.at < CERTS_TTL_MS) return cache.keys;
    const r = await fetchImpl(url);
    if (!r.ok) throw new Error(`certs ${r.status} from ${url}`);
    const body = await r.json();
    const keys = Array.isArray(body?.keys) ? body.keys : [];
    cache = { at: Date.now(), keys };
    return keys;
  };
}

/**
 * Verify one Access JWT. Pure given its inputs: cfg, the token, a certs fetcher and a clock.
 * Returns { ok:true, email, kid, exp } or { ok:false, reason }.
 */
export async function verifyAccessJwt(token, cfg, { fetchCerts, now = () => Date.now() } = {}) {
  if (!token) return { ok: false, reason: 'NO_ACCESS_TOKEN' };
  const parts = token.split('.');
  if (parts.length !== 3) return { ok: false, reason: 'MALFORMED_TOKEN' };
  let header, payload;
  try {
    header = JSON.parse(b64urlDecode(parts[0]).toString('utf8'));
    payload = JSON.parse(b64urlDecode(parts[1]).toString('utf8'));
  } catch { return { ok: false, reason: 'MALFORMED_TOKEN' }; }
  if (header.alg !== 'RS256') return { ok: false, reason: `ALG_NOT_ALLOWED:${header.alg}` };
  if (!header.kid) return { ok: false, reason: 'NO_KID' };

  let keys;
  try { keys = await fetchCerts(cfg.certsUrl); }
  catch (e) { return { ok: false, reason: `CERTS_UNREACHABLE:${e?.message ?? e}` }; }
  let jwk = keys.find((k) => k.kid === header.kid);
  if (!jwk) {
    // A rotated key is the one case where a stale cache is the wrong answer.
    try { keys = await fetchCerts(cfg.certsUrl, { force: true }); } catch { /* fall through to UNKNOWN_KID */ }
    jwk = keys.find((k) => k.kid === header.kid);
    if (!jwk) return { ok: false, reason: 'UNKNOWN_KID' };
  }
  let pub;
  try { pub = crypto.createPublicKey({ key: jwk, format: 'jwk' }); }
  catch { return { ok: false, reason: 'BAD_JWK' }; }
  const signed = Buffer.from(`${parts[0]}.${parts[1]}`);
  const sigOk = crypto.verify('RSA-SHA256', signed, pub, b64urlDecode(parts[2]));
  if (!sigOk) return { ok: false, reason: 'BAD_SIGNATURE' };

  const t = Math.floor(now() / 1000);
  if (typeof payload.exp !== 'number' || payload.exp <= t) return { ok: false, reason: 'EXPIRED' };
  if (typeof payload.nbf === 'number' && payload.nbf > t + 60) return { ok: false, reason: 'NOT_YET_VALID' };
  if (payload.iss !== cfg.issuer) return { ok: false, reason: 'WRONG_ISSUER' };
  const aud = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!aud.includes(cfg.aud)) return { ok: false, reason: 'WRONG_AUDIENCE' };
  const email = String(payload.email || '').toLowerCase();
  if (!email) return { ok: false, reason: 'NO_EMAIL_CLAIM' };
  if (cfg.emails && !cfg.emails.has(email)) return { ok: false, reason: 'EMAIL_NOT_AUTHORIZED' };
  return { ok: true, email, kid: header.kid, exp: payload.exp };
}

function refuse(res, code, body) {
  const s = JSON.stringify(body);
  res.writeHead(code, { 'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(s), 'cache-control': 'no-store' });
  res.end(s);
}

/**
 * Decides per request (next() = serve it):
 *   GET /healthz                                  -> pass, bare
 *   loopback peer + loopback Host + no CF marker  -> LOCAL: pass, req.access.via = 'loopback'
 *   Host in RECZIPES_LEGACY_HOSTS                 -> 302 to the same path on the public host
 *   anything else                                 -> must verify; refused in words otherwise
 * `opts.env`, `opts.fetchCerts`, `opts.now`, `opts.log` are injectable so the table is a fixture.
 */
export function accessGuard(opts = {}) {
  const env = opts.env || process.env;
  const fetchCerts = opts.fetchCerts || makeCertsFetcher();
  const now = opts.now || (() => Date.now());
  const log = opts.log || ((line) => console.log(line));
  return async function guard(req, res, next) {
    const pathOnly = String(req.url || '/').split('?')[0];
    if (pathOnly === HEALTH_PATH) {
      req.access = { via: 'health', host: hostName(req.headers.host), email: null };
      return next();
    }
    const host = req.headers.host;
    const peer = req.socket?.remoteAddress || '';
    const viaCloudflare = !!(req.headers['cf-ray'] || req.headers['cf-connecting-ip'] || req.headers[JWT_HEADER]);
    if (LOOPBACK_PEERS.has(peer) && isLoopbackHost(host) && !viaCloudflare) {
      req.access = { via: 'loopback', host: hostName(host), email: null };
      return next();
    }
    const cfg = guardConfig(env);
    if (!cfg.ok) {
      log(`[access] REFUSED 403 GUARD_NOT_CONFIGURED host=${hostName(host)} missing=${cfg.missing.join(',')}`);
      return refuse(res, 403, { error: 'GUARD_NOT_CONFIGURED', host: hostName(host), missing: cfg.missing,
        why: 'the Access guard has no configuration; refusing is the only honest answer' });
    }
    if (cfg.legacyHosts.has(hostName(host))) {
      const to = `https://${cfg.publicHost}${req.url && req.url.startsWith('/') ? req.url : '/'}`;
      log(`[access] REDIRECT 302 legacy host=${hostName(host)} -> ${cfg.publicHost}`);
      res.writeHead(302, { location: to, 'cache-control': 'no-store', 'content-type': 'text/plain; charset=utf-8' });
      return res.end(`Reczipes has moved to https://${cfg.publicHost}/ — sign in there.\n`);
    }
    if (hostName(host) !== cfg.publicHost) {
      log(`[access] REFUSED 403 HOST_NOT_SERVED host=${hostName(host)} expected=${cfg.publicHost}`);
      return refuse(res, 403, { error: 'HOST_NOT_SERVED', host: hostName(host), served: cfg.publicHost });
    }
    const token = extractToken(req.headers);
    const v = await verifyAccessJwt(token, cfg, { fetchCerts, now });
    if (!v.ok) {
      const code = v.reason === 'EMAIL_NOT_AUTHORIZED' ? 403 : 401;
      log(`[access] REFUSED ${code} ${v.reason} host=${hostName(host)} path=${pathOnly}`);
      return refuse(res, code, { error: v.reason, host: hostName(host),
        why: 'this site is shared with invited people only; the Access token was absent or did not verify' });
    }
    req.access = { via: 'cloudflare-access', host: cfg.publicHost, email: v.email, kid: v.kid, exp: v.exp };
    log(`[access] OK ${v.email} ${req.method} ${pathOnly}`);
    return next();
  };
}

/** GET /api/access/whoami — which lock let the request in, and as whom. */
export function whoami(req, env = process.env) {
  const a = req.access || { via: 'UNGUARDED', email: null };
  return {
    via: a.via, served_to: a.email, host: a.host ?? null, public_host: hostName(env.RECZIPES_PUBLIC_HOST) || null,
    note: a.via === 'loopback' ? 'local browser; no token required' : 'verified by this process, not only by the edge',
  };
}
