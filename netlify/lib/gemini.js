const { corsHeaders, json, optionsResponse } = require('./cors');
const { fetchTrusted } = require('./trusted_url');

const FALLBACK_MODELS = [
  'gemini-flash-lite-latest',
  'gemini-pro-latest',
  'gemini-3.1-flash-lite',
  'gemini-3.5-flash',
  'gemini-3-flash-preview',
];

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

const EMBED_MODEL = 'gemini-embedding-001';
const EMBED_DIMENSIONS = 768;
const MAX_PDF_BYTES = 8 * 1024 * 1024;

function classifyGeminiHttp(status, body) {
  const lower = `${body || ''}`.toLowerCase();
  if (status === 401 || status === 403 || lower.includes('api_key_invalid')) {
    return 'Gemini API unauthorized';
  }
  if (status === 404) return 'model not found';
  if (status === 429 || lower.includes('quota')) return 'quota exceeded';
  if (status === 400) return 'invalid request';
  if (status === 503) return 'network error';
  return 'invalid request';
}

async function embedTexts({ texts, task = 'document' }) {
  const apiKey = requireEnv('AI_API_KEY');
  const taskType =
    task === 'query' ? 'RETRIEVAL_QUERY' : 'RETRIEVAL_DOCUMENT';
  const embeddings = [];
  for (const text of texts) {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${EMBED_MODEL}:embedContent`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: JSON.stringify({
          content: { parts: [{ text: `${text || ''}`.slice(0, 8000) }] },
          taskType,
          outputDimensionality: EMBED_DIMENSIONS,
        }),
      },
    );
    const raw = await res.text();
    if (res.status !== 200) {
      throw Object.assign(new Error(classifyGeminiHttp(res.status, raw)), {
        publicMessage: classifyGeminiHttp(res.status, raw),
      });
    }
    const payload = JSON.parse(raw);
    const values = payload.embedding?.values;
    if (!Array.isArray(values) || values.length !== EMBED_DIMENSIONS) {
      throw Object.assign(new Error('embedding failure'), {
        publicMessage: 'embedding failure',
      });
    }
    embeddings.push(values);
  }
  return embeddings;
}

function stripFences(text) {
  let t = `${text || ''}`.trim();
  if (t.startsWith('```')) {
    t = t.replace(/^```(?:json)?\s*/i, '');
    t = t.replace(/\s*```$/, '');
  }
  return t.trim();
}

async function extractPdfFromUrl({ fileUrl, title = '' }) {
  const url = `${fileUrl || ''}`.trim();
  if (!url) {
    throw Object.assign(new Error('fileUrl required'), {
      publicMessage: 'PDF extraction failed: fileUrl required',
    });
  }
  let fetched;
  try {
    fetched = await fetchTrusted(url);
  } catch (e) {
    if (e.statusCode === 400) throw e;
    throw Object.assign(new Error('network error'), {
      publicMessage: 'PDF extraction failed: could not download the file',
    });
  }
  if (!fetched.ok) {
    throw Object.assign(new Error('PDF extraction failed'), {
      publicMessage: `PDF extraction failed: download HTTP ${fetched.status}`,
    });
  }
  const buf = Buffer.from(await fetched.arrayBuffer());
  if (!buf.length) {
    throw Object.assign(new Error('empty document'), {
      publicMessage: 'empty document',
    });
  }
  if (buf.length > MAX_PDF_BYTES) {
    throw Object.assign(new Error('PDF too large'), {
      publicMessage: `PDF extraction failed: file is larger than ${MAX_PDF_BYTES / (1024 * 1024)} MB`,
    });
  }
  const apiKey = requireEnv('AI_API_KEY');
  const preferred = (process.env.AI_MODEL || '').trim();
  const models = [];
  if (preferred) models.push(preferred);
  for (const m of FALLBACK_MODELS) {
    if (!models.includes(m)) models.push(m);
  }
  const prompt = `Extract ALL text from this MPSC study PDF.
Return ONE JSON object only: {"pages":[{"page":1,"text":"..."}]}.
"page" MUST be the 1-based index of the actual PDF file page you extracted.
If you cannot observe real page boundaries, return {"pages":[{"text":"<full text>"}]} with NO page field — never guess a page number.
Preserve Marathi (Devanagari) exactly. Do not translate. Do not invent facts.
Title hint: ${title || '(none)'}`;

  let lastError = 'PDF extraction failed';
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
          systemInstruction: {
            parts: [
              {
                text: 'You extract PDF text for RAG. JSON only. Never invent page numbers.',
              },
            ],
          },
          contents: [
            {
              role: 'user',
              parts: [
                { text: prompt },
                {
                  inline_data: {
                    mime_type: 'application/pdf',
                    data: buf.toString('base64'),
                  },
                },
              ],
            },
          ],
          generationConfig: {
            responseMimeType: 'application/json',
            temperature: 0.1,
            maxOutputTokens: 8192,
          },
        }),
      },
    );
    const raw = await res.text();
    if (res.status !== 200) {
      lastError = classifyGeminiHttp(res.status, raw);
      if (res.status === 401 || res.status === 403) {
        throw Object.assign(new Error(lastError), { publicMessage: lastError });
      }
      continue;
    }
    let payload;
    try {
      payload = JSON.parse(raw);
    } catch (_) {
      lastError = 'response parsing error';
      continue;
    }
    const text = extractText(payload);
    if (!text) {
      lastError = 'response parsing error';
      continue;
    }
    try {
      const parsed = JSON.parse(stripFences(text));
      const pages = Array.isArray(parsed.pages)
        ? parsed.pages
        : parsed.text
          ? [{ text: parsed.text }]
          : [];
      const cleaned = pages
        .map((p) => {
          const pageText = `${p.text || ''}`.trim();
          const page =
            typeof p.page === 'number' && p.page >= 1 ? p.page : undefined;
          if (!pageText) return null;
          return page ? { page, text: pageText } : { text: pageText };
        })
        .filter(Boolean);
      if (!cleaned.length) {
        lastError = 'empty document';
        continue;
      }
      return { pages: cleaned };
    } catch (_) {
      lastError = 'response parsing error';
    }
  }
  throw Object.assign(new Error(lastError), { publicMessage: lastError });
}

