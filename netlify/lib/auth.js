/**
 * Firebase ID token verification for Netlify /ai/* and /rag/* functions.
 * Tokens are verified with Google's Secure Token certs (RS256). Admin
 * permission is the same allow-list as firestore.rules: admin/{uid} or
 * admins/{uid} (plus optional ADMIN_UIDS).
 */

const crypto = require('crypto');
const { json, optionsResponse } = require('./cors');

const CERTS_URL =
  'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';

let certCache = { certs: null, expiresAt: 0 };

const hooks = {
  getCerts: defaultGetCerts,
  lookupAdmin: defaultLookupAdmin,
};

function firebaseProjectId() {
  return (
    process.env.FIREBASE_PROJECT_ID ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    'mpsc-3f4ef'
  ).trim();
}

function setAuthHooksForTests(next = {}) {
  const inTest =
    process.env.NODE_TEST_CONTEXT != null || process.env.NODE_ENV === 'test';
  if (!inTest) {
    throw new Error('setAuthHooksForTests is test-only');
  }
  if (next.getCerts) hooks.getCerts = next.getCerts;
  if (next.lookupAdmin) hooks.lookupAdmin = next.lookupAdmin;
}

function resetAuthHooksForTests() {
  hooks.getCerts = defaultGetCerts;
  hooks.lookupAdmin = defaultLookupAdmin;
  certCache = { certs: null, expiresAt: 0 };
}

async function defaultGetCerts() {
  if (certCache.certs && Date.now() < certCache.expiresAt) {
    return certCache.certs;
  }
  const res = await fetch(CERTS_URL);
  if (!res.ok) {
    throw unauthorized();
  }
  const cacheControl = res.headers.get('cache-control') || '';
  const maxAgeMatch = /max-age=(\d+)/i.exec(cacheControl);
  const maxAgeMs = maxAgeMatch ? Number(maxAgeMatch[1]) * 1000 : 60 * 60 * 1000;
  const certs = await res.json();
  certCache = { certs, expiresAt: Date.now() + maxAgeMs };
  return certs;
}

function unauthorized() {
  return Object.assign(new Error('unauthenticated'), {
    publicMessage: 'unauthenticated',
    statusCode: 401,
  });
}

function forbidden() {
  return Object.assign(new Error('forbidden'), {
    publicMessage: 'forbidden',
    statusCode: 403,
  });
}

function decodeJwtPart(part) {
  const padded = part.replace(/-/g, '+').replace(/_/g, '/');
  const buf = Buffer.from(padded, 'base64');
  return JSON.parse(buf.toString('utf8'));
}

function bearerToken(event) {
  const headers = event?.headers || {};
  let raw = '';
  for (const [k, v] of Object.entries(headers)) {
    if (`${k}`.toLowerCase() === 'authorization') {
      raw = `${v || ''}`;
      break;
    }
  }
  const match = /^Bearer\s+(.+)$/i.exec(raw.trim());
  return match ? match[1].trim() : '';
}

function verifyRs256(unsigned, signatureB64Url, pem) {
  const verifier = crypto.createVerify('RSA-SHA256');
  verifier.update(unsigned);
  verifier.end();
  const sig = Buffer.from(
    signatureB64Url.replace(/-/g, '+').replace(/_/g, '/'),
    'base64',
  );
  return verifier.verify(pem, sig);
}

async function verifyFirebaseIdToken(idToken, deps = {}) {
  const token = `${idToken || ''}`.trim();
  if (!token || token.split('.').length !== 3) throw unauthorized();
  const [h, p, s] = token.split('.');
  let header;
  let payload;
  try {
    header = decodeJwtPart(h);
    payload = decodeJwtPart(p);
  } catch (_) {
    throw unauthorized();
  }
  if (header.alg !== 'RS256' || !header.kid) throw unauthorized();
  const projectId = deps.projectId || firebaseProjectId();
  const now = deps.now || Math.floor(Date.now() / 1000);
  const getCerts = deps.getCerts || hooks.getCerts;
  const certs = await getCerts();
  const pem = certs && certs[header.kid];
  if (!pem) throw unauthorized();
  if (!verifyRs256(`${h}.${p}`, s, pem)) throw unauthorized();
  if (!payload.exp || payload.exp <= now) throw unauthorized();
  if (payload.iat && payload.iat > now + 60) throw unauthorized();
  if (payload.aud !== projectId) throw unauthorized();
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) {
    throw unauthorized();
  }
  if (!payload.sub || typeof payload.sub !== 'string') throw unauthorized();
  return {
    uid: payload.sub,
    token,
    claims: payload,
  };
}

function adminUidAllowlist() {
  return `${process.env.ADMIN_UIDS || ''}`
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

async function defaultLookupAdmin(user) {
  if (adminUidAllowlist().includes(user.uid)) return true;
  const projectId = firebaseProjectId();
  for (const col of ['admin', 'admins']) {
    const url =
      `https://firestore.googleapis.com/v1/projects/${projectId}` +
      `/databases/(default)/documents/${col}/${encodeURIComponent(user.uid)}`;
    try {
      const res = await fetch(url, {
        headers: { Authorization: `Bearer ${user.token}` },
      });
      if (res.status === 200) return true;
    } catch (_) {
      // Try the other collection / fall through.
    }
  }
  return false;
}

async function userIsAdmin(user) {
  if (adminUidAllowlist().includes(user.uid)) return true;
  return hooks.lookupAdmin(user);
}

async function authorize(event, { admin = false } = {}) {
  const token = bearerToken(event);
  if (!token) throw unauthorized();
  const user = await verifyFirebaseIdToken(token);
  if (admin) {
    const ok = await userIsAdmin(user);
    if (!ok) throw forbidden();
  }
  return user;
}

async function withAuth(event, { admin = false, method = 'POST' } = {}) {
  if (event.httpMethod === 'OPTIONS') {
    return { halt: optionsResponse(event) };
  }
  if (method && event.httpMethod !== method) {
    return { halt: json(405, { error: 'method not allowed' }, event) };
  }
  try {
    const user = await authorize(event, { admin });
    return { user };
  } catch (e) {
    if (e.statusCode === 401) {
      return { halt: json(401, { error: 'unauthenticated' }, event) };
    }
    if (e.statusCode === 403) {
      return { halt: json(403, { error: 'forbidden' }, event) };
    }
    return { halt: json(500, { error: 'invalid request' }, event) };
  }
}

module.exports = {
  firebaseProjectId,
  bearerToken,
  verifyFirebaseIdToken,
  authorize,
  withAuth,
  userIsAdmin,
  setAuthHooksForTests,
  resetAuthHooksForTests,
  unauthorized,
  forbidden,
};
