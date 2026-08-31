const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.FIREBASE_PROJECT_ID = 'mpsc-3f4ef';

const {
  retrieveRag,
  matchesFilters,
  inferDomain,
  cosineSimilarity,
  setRetrieveHooksForTests,
  resetRetrieveHooksForTests,
  EMBED_DIMENSIONS,
} = require('./rag_retrieve');

function vec(seed) {
  const v = Array(EMBED_DIMENSIONS).fill(0);
  v[0] = seed;
  v[1] = 1 - seed;
  const n = Math.sqrt(v.reduce((s, x) => s + x * x, 0));
  return v.map((x) => x / n);
}

function chunk({
  id,
  sourceId,
  text,
  published = true,
  examId = 'mpsc_combine',
  subjectId = 'pol',
  chapterId = 'fr',
  topicId = 'a14',
  ragDomain = 'notes_rag',
  embedding,
}) {
  return {
    id,
    sourceId,
    sourceTitle: text,
    subject: 'Polity',
    subjectId,
    chapter: 'FR',
    chapterId,
    topicId,
    contentType: ragDomain.startsWith('pyq') ? 'pyq' : 'notes_pdf',
    examId,
    ragDomain,
    text,
    published,
    keywords: text.toLowerCase().split(' '),
    embedding: embedding || vec(0.9),
  };
}

test.afterEach(() => {
  resetRetrieveHooksForTests();
});

test('top-K retrieval returns only the nearest published Ready chunks', async () => {
  const qv = vec(0.95);
  setRetrieveHooksForTests({
    embedQuery: async () => ({ values: qv, provider: 'vertex' }),
    findNearest: async () => [
      chunk({ id: 'c1', sourceId: 's1', text: 'Article 14 equality', embedding: vec(0.95) }),
      chunk({ id: 'c2', sourceId: 's1', text: 'Article 19 speech', embedding: vec(0.2) }),
      chunk({ id: 'c3', sourceId: 's1', text: 'Article 21 life', embedding: vec(0.1) }),
    ],
    getSources: async () => [
      { id: 's1', published: true, status: 'Ready' },
    ],
  });
  const out = await retrieveRag({ query: 'Article 14', topK: 1, hybrid: false });
  assert.equal(out.hits.length, 1);
  assert.equal(out.hits[0].chunk.id, 'c1');
  assert.equal(out.embeddingModel, 'gemini-embedding-001');
  assert.equal(out.embeddingDimensions, 768);
  assert.equal(out.vectorIndex, 'firestore.ragChunks.embedding');
  assert.ok(!('embedding' in out.hits[0].chunk));
});

test('unpublished chunks are excluded even if the vector index returns them', async () => {
  setRetrieveHooksForTests({
    embedQuery: async () => ({ values: vec(0.9), provider: 'gemini' }),
    findNearest: async () => [
      chunk({
        id: 'draft',
        sourceId: 's1',
        text: 'secret draft',
        published: false,
        embedding: vec(0.99),
      }),
      chunk({
        id: 'live',
        sourceId: 's2',
        text: 'Article 14',
        published: true,
        embedding: vec(0.8),
      }),
    ],
    getSources: async () => [
      { id: 's1', published: false, status: 'Ready' },
      { id: 's2', published: true, status: 'Ready' },
    ],
  });
  const out = await retrieveRag({ query: 'Article 14', hybrid: false });
  assert.deepEqual(out.hits.map((h) => h.chunk.id), ['live']);
});

test('Processing/Failed parent sources are excluded', async () => {
  setRetrieveHooksForTests({
    embedQuery: async () => ({ values: vec(0.9), provider: 'vertex' }),
    findNearest: async () => [
      chunk({ id: 'p', sourceId: 'proc', text: 'processing', embedding: vec(0.99) }),
      chunk({ id: 'f', sourceId: 'fail', text: 'failed', embedding: vec(0.98) }),
      chunk({ id: 'ok', sourceId: 'ok', text: 'ready', embedding: vec(0.5) }),
    ],
    getSources: async () => [
      { id: 'proc', published: true, status: 'Processing' },
      { id: 'fail', published: true, status: 'Failed' },
      { id: 'ok', published: true, status: 'Ready' },
    ],
  });
  const out = await retrieveRag({ query: 'ready', hybrid: false });
  assert.deepEqual(out.hits.map((h) => h.chunk.id), ['ok']);
});

