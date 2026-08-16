const FALLBACK_MODELS = [
  'gemini-flash-lite-latest',
  'gemini-pro-latest',
  'gemini-3.1-flash-lite',
  'gemini-3.5-flash',
  'gemini-3-flash-preview',
];

function corsHeaders(extra = {}) {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    ...extra,
  };
}

function json(statusCode, body) {
  return {
    statusCode,
    headers: corsHeaders({ 'Content-Type': 'application/json' }),
    body: JSON.stringify(body),
  };
}

function optionsResponse() {
  return { statusCode: 204, headers: corsHeaders(), body: '' };
}

function requireEnv(name) {
  const value = (process.env[name] || '').trim();
  if (!value) {
    const err = new Error(`${name} missing`);
    err.statusCode = 500;
    err.publicMessage = `${name} missing`;
    throw err;
  }
  return value;
}

function extractText(payload) {
  const parts = payload?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts) || parts.length === 0) return '';
  return `${parts[0].text || ''}`.trim();
}

async function generateContent({ systemPrompt, userText, jsonMode = false }) {
  const apiKey = requireEnv('AI_API_KEY');
  const preferred = (process.env.AI_MODEL || '').trim();
  const models = [];
  if (preferred) models.push(preferred);
  for (const m of FALLBACK_MODELS) {
    if (!models.includes(m)) models.push(m);
  }

  let lastError = 'invalid request';
  for (const model of models) {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: systemPrompt }] },
          contents: [{ role: 'user', parts: [{ text: userText }] }],
          generationConfig: jsonMode
            ? {
                responseMimeType: 'application/json',
                temperature: 0.35,
                maxOutputTokens: 8192,
              }
            : { temperature: 0.4, maxOutputTokens: 2048 },
        }),
      },
    );
    const raw = await res.text();
    if (res.status === 200) {
      const payload = JSON.parse(raw);
      const text = extractText(payload);
      if (!text) {
        lastError = 'response parsing error';
        continue;
      }
      if (!jsonMode) return text;
      try {
        return JSON.parse(text);
      } catch (_) {
        lastError = 'response parsing error';
        continue;
      }
    }
    if (res.status === 401 || res.status === 403) {
      throw Object.assign(new Error('Gemini API unauthorized'), {
        publicMessage: 'Gemini API unauthorized',
      });
    }
    if (res.status === 429) {
      lastError = 'quota exceeded';
      continue;
    }
    if (res.status === 404 || res.status === 503) {
      lastError = res.status === 404 ? 'model not found' : 'network error';
      continue;
    }
    lastError = `invalid request`;
  }
  throw Object.assign(new Error(lastError), { publicMessage: lastError });
}

function compactLessonPrompt(topic, teachingSubject) {
  const subjectLine = teachingSubject
    ? `Subject MUST be ${teachingSubject}. Teach only in that classroom style.`
    : 'Detect the MPSC subject automatically.';
  return {
    system: `You are an MPSC Combined Group B and C Marathi teacher.
${subjectLine}
Teach the EXACT student topic. Never substitute संसद / Parliament unless that is the topic.
Never invent citations, article numbers, or years. If unsure, teach the principle without a fake source.
Reply with ONE JSON object only (no markdown).
All student-facing text in natural teacher-style Marathi.`,
    user: `Teach this EXACT MPSC Combined Group B & C topic in simple teacher-style Marathi: "${topic}"
${subjectLine}
Never teach संसद / Parliament unless that is the student topic.
Do not invent citations or unsupported facts.
Return ONLY one JSON object with keys:
title, subject, subjectName, topic, introduction, concepts[], important_facts[],
mpsc_points[], examples[], exam_traps[], teaching_script, mcq_seed_topics[],
memoryTricks[], revision[], notes[], mcqs[], pyqs[], slides[].
Keep JSON complete: 5 slides, 6 MCQs, 4 PYQ-style questions.`,
  };
}

module.exports = {
  corsHeaders,
  json,
  optionsResponse,
  requireEnv,
  generateContent,
  compactLessonPrompt,
};
