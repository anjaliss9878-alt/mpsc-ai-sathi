/**
 * Restrict CORS to the production Student app, Admin panel, and same-origin
 * Netlify site. Never use Access-Control-Allow-Origin: *.
 *
 * Allowlist:
 * - Same origin as the function Host (Student web on Netlify)
 * - URL / DEPLOY_PRIME_URL (Netlify site / deploy preview)
 * - Firebase Hosting defaults for project mpsc-3f4ef
 * - Production Student origin
 * - Production Admin Panel (https://mpsc-ai-admin.netlify.app)
 * - Local Flutter Admin debug origins (8080/8081)
 * - CORS_ALLOWED_ORIGINS (comma-separated extra Student/Admin origins)
 *
 * Local Admin may call production `/rag/*`. Those routes stay auth-gated
 * (extract is admin-only).
 */

const DEFAULT_ORIGINS = [
  'https://mpsc-3f4ef.web.app',
  'https://mpsc-3f4ef.firebaseapp.com',
  'https://mpscaisathi.co.in',
  'https://mpsc-ai-admin.netlify.app',
];

const ADMIN_DEBUG_ORIGINS = [
  'http://localhost:8081',
  'http://localhost:8080',
  'http://127.0.0.1:8081',
  'http://127.0.0.1:8080',
];

function header(event, name) {
  if (!event || !event.headers) return '';
  const h = event.headers;
  const lower = name.toLowerCase();
  for (const [k, v] of Object.entries(h)) {
    if (`${k}`.toLowerCase() === lower) return `${v || ''}`.trim();
  }
  return '';
}

function requestOrigin(event) {
  return header(event, 'origin');
}

function configuredOrigins() {
  const extra = `${process.env.CORS_ALLOWED_ORIGINS || ''}`
    .split(',')
    .map((s) => s.trim().replace(/\/$/, ''))
    .filter(Boolean);
  const site = `${process.env.URL || ''}`.trim().replace(/\/$/, '');
  const preview = `${process.env.DEPLOY_PRIME_URL || ''}`
    .trim()
    .replace(/\/$/, '');
  return [
    ...new Set(
      [...DEFAULT_ORIGINS, ...ADMIN_DEBUG_ORIGINS, site, preview, ...extra].filter(
        Boolean,
      ),
    ),
  ];
}

function isLocalDevOrigin(origin) {
  const o = `${origin || ''}`.trim().replace(/\/$/, '');
  if (ADMIN_DEBUG_ORIGINS.includes(o)) return true;
  try {
    const u = new URL(origin);
    const localHost =
      u.hostname === 'localhost' ||
      u.hostname === '127.0.0.1' ||
      u.hostname === '[::1]';
    const port = u.port === '8080' || u.port === '8081';
    return u.protocol === 'http:' && localHost && port;
  } catch (_) {
    return false;
  }
}

function allowLocalCors() {
  return true;
}

function isSameOrigin(event, origin) {
  if (!origin) return false;
  const host = header(event, 'host');
  if (!host) return false;
  try {
    const o = new URL(origin);
    return o.host === host;
  } catch (_) {
    return false;
  }
}

function isOriginAllowed(origin, event) {
  const o = `${origin || ''}`.trim().replace(/\/$/, '');
  if (!o) return false;
  if (isSameOrigin(event, o)) return true;
  if (configuredOrigins().includes(o)) return true;
  if (isLocalDevOrigin(o)) return true;
  return false;
}

function corsHeaders(event = {}, extra = {}) {
  const origin = requestOrigin(event);
  const headers = {
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    Vary: 'Origin',
    ...extra,
  };
  if (origin && isOriginAllowed(origin, event)) {
    headers['Access-Control-Allow-Origin'] = origin;
  }
  return headers;
}

function json(statusCode, body, event = {}) {
  return {
    statusCode,
    headers: corsHeaders(event, { 'Content-Type': 'application/json' }),
    body: JSON.stringify(body),
  };
}

function optionsResponse(event = {}) {
  return { statusCode: 204, headers: corsHeaders(event), body: '' };
}

module.exports = {
  DEFAULT_ORIGINS,
  ADMIN_DEBUG_ORIGINS,
  configuredOrigins,
  requestOrigin,
  isOriginAllowed,
  isLocalDevOrigin,
  allowLocalCors,
  corsHeaders,
  json,
  optionsResponse,
};
