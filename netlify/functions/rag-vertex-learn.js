const { json } = require('../lib/cors');
const { withAuth } = require('../lib/auth');
const { isVertexConfigured, learnGroundedVertex } = require('../lib/vertex');

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
    const mode = `${map.mode || 'answer'}`.trim();
    const question = `${map.question || ''}`.trim();
    if (!question) return json(400, { error: 'question required' }, event);
    const chunks = Array.isArray(map.chunks) ? map.chunks : [];
    if (!chunks.length) {
      return json(200, {
        insufficient: true,
        answer: '',
        provider: 'vertex',
      }, event);
    }
    const result = await learnGroundedVertex({
      mode,
      question,
      chunks,
      history: Array.isArray(map.history) ? map.history : [],
      teachingStyle: `${map.teachingStyle || ''}`,
    });
    return json(200, result, event);
  } catch (e) {
    const status = e.vertexUnavailable ? 503 : 500;
    return json(status, {
      error: e.publicMessage || 'Vertex generation failed',
      fallback: true,
    }, event);
  }
};
