const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

process.env.NODE_ENV = 'test';
process.env.FIREBASE_PROJECT_ID = 'mpsc-3f4ef';

const {
  inspectPdfUrl,
  isPrivateIPv4,
  isBlockedHostname,
} = require('./trusted_url');
const {
  isOriginAllowed,
  corsHeaders,
  json,
} = require('./cors');
const {
  setAuthHooksForTests,
  resetAuthHooksForTests,
  verifyFirebaseIdToken,
} = require('./auth');

const aiLesson = require('../functions/ai-lesson');
const ragLearn = require('../functions/rag-learn');
const ragExtract = require('../functions/rag-extract');
const ragVertexEmbed = require('../functions/rag-vertex-embed');
const ragRetrieve = require('../functions/rag-retrieve');
const {
  setRetrieveHooksForTests,
  resetRetrieveHooksForTests,
} = require('./rag_retrieve');

function keyPair() {
  return crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });
}

function b64url(value) {
  const buf = Buffer.isBuffer(value) ? value : Buffer.from(value);
  return buf
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function mintJwt({
  privateKey,
  kid,
  uid,
  projectId = 'mpsc-3f4ef',
  exp,
  iat,
}) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(
    JSON.stringify({ alg: 'RS256', typ: 'JWT', kid }),
  );
  const payload = b64url(
    JSON.stringify({
      aud: projectId,
      iss: `https://securetoken.google.com/${projectId}`,
      sub: uid,
      iat: iat ?? now,
      exp: exp ?? now + 3600,
      auth_time: now,
    }),
  );
  const unsigned = `${header}.${payload}`;
  const sign = crypto.createSign('RSA-SHA256');
  sign.update(unsigned);
  const sig = b64url(sign.sign(privateKey));
  return `${unsigned}.${sig}`;
}

const { publicKey, privateKey } = keyPair();
const kid = 'p0-test-kid';

function eventFor({
  method = 'POST',
  path = '/rag/learn',
  body = {},
  token,
  origin,
  host = 'mpsc-ai.netlify.app',
} = {}) {
  const headers = {
    host,
    'content-type': 'application/json',
  };
  if (origin) headers.origin = origin;
  if (token) headers.authorization = `Bearer ${token}`;
  return {
    httpMethod: method,
    path,
    headers,
    body: typeof body === 'string' ? body : JSON.stringify(body),
  };
}

function installAuthHooks() {
  setAuthHooksForTests({
    getCerts: async () => ({ [kid]: publicKey }),
    lookupAdmin: async (user) => user.uid === 'admin-uid',
  });
}

test.beforeEach(() => {
  installAuthHooks();
});

test.afterEach(() => {
  resetAuthHooksForTests();
  resetRetrieveHooksForTests();
  delete process.env.CONTEXT;
  delete process.env.CORS_ALLOWED_ORIGINS;
});

test('unauthenticated /ai request → 401', async () => {
  const res = await aiLesson.handler(eventFor({ path: '/ai/lesson', body: { topic: 'x' } }));
  assert.equal(res.statusCode, 401);
  assert.equal(JSON.parse(res.body).error, 'unauthenticated');
});

test('unauthenticated /rag request → 401', async () => {
  const res = await ragLearn.handler(
    eventFor({ path: '/rag/learn', body: { question: 'Article 14?' } }),
  );
  assert.equal(res.statusCode, 401);
  assert.equal(JSON.parse(res.body).error, 'unauthenticated');
});

test('authenticated allowed request → success', async () => {
  const token = mintJwt({ privateKey, kid, uid: 'student-uid' });
  const res = await ragLearn.handler(
    eventFor({
      path: '/rag/learn',
      token,
      body: { question: 'Article 14?', chunks: [] },
    }),
  );
  assert.equal(res.statusCode, 200);
  const payload = JSON.parse(res.body);
  assert.equal(payload.insufficient, true);
  assert.equal(payload.answer, '');
});

