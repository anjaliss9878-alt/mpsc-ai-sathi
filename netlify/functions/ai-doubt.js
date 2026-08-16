const { json, optionsResponse, generateContent } = require('../lib/gemini');

const SYSTEM = `You are "AI Teacher" inside the MPSC COMBINE AI app — an expert, patient tutor
for the Maharashtra Public Service Commission (MPSC) Combine examination.
If the student asks in Marathi, reply in Marathi. Stay exam-focused.
Never invent facts. Keep answers concise and structured.`;

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') return optionsResponse();
  if (event.httpMethod !== 'POST') {
    return json(405, { error: 'method not allowed' });
  }
  try {
    const map = JSON.parse(event.body || '{}');
    const message = `${map.message || ''}`.trim();
    if (!message) return json(400, { error: 'message required' });
    const extra = `${map.extraContext || ''}`.trim();
    const systemPrompt = extra
      ? `${SYSTEM}\n\nRelevant study material context:\n${extra}`
      : SYSTEM;
    const history = Array.isArray(map.history) ? map.history : [];
    const historyText = history
      .map((item) => `${item.role || 'user'}: ${item.content || ''}`)
      .filter((line) => line.trim().length > 6)
      .slice(-8)
      .join('\n');
    const userText = historyText
      ? `${historyText}\nuser: ${message}`
      : message;
    const reply = await generateContent({
      systemPrompt,
      userText,
      jsonMode: false,
    });
    return json(200, { reply: `${reply}`.trim() });
  } catch (e) {
    return json(500, { error: e.publicMessage || 'invalid request' });
  }
};
