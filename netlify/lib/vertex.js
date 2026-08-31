const crypto = require('crypto');
const { learnGrounded, learnSystemPrompt, learnUserText, EMBED_DIMENSIONS } =
  require('./gemini');

const VERTEX_EMBED_MODEL = 'gemini-embedding-001';
const VERTEX_GENERATE_MODELS = [
  'gemini-2.0-flash',
  'gemini-2.5-flash',
  'gemini-flash-lite-latest',
];

function vertexUnavailable(message) {
  return Object.assign(new Error(message), {
    publicMessage: message,
    vertexUnavailable: true,
    statusCode: 503,
  });
}

function vertexProject() {
  return (
    process.env.VERTEX_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    ''
  ).trim();
}

function vertexLocation() {
  return (process.env.VERTEX_LOCATION || 'us-central1').trim() || 'us-central1';
}

function vertexEmbedModel() {
  return (process.env.VERTEX_EMBED_MODEL || VERTEX_EMBED_MODEL).trim();
}

function vertexGenerateModels() {
  const preferred = (process.env.VERTEX_MODEL || '').trim();
  const models = [];
  if (preferred) models.push(preferred);
  for (const m of VERTEX_GENERATE_MODELS) {
    if (!models.includes(m)) models.push(m);
  }
  return models;
}

function isVertexConfigured() {
  const project = vertexProject();
  const token = (process.env.VERTEX_ACCESS_TOKEN || '').trim();
  const sa = (process.env.VERTEX_SERVICE_ACCOUNT_JSON || '').trim();
  return Boolean(project && (token || sa));
}

function vertexApiRoot(project, location) {
  if (location === 'global') {
    return `https://aiplatform.googleapis.com/v1/projects/${project}/locations/global`;
  }
  return `https://${location}-aiplatform.googleapis.com/v1/projects/${project}/locations/${location}`;
}

function vertexModelUrl(model, method) {
  const project = vertexProject();
  const location = vertexLocation();
  if (!project) {
    throw vertexUnavailable('VERTEX_PROJECT missing');
  }
  return `${vertexApiRoot(project, location)}/publishers/google/models/${model}:${method}`;
}

function toBase64Url(input) {
  const buf = Buffer.isBuffer(input) ? input : Buffer.from(input);
  return buf
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function parseServiceAccount() {
  const raw = (process.env.VERTEX_SERVICE_ACCOUNT_JSON || '').trim();
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch (_) {
    throw vertexUnavailable('VERTEX_SERVICE_ACCOUNT_JSON is not valid JSON');
  }
}

async function mintAccessToken() {
  const preset = (process.env.VERTEX_ACCESS_TOKEN || '').trim();
  if (preset) return preset;

  const sa = parseServiceAccount();
  if (!sa || !sa.client_email || !sa.private_key) {
    throw vertexUnavailable('Vertex AI is not configured');
  }

  const now = Math.floor(Date.now() / 1000);
  const header = toBase64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = toBase64Url(
    JSON.stringify({
      iss: sa.client_email,
      sub: sa.client_email,
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
      scope: 'https://www.googleapis.com/auth/cloud-platform',
    }),
  );
  const unsigned = `${header}.${claim}`;
  const sign = crypto.createSign('RSA-SHA256');
  sign.update(unsigned);
  const signature = toBase64Url(sign.sign(sa.private_key));
  const assertion = `${unsigned}.${signature}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=${encodeURIComponent(
      'urn:ietf:params:oauth:grant-type:jwt-bearer',
    )}&assertion=${encodeURIComponent(assertion)}`,
  });
  const raw = await res.text();
  if (res.status !== 200) {
    throw vertexUnavailable('Vertex AI unauthorized');
  }
  let payload;
  try {
    payload = JSON.parse(raw);
  } catch (_) {
    throw vertexUnavailable('Vertex AI unauthorized');
  }
  const token = `${payload.access_token || ''}`.trim();
  if (!token) throw vertexUnavailable('Vertex AI unauthorized');
  return token;
}

function classifyVertexHttp(status, body) {
  const lower = `${body || ''}`.toLowerCase();
  if (status === 401 || status === 403) return 'Vertex AI unauthorized';
  if (status === 404) return 'Vertex model not found';
  if (status === 429 || lower.includes('quota')) return 'Vertex quota exceeded';
  if (status === 400) return 'Vertex invalid request';
  if (status === 503) return 'Vertex network error';
  return 'Vertex AI request failed';
}

