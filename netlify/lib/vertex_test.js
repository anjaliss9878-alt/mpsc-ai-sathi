const test = require('node:test');
const assert = require('node:assert/strict');
const {
  isVertexConfigured,
  vertexApiRoot,
  parseEmbeddingValues,
} = require('./vertex');

test('Vertex is off without project and credentials', () => {
  const prev = {
    VERTEX_PROJECT: process.env.VERTEX_PROJECT,
    GOOGLE_CLOUD_PROJECT: process.env.GOOGLE_CLOUD_PROJECT,
    VERTEX_ACCESS_TOKEN: process.env.VERTEX_ACCESS_TOKEN,
    VERTEX_SERVICE_ACCOUNT_JSON: process.env.VERTEX_SERVICE_ACCOUNT_JSON,
  };
  delete process.env.VERTEX_PROJECT;
  delete process.env.GOOGLE_CLOUD_PROJECT;
  delete process.env.VERTEX_ACCESS_TOKEN;
  delete process.env.VERTEX_SERVICE_ACCOUNT_JSON;
  try {
    assert.equal(isVertexConfigured(), false);
  } finally {
    for (const [k, v] of Object.entries(prev)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  }
});

test('Vertex is configured with project + access token', () => {
  const prevP = process.env.VERTEX_PROJECT;
  const prevT = process.env.VERTEX_ACCESS_TOKEN;
  process.env.VERTEX_PROJECT = 'mpsc-test';
  process.env.VERTEX_ACCESS_TOKEN = 'test-token';
  try {
    assert.equal(isVertexConfigured(), true);
  } finally {
    if (prevP === undefined) delete process.env.VERTEX_PROJECT;
    else process.env.VERTEX_PROJECT = prevP;
    if (prevT === undefined) delete process.env.VERTEX_ACCESS_TOKEN;
    else process.env.VERTEX_ACCESS_TOKEN = prevT;
  }
});

test('regional and global Vertex URLs', () => {
  assert.equal(
    vertexApiRoot('p1', 'us-central1'),
    'https://us-central1-aiplatform.googleapis.com/v1/projects/p1/locations/us-central1',
  );
  assert.equal(
    vertexApiRoot('p1', 'global'),
    'https://aiplatform.googleapis.com/v1/projects/p1/locations/global',
  );
});

test('parseEmbeddingValues reads embedContent and predict shapes', () => {
  const values = Array.from({ length: 768 }, (_, i) => i);
  assert.deepEqual(parseEmbeddingValues({ embedding: { values } }), values);
  assert.deepEqual(
    parseEmbeddingValues({ predictions: [{ embeddings: { values } }] }),
    values,
  );
  assert.equal(parseEmbeddingValues({}), null);
});
