/**
 * Server-side vector retrieval over existing `ragChunks` / `ragSources`.
 * Embedding: gemini-embedding-001 @ 768-d (Vertex first, Gemini fallback).
 * Vector index: Firestore ragChunks.embedding (cosine, 768).
 */
const { embedTexts, EMBED_DIMENSIONS } = require('./gemini');
const {
  embedTextsVertex,
  isVertexConfigured,
  mintAccessToken,
} = require('./vertex');
const { firebaseProjectId } = require('./auth');

const VECTOR_LIMIT = 40;
const DEFAULT_TOP_K = 8;
const READY = 'Ready';

const hooks = {
  embedQuery: null,
  embedVertex: null,
  embedGemini: null,
  findNearest: null,
  getSources: null,
};

function setRetrieveHooksForTests(next = {}) {
  const inTest =
    process.env.NODE_TEST_CONTEXT != null || process.env.NODE_ENV === 'test';
  if (!inTest) {
    throw new Error('setRetrieveHooksForTests is test-only');
  }
  if (next.embedQuery) hooks.embedQuery = next.embedQuery;
  if (next.embedVertex) hooks.embedVertex = next.embedVertex;
  if (next.embedGemini) hooks.embedGemini = next.embedGemini;
  if (next.findNearest) hooks.findNearest = next.findNearest;
  if (next.getSources) hooks.getSources = next.getSources;
}

function resetRetrieveHooksForTests() {
  hooks.embedQuery = null;
  hooks.embedVertex = null;
  hooks.embedGemini = null;
  hooks.findNearest = null;
  hooks.getSources = null;
}

function cosineSimilarity(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length || !a.length) {
    return 0;
  }
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i++) {
    const x = Number(a[i]) || 0;
    const y = Number(b[i]) || 0;
    dot += x * y;
    na += x * x;
    nb += y * y;
  }
  if (na <= 0 || nb <= 0) return 0;
  const sim = dot / (Math.sqrt(na) * Math.sqrt(nb));
  if (!Number.isFinite(sim) || sim < 0) return 0;
  return sim > 1 ? 1 : sim;
}

function keywordTokens(text, limit = 24) {
  const raw = `${text || ''}`.toLowerCase();
  const parts = raw.split(/[^\p{L}\p{N}]+/u).filter((t) => t.length >= 2);
  const seen = new Set();
  const out = [];
  for (const t of parts) {
    if (seen.has(t)) continue;
    seen.add(t);
    out.push(t);
    if (out.length >= limit) break;
  }
  return out;
}

function keywordScore(tokens, haystack) {
  if (!tokens.length) return 0;
  const h = `${haystack || ''}`.toLowerCase();
  if (!h) return 0;
  let hits = 0;
  let usable = 0;
  for (const t of tokens) {
    if (t.length < 2) continue;
    usable += 1;
    if (h.includes(t)) hits += 1;
  }
  return usable === 0 ? 0 : hits / usable;
}

function decodeValue(v) {
  if (v == null || typeof v !== 'object') return null;
  if ('stringValue' in v) return v.stringValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('nullValue' in v) return null;
  if ('vectorValue' in v) {
    return (v.vectorValue.values || []).map((n) => Number(n) || 0);
  }
  if ('arrayValue' in v) {
    return (v.arrayValue.values || []).map(decodeValue);
  }
  if ('mapValue' in v) {
    const out = {};
    for (const [k, val] of Object.entries(v.mapValue.fields || {})) {
      out[k] = decodeValue(val);
    }
    return out;
  }
  return null;
}

function fieldsToMap(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields || {})) {
    out[k] = decodeValue(v);
  }
  return out;
}

function docIdFromName(name) {
  const parts = `${name || ''}`.split('/');
  return parts[parts.length - 1] || '';
}

function inferDomain(chunk) {
  const explicit = `${chunk.ragDomain || ''}`.toLowerCase().replace(/-/g, '_');
  if (explicit.includes('pyq')) return 'pyq_rag';
  if (explicit.includes('syllabus')) return 'syllabus_rag';
  if (explicit.includes('current_affair')) return 'current_affairs_rag';
  if (explicit.includes('ai_teacher') || explicit.includes('ai_lesson')) {
    return 'ai_teacher_rag';
  }
  if (explicit.includes('student_performance')) return 'student_performance_rag';
  if (explicit.includes('notes')) return 'notes_rag';
  const type = `${chunk.contentType || ''}`.toLowerCase();
  if (type === 'pyq' || type === 'pyqs') return 'pyq_rag';
  if (type === 'syllabus' || type === 'chapter') return 'syllabus_rag';
  if (type === 'current_affairs' || type === 'currentaffairs') {
    return 'current_affairs_rag';
  }
  if (type === 'ai_lesson' || type === 'ai_teacher') return 'ai_teacher_rag';
  return 'notes_rag';
}