test('unauthorized admin operation → 403', async () => {
  const token = mintJwt({ privateKey, kid, uid: 'student-uid' });
  const res = await ragExtract.handler(
    eventFor({
      path: '/rag/extract',
      token,
      body: {
        fileUrl:
          'https://firebasestorage.googleapis.com/v0/b/mpsc-3f4ef.firebasestorage.app/o/notes%2Fa.pdf?alt=media',
      },
    }),
  );
  assert.equal(res.statusCode, 403);
  assert.equal(JSON.parse(res.body).error, 'forbidden');
});

test('malicious SSRF URL → rejected', async () => {
  const token = mintJwt({ privateKey, kid, uid: 'admin-uid' });
  const res = await ragExtract.handler(
    eventFor({
      path: '/rag/extract',
      token,
      body: { fileUrl: 'https://evil.example/ssrf.pdf' },
    }),
  );
  assert.equal(res.statusCode, 400);
  assert.match(JSON.parse(res.body).error, /untrusted/i);
});

test('private IP URL → rejected', async () => {
  const token = mintJwt({ privateKey, kid, uid: 'admin-uid' });
  const res = await ragExtract.handler(
    eventFor({
      path: '/rag/extract',
      token,
      body: { fileUrl: 'http://192.168.1.20/internal.pdf' },
    }),
  );
  assert.equal(res.statusCode, 400);
  assert.match(JSON.parse(res.body).error, /untrusted/i);
});

test('inspectPdfUrl blocks localhost, file://, metadata and private IPs', () => {
  const blocked = [
    'http://127.0.0.1/x.pdf',
    'https://localhost/x.pdf',
    'http://10.0.0.5/x.pdf',
    'http://172.16.4.1/x.pdf',
    'http://169.254.169.254/latest/meta-data',
    'file:///etc/passwd',
    'https://example.com/notes.pdf',
    'https://firebasestorage.googleapis.com/v0/b/other-bucket.appspot.com/o/a.pdf',
  ];
  for (const url of blocked) {
    const result = inspectPdfUrl(url);
    assert.equal(result.ok, false, url);
  }
  assert.equal(isPrivateIPv4('10.1.2.3'), true);
  assert.equal(isPrivateIPv4('192.168.0.1'), true);
  assert.equal(isBlockedHostname('127.0.0.1'), true);
  assert.equal(isBlockedHostname('::1'), true);

  const allowed = inspectPdfUrl(
    'https://firebasestorage.googleapis.com/v0/b/mpsc-3f4ef.firebasestorage.app/o/notes%2Fa.pdf?alt=media&token=x',
  );
  assert.equal(allowed.ok, true);
});

test('CORS is origin-restricted and never *', () => {
  process.env.CONTEXT = 'production';
  const origin = 'https://evil.example';
  assert.equal(
    isOriginAllowed(origin, { headers: { host: 'mpsc-ai.netlify.app' } }),
    false,
  );
  const headers = corsHeaders({
    headers: { origin, host: 'mpsc-ai.netlify.app' },
  });
  assert.notEqual(headers['Access-Control-Allow-Origin'], '*');
  assert.equal(headers['Access-Control-Allow-Origin'], undefined);

  const studentOrigin = 'https://mpsc-3f4ef.web.app';
  const allowed = corsHeaders({
    headers: { origin: studentOrigin, host: 'mpsc-ai.netlify.app' },
  });
  assert.equal(allowed['Access-Control-Allow-Origin'], studentOrigin);
  assert.match(allowed['Access-Control-Allow-Headers'], /Authorization/);

  const sameOrigin = corsHeaders({
    headers: {
      origin: 'https://mpsc-ai.netlify.app',
      host: 'mpsc-ai.netlify.app',
    },
  });
  assert.equal(sameOrigin['Access-Control-Allow-Origin'], 'https://mpsc-ai.netlify.app');

  const body = json(401, { error: 'unauthenticated' }, {
    headers: { origin, host: 'mpsc-ai.netlify.app' },
  });
  assert.notEqual(body.headers['Access-Control-Allow-Origin'], '*');
});