function extractGenerateText(payload) {
  const parts = payload?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts) || parts.length === 0) return '';
  return `${parts[0].text || ''}`.trim();
}

function parseEmbeddingValues(payload) {
  const direct = payload?.embedding?.values;
  if (Array.isArray(direct)) return direct;
  const pred = payload?.predictions?.[0];
  const nested =
    pred?.embeddings?.values ||
    pred?.values ||
    pred?.embedding?.values;
  if (Array.isArray(nested)) return nested;
  return null;
}

async function embedOneVertex({ text, task, token }) {
  const taskType = task === 'query' ? 'RETRIEVAL_QUERY' : 'RETRIEVAL_DOCUMENT';
  const clipped = `${text || ''}`.slice(0, 8000);
  const url = vertexModelUrl(vertexEmbedModel(), 'embedContent');
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      content: { parts: [{ text: clipped }] },
      taskType,
      outputDimensionality: EMBED_DIMENSIONS,
    }),
  });
  const raw = await res.text();
  if (res.status !== 200) {
    throw Object.assign(new Error(classifyVertexHttp(res.status, raw)), {
      publicMessage: classifyVertexHttp(res.status, raw),
      vertexUnavailable: res.status === 401 || res.status === 403 || res.status === 404,
    });
  }
  let payload;
  try {
    payload = JSON.parse(raw);
  } catch (_) {
    throw Object.assign(new Error('embedding failure'), {
      publicMessage: 'embedding failure',
    });
  }
  const values = parseEmbeddingValues(payload);
  if (!Array.isArray(values) || values.length !== EMBED_DIMENSIONS) {
    throw Object.assign(new Error('embedding failure'), {
      publicMessage: 'embedding failure',
    });
  }
  return values;
}

async function embedTextsVertex({ texts, task = 'document' }) {
  if (!isVertexConfigured()) {
    throw vertexUnavailable('Vertex AI is not configured');
  }
  const token = await mintAccessToken();
  const embeddings = [];
  for (const text of texts) {
    embeddings.push(await embedOneVertex({ text, task, token }));
  }
  return embeddings;
}

async function generateContentVertex({ systemPrompt, userText }) {
  const token = await mintAccessToken();
  let lastError = 'Vertex AI request failed';
  for (const model of vertexGenerateModels()) {
    const url = vertexModelUrl(model, 'generateContent');
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemPrompt }] },
        contents: [{ role: 'user', parts: [{ text: userText }] }],
        generationConfig: {
          responseMimeType: 'application/json',
          temperature: 0.35,
          maxOutputTokens: 8192,
        },
      }),
    });
    const raw = await res.text();
    if (res.status === 200) {
      let payload;
      try {
        payload = JSON.parse(raw);
      } catch (_) {
        lastError = 'response parsing error';
        continue;
      }
      const text = extractGenerateText(payload);
      if (!text) {
        lastError = 'response parsing error';
        continue;
      }
      try {
        return JSON.parse(text);
      } catch (_) {
        lastError = 'response parsing error';
        continue;
      }
    }
    if (res.status === 401 || res.status === 403) {
      throw vertexUnavailable('Vertex AI unauthorized');
    }
    lastError = classifyVertexHttp(res.status, raw);
  }
  throw Object.assign(new Error(lastError), { publicMessage: lastError });
}

async function learnGroundedVertex({
  mode,
  question,
  chunks,
  history,
  teachingStyle,
}) {
  if (!isVertexConfigured()) {
    throw vertexUnavailable('Vertex AI is not configured');
  }
  const allowed = new Set([
    'answer',
    'summary',
    'mcq',
    'flashcards',
    'revision',
    'memory',
  ]);
  const m = allowed.has(mode) ? mode : 'answer';
  if (!Array.isArray(chunks) || chunks.length === 0) {
    return { insufficient: true, answer: '', provider: 'vertex' };
  }
  const parsed = await generateContentVertex({
    systemPrompt: learnSystemPrompt(m, teachingStyle),
    userText: learnUserText({ mode: m, question, chunks, history }),
  });
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw Object.assign(new Error('invalid learn JSON'), {
      publicMessage: 'Vertex returned invalid JSON',
    });
  }
  return { ...parsed, provider: 'vertex' };
}

module.exports = {
  isVertexConfigured,
  vertexProject,
  vertexLocation,
  vertexApiRoot,
  vertexModelUrl,
  parseEmbeddingValues,
  embedTextsVertex,
  learnGroundedVertex,
  vertexUnavailable,
  learnGrounded,
  mintAccessToken,
};