function knowledgeDomains(domains) {
  const list = Array.isArray(domains) ? domains : [];
  return list
    .map((d) => `${d || ''}`.trim())
    .filter((d) => d && d !== 'student_performance_rag' && d !== 'student_performance');
}

function matchesFilters(chunk, filters) {
  if (chunk.published !== true) return false;
  if (filters.examId && chunk.examId && chunk.examId !== filters.examId) {
    return false;
  }
  if (filters.subjectId && chunk.subjectId && chunk.subjectId !== filters.subjectId) {
    return false;
  }
  if (
    filters.chapterId &&
    chunk.chapterId &&
    chunk.chapterId !== filters.chapterId &&
    chunk.topicId !== filters.chapterId
  ) {
    return false;
  }
  if (filters.topicId) {
    const tid = `${chunk.topicId || ''}`.trim();
    const cid = `${chunk.chapterId || ''}`.trim();
    if (tid !== filters.topicId && cid !== filters.topicId) return false;
  }
  if (Array.isArray(filters.sourceIds) && filters.sourceIds.length) {
    if (!filters.sourceIds.includes(chunk.sourceId)) return false;
  }
  const wanted = knowledgeDomains(filters.domains);
  if (wanted.length) {
    const domain = inferDomain(chunk);
    const aliases = {
      notes_rag: ['notes_rag', 'notes'],
      pyq_rag: ['pyq_rag', 'pyq', 'pyqs'],
      syllabus_rag: ['syllabus_rag', 'syllabus'],
      current_affairs_rag: [
        'current_affairs_rag',
        'current_affairs',
        'currentaffairs',
      ],
      ai_teacher_rag: ['ai_teacher_rag', 'ai_teacher', 'ai_lesson'],
    };
    const names = aliases[domain] || [domain];
    if (!wanted.some((w) => names.includes(w))) return false;
  }
  return true;
}

function publicChunk(chunk) {
  return {
    id: chunk.id,
    sourceId: chunk.sourceId,
    sourceTitle: chunk.sourceTitle,
    subject: chunk.subject,
    subjectId: chunk.subjectId,
    chapter: chunk.chapter,
    chapterId: chunk.chapterId,
    topicId: chunk.topicId,
    noteId: chunk.noteId || '',
    contentType: chunk.contentType,
    exam: chunk.exam || '',
    examId: chunk.examId,
    source: chunk.source || '',
    year: chunk.year == null ? null : chunk.year,
    difficulty: chunk.difficulty || '',
    status: chunk.status || '',
    ragDomain: chunk.ragDomain || inferDomain(chunk),
    pageNumber: chunk.pageNumber == null ? null : chunk.pageNumber,
    chunkIndex: chunk.chunkIndex || 0,
    text: chunk.text,
    language: chunk.language || '',
    sourceType: chunk.sourceType || '',
    published: true,
    keywords: Array.isArray(chunk.keywords) ? chunk.keywords : [],
  };
}

async function embedQueryText(query) {
  if (hooks.embedQuery) return hooks.embedQuery(query);
  const vertexEmbed =
    hooks.embedVertex ||
    (isVertexConfigured() ? embedTextsVertex : null);
  const geminiEmbed = hooks.embedGemini || embedTexts;
  if (typeof vertexEmbed === 'function') {
    try {
      const rows = await vertexEmbed({ texts: [query], task: 'query' });
      if (Array.isArray(rows?.[0]) && rows[0].length === EMBED_DIMENSIONS) {
        return { values: rows[0], provider: 'vertex' };
      }
    } catch (_) {
      // Gemini Developer API fallback — same model + 768-d.
    }
  }
  const rows = await geminiEmbed({ texts: [query], task: 'query' });
  return { values: rows[0], provider: 'gemini' };
}

function toVectorField(values) {
  return {
    arrayValue: {
      values: values.map((n) => ({ doubleValue: Number(n) || 0 })),
    },
  };
}

async function firestoreToken(userToken) {
  try {
    return await mintAccessToken();
  } catch (_) {
    return userToken || '';
  }
}

