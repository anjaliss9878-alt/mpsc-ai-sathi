const { json, optionsResponse } = require('../lib/gemini');

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') return optionsResponse();
  if (event.httpMethod !== 'GET') {
    return json(405, { error: 'method not allowed' });
  }
  return json(200, { ok: true });
};
