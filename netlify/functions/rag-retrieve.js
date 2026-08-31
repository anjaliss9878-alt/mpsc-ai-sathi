const { json } = require('../lib/cors');
const { withAuth } = require('../lib/auth');
const { retrieveRag } = require('../lib/rag_retrieve');

exports.handler = async (event) => {
  const gated = await withAuth(event);
  if (gated.halt) return gated.halt;
  try {
    const map = JSON.parse(event.body || '{}');
    const query = `${map.query || map.question || ''}`.trim();
    if (!query) return json(400, { error: 'query required' }, event);
    const result = await retrieveRag({
      query,
      examId: `${map.examId || ''}`,
      subjectId: `${map.subjectId || ''}`,
      chapterId: `${map.chapterId || ''}`,
      topicId: `${map.topicId || ''}`,
      domains: Array.isArray(map.domains) ? map.domains : [],
      sourceIds: Array.isArray(map.sourceIds) ? map.sourceIds : [],
      topK: Number(map.topK) || 8,
      similarityThreshold:
        map.similarityThreshold == null ? 0.05 : Number(map.similarityThreshold),
      hybrid: map.hybrid !== false,
      userToken: gated.user.token,
    });
    return json(200, result, event);
  } catch (e) {
    return json(
      200,
      {
        hits: [],
        fallback: true,
        error: e.publicMessage || 'vector retrieval failed',
      },
      event,
    );
  }
};