async function defaultFindNearest({ vector, token, publishedOnly }) {
  const projectId = firebaseProjectId();
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    `/databases/(default)/documents:runQuery`;
  const structuredQuery = {
    from: [{ collectionId: 'ragChunks' }],
    findNearest: {
      vectorField: { fieldPath: 'embedding' },
      queryVector: toVectorField(vector),
      distanceMeasure: 'COSINE',
      limit: VECTOR_LIMIT,
      distanceResultField: 'vectorDistance',
    },
  };
  if (publishedOnly) {
    structuredQuery.where = {
      fieldFilter: {
        field: { fieldPath: 'published' },
        op: 'EQUAL',
        value: { booleanValue: true },
      },
    };
  }
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ structuredQuery }),
  });
  const raw = await res.text();
  if (res.status !== 200) {
    throw Object.assign(new Error('vector search failed'), {
      publicMessage: 'vector search failed',
      statusCode: res.status,
    });
  }
  let rows;
  try {
    rows = JSON.parse(raw);
  } catch (_) {
    throw Object.assign(new Error('vector search failed'), {
      publicMessage: 'vector search failed',
    });
  }
  const chunks = [];
  for (const row of Array.isArray(rows) ? rows : []) {
    const doc = row.document;
    if (!doc || !doc.fields) continue;
    const map = fieldsToMap(doc.fields);
    const embedding =
      (Array.isArray(map.embedding) && map.embedding) ||
      (Array.isArray(map.embeddingValues) && map.embeddingValues) ||
      [];
    chunks.push({
      id: docIdFromName(doc.name),
      sourceId: `${map.sourceId || ''}`,
      sourceTitle: `${map.sourceTitle || ''}`,
      subject: `${map.subject || ''}`,
      subjectId: `${map.subjectId || ''}`,
      chapter: `${map.chapter || ''}`,
      chapterId: `${map.chapterId || ''}`,
      topicId: `${map.topicId || ''}`,
      noteId: `${map.noteId || ''}`,
      contentType: `${map.contentType || ''}`,
      exam: `${map.exam || ''}`,
      examId: `${map.examId || ''}`,
      source: `${map.source || ''}`,
      year: map.year == null || map.year === '' ? null : Number(map.year),
      difficulty: `${map.difficulty || ''}`,
      status: `${map.status || ''}`,
      ragDomain: `${map.ragDomain || ''}`,
      pageNumber:
        map.pageNumber == null || map.pageNumber === ''
          ? null
          : Number(map.pageNumber),
      chunkIndex: Number(map.chunkIndex) || 0,
      text: `${map.text || map.chunkText || ''}`,
      language: `${map.language || ''}`,
      sourceType: `${map.sourceType || ''}`,
      published: map.published === true,
      keywords: Array.isArray(map.keywords) ? map.keywords.map((k) => `${k}`) : [],
      embedding,
      vectorDistance:
        row.vectorDistance == null ? null : Number(row.vectorDistance),
    });
  }
  return chunks;
}

async function defaultGetSources(ids, token) {
  if (!ids.length) return [];
  const projectId = firebaseProjectId();
  const url =
    `https://firestore.googleapis.com/v1/projects/${projectId}` +
    `/databases/(default)/documents:batchGet`;
  const documents = ids.map(
    (id) =>
      `projects/${projectId}/databases/(default)/documents/ragSources/${encodeURIComponent(id)}`,
  );
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ documents }),
  });
  if (res.status !== 200) return [];
  let rows;
  try {
    rows = JSON.parse(await res.text());
  } catch (_) {
    return [];
  }
  const out = [];
  for (const row of Array.isArray(rows) ? rows : []) {
    const doc = row.found;
    if (!doc || !doc.fields) continue;
    const map = fieldsToMap(doc.fields);
    out.push({
      id: docIdFromName(doc.name),
      published: map.published === true,
      status: `${map.status || ''}`,
    });
  }
  return out;
}

