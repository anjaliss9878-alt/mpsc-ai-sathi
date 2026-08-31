const { json } = require('../lib/cors');
const { withAuth } = require('../lib/auth');
const { learnGrounded } = require('../lib/gemini');

exports.handler = async (event) => {
  const gated = await withAuth(event);
  if (gated.halt) return gated.halt;
  try {
    const map = JSON.parse(event.body || '{}');
    const mode = `${map.mode || 'answer'}`.trim();
    const question = `${map.question || ''}`.trim();
    if (!question) return json(400, { error: 'question required' }, event);
    const chunks = Array.isArray(map.chunks) ? map.chunks : [];
    if (!chunks.length) {
      return json(200, { insufficient: true, answer: '' }, event);
    }
    const result = await learnGrounded({
      mode,
      question,
      chunks,
      history: Array.isArray(map.history) ? map.history : [],
      teachingStyle: `${map.teachingStyle || ''}`,
    });
    return json(200, result, event);
  } catch (e) {
    return json(500, { error: e.publicMessage || 'Gemini/API request failed' }, event);
  }
};
