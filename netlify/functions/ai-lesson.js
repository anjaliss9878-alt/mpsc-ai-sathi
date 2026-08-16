const { json, optionsResponse, generateContent, compactLessonPrompt } = require('../lib/gemini');

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') return optionsResponse();
  if (event.httpMethod !== 'POST') {
    return json(405, { error: 'method not allowed' });
  }
  try {
    const map = JSON.parse(event.body || '{}');
    const topic = `${map.topic || ''}`.trim();
    const teachingSubject = `${map.teachingSubject || ''}`.trim();
    if (!topic) return json(400, { error: 'topic required' });
    const prompt = compactLessonPrompt(topic, teachingSubject);
    const lesson = await generateContent({
      systemPrompt: prompt.system,
      userText: prompt.user,
      jsonMode: true,
    });
    if (!lesson || typeof lesson !== 'object') {
      return json(500, { error: 'response parsing error' });
    }
    if (!lesson.topicName) lesson.topicName = lesson.title || topic;
    if (!lesson.subjectName) {
      lesson.subjectName = lesson.subject || teachingSubject || 'MPSC Combine';
    }
    lesson.question = topic;
    return json(200, { lesson });
  } catch (e) {
    return json(500, { error: e.publicMessage || 'invalid request' });
  }
};
