const { json, optionsResponse } = require('../lib/cors');

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') return optionsResponse(event);
  if (event.httpMethod !== 'GET') {
    return json(405, { error: 'method not allowed' }, event);
  }
  return json(200, { ok: true }, event);
};
