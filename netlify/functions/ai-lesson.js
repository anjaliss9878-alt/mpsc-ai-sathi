const { json } = require('../lib/cors');
const { withAuth } = require('../lib/auth');
const { generateContent, compactLessonPrompt } = require('../lib/gemini');

exports.handler = async (event) => {
  const gated = await withAuth(event);
  if (gated.halt) return gated.halt;
  try {
    const map = JSON.parse(event.body || '{}');
    const topic = `${map.topic || ''}`.trim();
    const teachingSubject = `${map.teachingSubject || ''}`.trim();
    if (!topic) return json(400, { error: 'topic required' }, event);
    const prompt = compactLessonPrompt(topic, teachingSubject);
    const lesson = await generateContent({
      systemPrompt: prompt.system,
      userText: prompt.user,
      jsonMode: true,
    });
    if (!lesson || typeof lesson !== 'object') {
      return json(500, { error: 'response parsing error' }, event);
    }
    if (!lesson.topicName) lesson.topicName = lesson.title || topic;
    if (!lesson.subjectName) {
      lesson.subjectName = lesson.subject || teachingSubject || 'MPSC Combine';
    }
    lesson.question = topic;
    return json(200, { lesson }, event);
  } catch (e) {
    return json(500, { error: e.publicMessage || 'invalid request' }, event);
  }
};