test('API secrets are not in the production Flutter web build script', () => {
  const script = fs.readFileSync(
    path.join(__dirname, '..', '..', 'tool', 'netlify_build.sh'),
    'utf8',
  );
  assert.equal(/\nDEFINES=\(\)/.test(script) || script.includes('DEFINES=()'), true);
  assert.equal(/--dart-define=["']?AI_API_KEY/.test(script), false);
  assert.equal(/--dart-define=["']?ELEVENLABS_API_KEY/.test(script), false);
  assert.equal(/--dart-define=["']?VERTEX_/.test(script), false);
  assert.match(script, /Does NOT pass AI_API_KEY/);
});

test('invalid Firebase ID token → 401', async () => {
  await assert.rejects(
    () => verifyFirebaseIdToken('not-a-jwt'),
    (e) => e.statusCode === 401,
  );
  const res = await ragLearn.handler(
    eventFor({
      token: 'aaaa.bbbb.cccc',
      body: { question: 'hi' },
    }),
  );
  assert.equal(res.statusCode, 401);
});

test('Vertex admin endpoint keeps fallback body for unconfigured Vertex', async () => {
  const token = mintJwt({ privateKey, kid, uid: 'admin-uid' });
  delete process.env.VERTEX_PROJECT;
  delete process.env.VERTEX_ACCESS_TOKEN;
  delete process.env.VERTEX_SERVICE_ACCOUNT_JSON;
  const res = await ragVertexEmbed.handler(
    eventFor({
      path: '/rag/vertex-embed',
      token,
      body: { texts: ['hello'] },
    }),
  );
  assert.equal(res.statusCode, 503);
  const payload = JSON.parse(res.body);
  assert.equal(payload.fallback, true);
  assert.equal(payload.error, 'Vertex AI is not configured');
});

test('student cannot call Vertex admin endpoint', async () => {
  const token = mintJwt({ privateKey, kid, uid: 'student-uid' });
  const res = await ragVertexEmbed.handler(
    eventFor({
      path: '/rag/vertex-embed',
      token,
      body: { texts: ['hello'] },
    }),
  );
  assert.equal(res.statusCode, 403);
});

test('unauthenticated /rag/retrieve → 401', async () => {
  const res = await ragRetrieve.handler(
    eventFor({ path: '/rag/retrieve', body: { query: 'Article 14' } }),
  );
  assert.equal(res.statusCode, 401);
  assert.equal(JSON.parse(res.body).error, 'unauthenticated');
});

test('authenticated /rag/retrieve returns top-K hits without embeddings', async () => {
  const values = Array(768).fill(0);
  values[0] = 1;
  setRetrieveHooksForTests({
    embedQuery: async () => ({ values, provider: 'vertex' }),
    findNearest: async () => [
      {
        id: 'c1',
        sourceId: 's1',
        sourceTitle: 'Article 14',
        subject: 'Polity',
        subjectId: 'pol',
        chapter: 'FR',
        chapterId: 'fr',
        topicId: 'a14',
        contentType: 'notes_pdf',
        examId: 'mpsc_combine',
        ragDomain: 'notes_rag',
        text: 'Article 14 equality',
        published: true,
        keywords: ['article', '14'],
        embedding: values,
      },
    ],
    getSources: async () => [{ id: 's1', published: true, status: 'Ready' }],
  });
  const token = mintJwt({ privateKey, kid, uid: 'student-uid' });
  const res = await ragRetrieve.handler(
    eventFor({
      path: '/rag/retrieve',
      token,
      body: { query: 'Article 14', topK: 1, hybrid: false },
    }),
  );
  assert.equal(res.statusCode, 200);
  const payload = JSON.parse(res.body);
  assert.equal(payload.fallback, undefined);
  assert.equal(payload.hits.length, 1);
  assert.equal(payload.hits[0].chunk.id, 'c1');
  assert.equal(payload.hits[0].chunk.embedding, undefined);
  assert.equal(payload.embeddingModel, 'gemini-embedding-001');
  assert.equal(payload.embeddingDimensions, 768);
});
