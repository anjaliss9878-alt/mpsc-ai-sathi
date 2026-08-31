const { json } = require('../lib/cors');
const { withAuth } = require('../lib/auth');
const { embedTextsVertex, isVertexConfigured } = require('../lib/vertex');

exports.handler = async (event) => {
  const gated = await withAuth(event, { admin: true });
  if (gated.halt) return gated.halt;
  try {
    if (!isVertexConfigured()) {
      return json(503, {
        error: 'Vertex AI is not configured',
        fallback: true,
      }, event);
    }
    const map = JSON.parse(event.body || '{}');
    const texts = Array.isArray(map.texts)
      ? map.texts.map((t) => `${t || ''}`)
      : [];
    if (!texts.length) return json(400, { error: 'texts required' }, event);
    if (texts.length > 32) {
      return json(400, { error: 'at most 32 texts per request' }, event);
    }
    const task = `${map.task || 'document'}`.trim();
    const embeddings = await embedTextsVertex({ texts, task });
    return json(200, { embeddings, provider: 'vertex' }, event);
  } catch (e) {
    const status = e.vertexUnavailable ? 503 : 500;
    return json(status, {
      error: e.publicMessage || 'Vertex embedding failure',
      fallback: true,
    }, event);
  }
};