function learnSystemPrompt(mode, teachingStyle) {
  return `You are a grounded MPSC Combined Group B/C AI Teacher.
Retrieved numbered chunks are PRIMARY EVIDENCE. The app will attach citations from chunk indexes.

HARD RULES:
- Use only facts supported by the numbered chunks.
- Never invent sources, citations, page numbers, PYQs, years, article numbers, dates, committees, or personalities.
- If the chunks do not contain enough information, set insufficient=true and leave content empty.
- Do NOT write a Sources section or page numbers in the text. Return chunkIndexes instead.
- If the student question uses Devanagari, answer in natural Marathi. Otherwise English.
- Explain step-by-step with MPSC exam-oriented examples drawn from the chunks.
- If the student asks to compare topics, use a Markdown table from chunk facts only.
- Memory tricks must not change the meaning of source facts.
- MCQ difficulty must be exactly Easy, Medium, or Hard.
- chunkIndexes must be integers from the provided chunk list only.

${teachingStyle || ''}
Mode: ${mode}`;
}

function learnUserText({ mode, question, chunks, history }) {
  const chunkBlock = (Array.isArray(chunks) ? chunks : [])
    .map((c, i) => {
      const idx = typeof c.index === 'number' ? c.index : i;
      const page =
        typeof c.pageNumber === 'number' && c.pageNumber >= 1
          ? ` page=${c.pageNumber}`
          : ' page=unknown';
      const title = `${c.sourceTitle || c.topic || ''}`.trim();
      const type = `${c.contentType || ''}`.trim();
      const chunkRef = `${c.chunkId || c.sourceId || ''}`.trim();
      return `[${idx}] title=${title} contentType=${type} topic=${c.topic || ''} chunk=${chunkRef} subject=${c.subject || ''} chapter=${c.chapter || ''}${page}\n${c.text || ''}`;
    })
    .join('\n\n');
  const hist = (Array.isArray(history) ? history : [])
    .map((m) => `${m.role === 'user' ? 'Student' : 'Teacher'}: ${m.content || ''}`)
    .join('\n');
  const schema = {
    answer:
      '{"insufficient":boolean,"answer":string,"chunkIndexes":number[]}',
    summary:
      '{"insufficient":boolean,"detailed":string,"shortNotes":string,"fiveMinuteRevision":string,"importantFacts":string[],"examPoints":string[],"commonMistakes":string[],"chunkIndexes":number[]}',
    mcq: '{"insufficient":boolean,"questions":[{"question":string,"options":[string,string,string,string],"correctIndex":0,"explanation":string,"difficulty":"Easy|Medium|Hard","topic":string,"chunkIndexes":number[]}]}',
    flashcards:
      '{"insufficient":boolean,"cards":[{"front":string,"back":string,"explanation":string,"chunkIndexes":number[]}]}',
    revision:
      '{"insufficient":boolean,"keyFacts":string[],"terms":string[],"dates":string[],"articles":string[],"committees":string[],"personalities":string[],"examTraps":string[],"chunkIndexes":number[]}',
    memory:
      '{"insufficient":boolean,"tricks":[{"trick":string,"chunkIndexes":number[]}]}',
  }[mode] || '{"insufficient":boolean}';
  return `Student question:\n${question || ''}\n\nRecent chat (for pronouns / follow-ups only; do not invent facts from it):\n${hist || '(none)'}\n\nRetrieved chunks:\n${chunkBlock || '(none)'}\n\nReturn ONE JSON object matching:\n${schema}`;
}

async function learnGrounded({ mode, question, chunks, history, teachingStyle }) {
  const allowed = new Set([
    'answer',
    'summary',
    'mcq',
    'flashcards',
    'revision',
    'memory',
  ]);
  const m = allowed.has(mode) ? mode : 'answer';
  const parsed = await generateContent({
    systemPrompt: learnSystemPrompt(m, teachingStyle),
    userText: learnUserText({ mode: m, question, chunks, history }),
    jsonMode: true,
  });
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw Object.assign(new Error('invalid learn JSON'), {
      publicMessage: 'Gemini returned invalid JSON',
    });
  }
  return parsed;
}

module.exports = {
  corsHeaders,
  json,
  optionsResponse,
  requireEnv,
  generateContent,
  compactLessonPrompt,
  embedTexts,
  extractPdfFromUrl,
  learnGrounded,
  learnSystemPrompt,
  learnUserText,
  EMBED_DIMENSIONS,
};
