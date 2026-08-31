/**
 * SSRF guard for rag-extract. PDFs may be fetched only from this project's
 * Firebase Storage (or extra hosts in RAG_ALLOWED_PDF_HOSTS).
 *
 * Rejects file://, http, localhost, private/link-local/metadata IPs,
 * credentials-in-URL, and arbitrary domains.
 */

const dns = require('dns').promises;
const net = require('net');

const DEFAULT_BUCKETS = [
  'mpsc-3f4ef.firebasestorage.app',
  'mpsc-3f4ef.appspot.com',
];

function untrusted(message = 'PDF extraction failed: untrusted fileUrl') {
  return Object.assign(new Error(message), {
    publicMessage: message,
    statusCode: 400,
  });
}

function storageBuckets() {
  const primary = `${process.env.FIREBASE_STORAGE_BUCKET || ''}`.trim().toLowerCase();
  return new Set(
    [...DEFAULT_BUCKETS, primary].map((b) => b.trim().toLowerCase()).filter(Boolean),
  );
}

function extraAllowedHosts() {
  return `${process.env.RAG_ALLOWED_PDF_HOSTS || ''}`
    .split(',')
    .map((s) => s.trim().toLowerCase().replace(/\/$/, ''))
    .filter(Boolean);
}

function ipv4Parts(host) {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (!m) return null;
  const parts = m.slice(1).map((n) => Number(n));
  if (parts.some((n) => n > 255)) return null;
  return parts;
}

function isPrivateIPv4(host) {
  const p = ipv4Parts(host);
  if (!p) return false;
  const [a, b] = p;
  if (a === 0) return true;
  if (a === 10) return true;
  if (a === 127) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a === 100 && b >= 64 && b <= 127) return true;
  if (a === 192 && b === 0) return true;
  if (a === 198 && (b === 18 || b === 19)) return true;
  if (a >= 224) return true;
  return false;
}

function isPrivateIPv6(host) {
  const h = host.toLowerCase();
  if (h === '::' || h === '::1') return true;
  if (h.startsWith('fc') || h.startsWith('fd')) return true;
  if (h.startsWith('fe80:')) return true;
  if (h.startsWith('ff')) return true;
  const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/i.exec(h);
  if (mapped) return isPrivateIPv4(mapped[1]);
  const mappedHex = /^::ffff:([0-9a-f:.]+)$/i.exec(h);
  if (mappedHex && mappedHex[1].includes('.')) return isPrivateIPv4(mappedHex[1]);
  return false;
}

function isBlockedHostname(hostname) {
  const h = `${hostname || ''}`.replace(/^\[|\]$/g, '').toLowerCase();
  if (!h) return true;
  if (
    h === 'localhost' ||
    h === 'localhost.localdomain' ||
    h === 'metadata.google.internal' ||
    h === 'metadata' ||
    h.endsWith('.localhost') ||
    h.endsWith('.local') ||
    h.endsWith('.internal')
  ) {
    return true;
  }
  if (/^\d+$/.test(h)) return true;
  const ipVer = net.isIP(h);
  if (ipVer === 4) return true;
  if (ipVer === 6) return true;
  if (ipv4Parts(h)) return true;
  return false;
}

function isPrivateAddress(addr) {
  const a = `${addr || ''}`.replace(/^\[|\]$/g, '').toLowerCase();
  if (!a) return true;
  const ver = net.isIP(a);
  if (ver === 4) return isPrivateIPv4(a);
  if (ver === 6) return isPrivateIPv6(a);
  return isBlockedHostname(a);
}

function hostAllowedForParsed(hostname, parsed) {
  const host = hostname.toLowerCase();
  const buckets = storageBuckets();
  const extra = extraAllowedHosts();

  if (host === 'firebasestorage.googleapis.com') {
    const m = parsed.pathname.match(/\/(?:v0\/)?b\/([^/]+)\//);
    if (!m) return false;
    return buckets.has(decodeURIComponent(m[1]).toLowerCase());
  }
  if (host === 'storage.googleapis.com') {
    const first = parsed.pathname.split('/').filter(Boolean)[0];
    return Boolean(first && buckets.has(decodeURIComponent(first).toLowerCase()));
  }
  if (host.endsWith('.firebasestorage.app') || host.endsWith('.appspot.com')) {
    return buckets.has(host);
  }
  return extra.includes(host);
}

function inspectPdfUrl(raw) {
  const url = `${raw || ''}`.trim();
  if (!url) return { ok: false, reason: 'fileUrl required' };
  if (/[\u0000-\u001F\u007F]/.test(url)) {
    return { ok: false, reason: 'untrusted fileUrl' };
  }
  let parsed;
  try {
    parsed = new URL(url);
  } catch (_) {
    return { ok: false, reason: 'untrusted fileUrl' };
  }
  if (parsed.protocol !== 'https:') {
    return { ok: false, reason: 'untrusted fileUrl' };
  }
  if (parsed.username || parsed.password) {
    return { ok: false, reason: 'untrusted fileUrl' };
  }
  const hostname = parsed.hostname.replace(/^\[|\]$/g, '').toLowerCase();
  if (isBlockedHostname(hostname)) {
    return { ok: false, reason: 'untrusted fileUrl' };
  }
  if (!hostAllowedForParsed(hostname, parsed)) {
    return { ok: false, reason: 'untrusted fileUrl' };
  }
  return { ok: true, href: parsed.href, hostname, parsed };
}

function assertTrustedPdfUrl(raw) {
  const inspected = inspectPdfUrl(raw);
  if (!inspected.ok) {
    throw untrusted(
      inspected.reason === 'fileUrl required'
        ? 'PDF extraction failed: fileUrl required'
        : 'PDF extraction failed: untrusted fileUrl',
    );
  }
  return inspected;
}

async function assertPublicDns(hostname) {
  let addrs;
  try {
    addrs = await dns.lookup(hostname, { all: true, verbatim: true });
  } catch (_) {
    throw untrusted('PDF extraction failed: untrusted fileUrl');
  }
  if (!Array.isArray(addrs) || addrs.length === 0) {
    throw untrusted('PDF extraction failed: untrusted fileUrl');
  }
  for (const row of addrs) {
    if (isPrivateAddress(row.address)) {
      throw untrusted('PDF extraction failed: untrusted fileUrl');
    }
  }
}

async function fetchTrusted(raw, { fetchImpl = fetch, maxRedirects = 3 } = {}) {
  let current = `${raw || ''}`.trim();
  for (let i = 0; i <= maxRedirects; i += 1) {
    const inspected = assertTrustedPdfUrl(current);
    await assertPublicDns(inspected.hostname);
    const res = await fetchImpl(inspected.href, { redirect: 'manual' });
    const status = res.status;
    if (status >= 300 && status < 400) {
      const location = res.headers.get('location');
      if (!location) {
        throw untrusted('PDF extraction failed: untrusted fileUrl');
      }
      current = new URL(location, inspected.href).href;
      continue;
    }
    return res;
  }
  throw untrusted('PDF extraction failed: untrusted fileUrl');
}

module.exports = {
  inspectPdfUrl,
  assertTrustedPdfUrl,
  assertPublicDns,
  fetchTrusted,
  isBlockedHostname,
  isPrivateAddress,
  isPrivateIPv4,
  storageBuckets,
};
