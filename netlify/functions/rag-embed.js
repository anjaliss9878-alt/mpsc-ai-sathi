const { json } = require('../lib/cors');
const { withAuth } = require('../lib/auth');
const { embedTextsPreferVertex } = require('../lib/vertex');

exports.handler = async (event) => {
  const gated = await withAuth(event);
  if (gated.halt) return gated.halt;
  try {
    const map = JSON.parse(event.body || '{}');
    const texts = Array.isArray(map.texts) ? map.texts.map((t) => `${t || ''}`) : [];
    if (!texts.length) return json(400, { error: 'texts required' }, event);
    if (texts.length > 32) {
      return json(400, { error: 'at most 32 texts per request' }, event);
    }
    const task = `${map.task || 'document'}`.trim();
    const result = await embedTextsPreferVertex({ texts, task });
    return json(200, result, event);
  } catch (e) {
    return json(500, { error: e.publicMessage || 'embedding failure' }, event);
  }
};