test('wrong exam and topic are excluded', async () => {
  setRetrieveHooksForTests({
    embedQuery: async () => ({ values: vec(0.9), provider: 'vertex' }),
    findNearest: async () => [
      chunk({
        id: 'wrong-exam',
        sourceId: 's1',
        text: 'Article 14',
        examId: 'upsc',
      }),
      chunk({
        id: 'wrong-topic',
        sourceId: 's1',
        text: 'Article 14',
        topicId: 'a19',
      }),
      chunk({
        id: 'ok',
        sourceId: 's1',
        text: 'Article 14 equality',
        examId: 'mpsc_combine',
        topicId: 'a14',
      }),
    ],
    getSources: async () => [{ id: 's1', published: true, status: 'Ready' }],
  });
  const out = await retrieveRag({
    query: 'Article 14',
    examId: 'mpsc_combine',
    topicId: 'a14',
    hybrid: false,
  });
  assert.deepEqual(out.hits.map((h) => h.chunk.id), ['ok']);
});

test('empty retrieval returns no hits (insufficient evidence)', async () => {
  setRetrieveHooksForTests({
    embedQuery: async () => ({ values: vec(0.5), provider: 'gemini' }),
    findNearest: async () => [],
    getSources: async () => [],
  });
  const out = await retrieveRag({ query: 'unknown topic xyz' });
  assert.equal(out.hits.length, 0);
});

test('Vertex embed failure falls back to Gemini embeddings', async () => {
  let vertexCalls = 0;
  let geminiCalls = 0;
  setRetrieveHooksForTests({
    embedVertex: async () => {
      vertexCalls += 1;
      throw new Error('Vertex unavailable');
    },
    embedGemini: async () => {
      geminiCalls += 1;
      return [vec(0.7)];
    },
    findNearest: async () => [
      chunk({ id: 'ok', sourceId: 's1', text: 'Article 14', embedding: vec(0.7) }),
    ],
    getSources: async () => [{ id: 's1', published: true, status: 'Ready' }],
  });
  const out = await retrieveRag({ query: 'Article 14', hybrid: false });
  assert.equal(vertexCalls, 1);
  assert.equal(geminiCalls, 1);
  assert.equal(out.embeddingProvider, 'gemini');
  assert.equal(out.embeddingModel, 'gemini-embedding-001');
  assert.equal(out.embeddingDimensions, 768);
  assert.equal(out.hits.length, 1);
});

test('retrieve never reads another student performance collection', async () => {
  let sourceCollections = [];
  setRetrieveHooksForTests({
    embedQuery: async () => ({ values: vec(0.9), provider: 'vertex' }),
    findNearest: async () => [
      chunk({ id: 'ok', sourceId: 's1', text: 'Article 14' }),
    ],
    getSources: async (ids) => {
      sourceCollections = ids;
      return [{ id: 's1', published: true, status: 'Ready' }];
    },
  });
  const out = await retrieveRag({
    query: 'Article 14',
    domains: ['notes_rag', 'student_performance_rag'],
    studentUid: 'student-b',
  });
  assert.ok(sourceCollections.every((id) => id !== 'student_performance'));
  assert.ok(out.hits.every((h) => h.chunk.sourceId !== 'student_performance'));
  assert.equal(inferDomain({ ragDomain: 'notes_rag' }), 'notes_rag');
});

test('student_performance chunks are never returned from Firestore retrieve', async () => {
  setRetrieveHooksForTests({
    embedQuery: async () => ({ values: vec(0.99), provider: 'vertex' }),
    findNearest: async () => [
      chunk({
        id: 'perf',
        sourceId: 'student_performance',
        text: 'Student B secret score 12%',
        ragDomain: 'student_performance_rag',
        embedding: vec(0.99),
      }),
      chunk({
        id: 'ok',
        sourceId: 's1',
        text: 'Article 14',
        ragDomain: 'notes_rag',
        embedding: vec(0.8),
      }),
    ],
    getSources: async () => [
      { id: 'student_performance', published: true, status: 'Ready' },
      { id: 's1', published: true, status: 'Ready' },
    ],
  });
  const out = await retrieveRag({ query: 'Article 14', hybrid: false });
  assert.deepEqual(out.hits.map((h) => h.chunk.id), ['ok']);
});

test('six RAG domains still map from chunk metadata', () => {
  assert.equal(inferDomain({ ragDomain: 'notes_rag' }), 'notes_rag');
  assert.equal(inferDomain({ ragDomain: 'pyq_rag' }), 'pyq_rag');
  assert.equal(inferDomain({ ragDomain: 'syllabus_rag' }), 'syllabus_rag');
  assert.equal(inferDomain({ ragDomain: 'current_affairs_rag' }), 'current_affairs_rag');
  assert.equal(inferDomain({ ragDomain: 'ai_teacher_rag' }), 'ai_teacher_rag');
  assert.equal(
    inferDomain({ ragDomain: 'student_performance_rag' }),
    'student_performance_rag',
  );
});

test('cosine helper and published filter helpers', () => {
  const a = vec(1);
  assert.equal(cosineSimilarity(a, a), 1);
  assert.equal(
    matchesFilters(
      chunk({ id: 'x', sourceId: 's', text: 't', published: false }),
      {},
    ),
    false,
  );
});