function rankHits({ query, candidates, queryVector, topK, threshold, hybrid }) {
  const k = topK < 1 ? DEFAULT_TOP_K : topK;
  const vectorRanked = candidates
    .map((chunk) => {
      let score = 0;
      if (Array.isArray(chunk.embedding) && chunk.embedding.length === queryVector.length) {
        score = cosineSimilarity(queryVector, chunk.embedding);
      } else if (chunk.vectorDistance != null && Number.isFinite(chunk.vectorDistance)) {
        score = Math.max(0, 1 - chunk.vectorDistance);
      }
      return { chunk, vectorScore: score, keywordScore: 0, score };
    })
    .filter((h) => h.vectorScore >= 0)
    .sort((a, b) => b.vectorScore - a.vectorScore);

  if (!hybrid) {
    return vectorRanked
      .filter((h) => h.vectorScore >= threshold)
      .slice(0, k)
      .map((h) => ({ ...h, score: h.vectorScore }));
  }

  const tokens = keywordTokens(query);
  for (const h of vectorRanked) {
    h.keywordScore = keywordScore(
      tokens,
      `${h.chunk.text} ${h.chunk.sourceTitle} ${(h.chunk.keywords || []).join(' ')}`,
    );
  }
  const vectorIds = vectorRanked.map((h) => h.chunk.id);
  const keywordIds = vectorRanked
    .filter((h) => h.keywordScore > 0)
    .sort((a, b) => b.keywordScore - a.keywordScore)
    .map((h) => h.chunk.id);
  const rrf = {};
  const add = (ids) => {
    ids.forEach((id, i) => {
      rrf[id] = (rrf[id] || 0) + 1 / (60 + i + 1);
    });
  };
  add(vectorIds);
  add(keywordIds);
  const byId = Object.fromEntries(vectorRanked.map((h) => [h.chunk.id, h]));
  const merged = Object.entries(rrf)
    .map(([id, score]) => {
      const h = byId[id];
      if (!h) return null;
      return { ...h, score };
    })
    .filter(Boolean)
    .sort((a, b) => b.score - a.score);
  const strong = merged.filter((h) => h.vectorScore >= threshold);
  return (strong.length ? strong : merged).slice(0, k);
}

async function retrieveRag({
  query,
  examId = '',
  subjectId = '',
  chapterId = '',
  topicId = '',
  domains = [],
  sourceIds = [],
  topK = DEFAULT_TOP_K,
  similarityThreshold = 0.05,
  hybrid = true,
  userToken = '',
}) {
  const q = `${query || ''}`.trim();
  if (!q) {
    return {
      hits: [],
      embeddingProvider: '',
      vectorIndex: 'firestore.ragChunks.embedding',
      embeddingModel: 'gemini-embedding-001',
      embeddingDimensions: EMBED_DIMENSIONS,
    };
  }

  const { values, provider } = await embedQueryText(q);
  if (!Array.isArray(values) || values.length !== EMBED_DIMENSIONS) {
    throw Object.assign(new Error('embedding failure'), {
      publicMessage: 'embedding failure',
    });
  }

  const token = await firestoreToken(userToken);
  const findNearest = hooks.findNearest || defaultFindNearest;
  let nearest = [];
  try {
    nearest = await findNearest({
      vector: values,
      token,
      publishedOnly: true,
    });
  } catch (_) {
    try {
      nearest = await findNearest({
        vector: values,
        token,
        publishedOnly: false,
      });
    } catch (err) {
      throw Object.assign(new Error('vector search failed'), {
        publicMessage: err.publicMessage || 'vector search failed',
      });
    }
  }

  const filters = {
    examId: `${examId || ''}`.trim(),
    subjectId: `${subjectId || ''}`.trim(),
    chapterId: `${chapterId || ''}`.trim(),
    topicId: `${topicId || ''}`.trim(),
    domains,
    sourceIds: Array.isArray(sourceIds)
      ? sourceIds.map((id) => `${id}`).filter(Boolean)
      : [],
  };

  const sourceIdSet = [
    ...new Set(nearest.map((c) => c.sourceId).filter(Boolean)),
  ];
  const getSources = hooks.getSources || defaultGetSources;
  const sources = await getSources(sourceIdSet, token);
  const ready = new Set(
    sources
      .filter((s) => s.published === true && s.status === READY)
      .map((s) => s.id),
  );

  const candidates = nearest.filter(
    (c) =>
      c.published === true &&
      ready.has(c.sourceId) &&
      inferDomain(c) !== 'student_performance_rag' &&
      matchesFilters(c, filters),
  );

  const ranked = rankHits({
    query: q,
    candidates,
    queryVector: values,
    topK,
    threshold: similarityThreshold,
    hybrid,
  });

  return {
    hits: ranked.map((h) => ({
      score: h.score,
      vectorScore: h.vectorScore,
      keywordScore: h.keywordScore,
      domain: inferDomain(h.chunk),
      chunk: publicChunk(h.chunk),
    })),
    embeddingProvider: provider,
    vectorIndex: 'firestore.ragChunks.embedding',
    embeddingModel: 'gemini-embedding-001',
    embeddingDimensions: EMBED_DIMENSIONS,
  };
}

module.exports = {
  retrieveRag,
  matchesFilters,
  inferDomain,
  publicChunk,
  cosineSimilarity,
  setRetrieveHooksForTests,
  resetRetrieveHooksForTests,
  EMBED_DIMENSIONS,
  VECTOR_LIMIT,
  READY,
};
