const { json } = require('../lib/cors');
const { withAuth } = require('../lib/auth');
const { extractPdfFromUrl } = require('../lib/gemini');

exports.handler = async (event) => {
  const gated = await withAuth(event, { admin: true });
  if (gated.halt) return gated.halt;
  try {
    const map = JSON.parse(event.body || '{}');
    const fileUrl = `${map.fileUrl || ''}`.trim();
    const title = `${map.title || ''}`.trim();
    if (!fileUrl) return json(400, { error: 'fileUrl required' }, event);
    const result = await extractPdfFromUrl({ fileUrl, title });
    return json(200, result, event);
  } catch (e) {
    const msg = e.publicMessage || 'PDF extraction failed';
    const code =
      e.statusCode || (msg.toLowerCase().includes('empty') ? 422 : 500);
    return json(code, { error: msg }, event);
  }
};
