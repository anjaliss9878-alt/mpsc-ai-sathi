const { json } = require('../lib/cors');
const { withAuth } = require('../lib/auth');

const GEMINI_TTS_MODEL = 'gemini-3.1-flash-tts-preview';
const GEMINI_VOICE = 'Kore';

function safeSnippet(text) {
  return `${text || ''}`
    .replace(/sk_[A-Za-z0-9]+/g, '[redacted]')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 220);
}

function clipAtSentence(text, maxChars) {
  const cleaned = `${text || ''}`.trim();
  if (cleaned.length <= maxChars) return cleaned;
  const chunks = chunkSpeech(cleaned, maxChars);
  return chunks[0] || cleaned.slice(0, maxChars);
}

function chunkSpeech(text, maxChars) {
  const cleaned = `${text || ''}`.trim();
  if (!cleaned) return [];
  if (cleaned.length <= maxChars) return [cleaned];
  const sentences = cleaned
    .split(/(?<=[।.?!…])\s+/)
    .map((s) => s.trim())
    .filter(Boolean);
  if (!sentences.length) {
    const out = [];
    for (let i = 0; i < cleaned.length; i += maxChars) {
      out.push(cleaned.slice(i, i + maxChars));
    }
    return out;
  }
  const chunks = [];
  let buf = '';
  for (const s of sentences) {
    const next = buf ? `${buf} ${s}` : s;
    if (next.length > maxChars && buf) {
      chunks.push(buf.trim());
      buf = s;
    } else {
      buf = next;
    }
  }
  if (buf.trim()) chunks.push(buf.trim());
  return chunks;
}

function isWavContainer(buf) {
  return (
    buf &&
    buf.length >= 12 &&
    buf.toString('ascii', 0, 4) === 'RIFF' &&
    buf.toString('ascii', 8, 12) === 'WAVE'
  );
}

function ensureWav(buf, mime) {
  if (isWavContainer(buf)) return buf;
  return pcm16ToWav(buf, parseRate(mime) || 24000);
}

function pcm16ToWav(pcm, sampleRate) {
  const dataLength = pcm.length;
  const byteRate = sampleRate * 2;
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + dataLength, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(byteRate, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write('data', 36);
  header.writeUInt32LE(dataLength, 40);
  return Buffer.concat([header, pcm]);
}

function concatWav(wavs) {
  if (!wavs.length) throw new Error('No WAV clips to concatenate');
  if (wavs.length === 1) return wavs[0];
  const rate = wavs[0].readUInt32LE(24);
  const pcm = Buffer.concat(wavs.map((w) => w.subarray(44)));
  return pcm16ToWav(pcm, rate);
}

function wavDurationMs(wav) {
  if (!wav || wav.length < 44) return 800;
  const rate = wav.readUInt32LE(24) || 24000;
  const dataLen = wav.length - 44;
  return Math.max(800, Math.round((dataLen / (rate * 2)) * 1000));
}

function parseRate(mime) {
  const m = /rate=(\d+)/i.exec(mime || '');
  return m ? Number(m[1]) : 24000;
}

function isTransientStatus(status) {
  return status === 429 || status === 500 || status === 502 ||
    status === 503 || status === 504;
}

async function fetchGeminiAudio(body, apiKey) {
  let lastError;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 55000);
    try {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_TTS_MODEL}:generateContent`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: JSON.stringify(body),
          signal: controller.signal,
        },
      );
      const rawText = await res.text();
      if (res.ok) return rawText;
      const err = new Error(
        `Gemini TTS failed HTTP ${res.status}: ${safeSnippet(rawText)}`,
      );
      err.statusCode = res.status === 429 ? 429 : 502;
      lastError = err;
      if (!isTransientStatus(res.status) || attempt === 2) throw err;
    } catch (e) {
      lastError = e;
      if (attempt === 2 || (e.statusCode && e.statusCode !== 429 &&
          e.statusCode !== 502 && e.statusCode !== 503 &&
          e.statusCode !== 504)) {
        throw e;
      }
    } finally {
      clearTimeout(timer);
    }
    await new Promise((resolve) =>
      setTimeout(resolve, 700 * (2 ** attempt)),
    );
  }
  throw lastError || new Error('Gemini TTS unavailable');
}

async function geminiSpeech(text, apiKey) {
  const clipped = clipAtSentence(text, 1800);
  const chunks = chunkSpeech(clipped, 900);
  if (!chunks.length) {
    const err = new Error('Empty lesson script');
    err.statusCode = 400;
    throw err;
  }
  const wavs = [];
  for (const chunk of chunks) {
    const rawText = await fetchGeminiAudio({
      contents: [
        {
          role: 'user',
          parts: [
            {
              text:
                'Speak in natural Marathi as a warm female MPSC faculty. ' +
                `Do not add extra words. Read exactly:\n${chunk}`,
            },
          ],
        },
      ],
      generationConfig: {
        responseModalities: ['AUDIO'],
        speechConfig: {
          voiceConfig: {
            prebuiltVoiceConfig: { voiceName: GEMINI_VOICE },
          },
        },
      },
    }, apiKey);
    const decoded = JSON.parse(rawText);
    const parts = decoded?.candidates?.[0]?.content?.parts;
    const inline = parts?.[0]?.inlineData || parts?.[0]?.inline_data;
    const b64 = `${inline?.data || ''}`.trim();
    if (!b64) {
      const err = new Error('Gemini TTS empty audio payload');
      err.statusCode = 502;
      throw err;
    }
    const audioBuf = Buffer.from(b64, 'base64');
    if (audioBuf.length < 256 && !isWavContainer(audioBuf)) {
      const err = new Error('Gemini TTS returned empty audio');
      err.statusCode = 502;
      throw err;
    }
    const mime = inline?.mimeType || inline?.mime_type || '';
    wavs.push(ensureWav(audioBuf, mime));
  }
  const bytes = concatWav(wavs);
  return {
    audio_base64: bytes.toString('base64'),
    mimeType: 'audio/wav',
    mime_type: 'audio/wav',
    durationMs: Math.min(12 * 60 * 1000, wavDurationMs(bytes)),
    voiceId: GEMINI_VOICE,
    modelId: GEMINI_TTS_MODEL,
  };
}

exports.handler = async (event) => {
  const gated = await withAuth(event);
  if (gated.halt) {
    if (gated.halt.statusCode === 405) {
      return json(405, { error: 'method not allowed', status: 405 }, event);
    }
    return gated.halt;
  }
  try {
    const map = JSON.parse(event.body || '{}');
    const text = `${map.text || ''}`.trim();
    if (!text) {
      return json(400, { error: 'Empty lesson script', status: 400 }, event);
    }
    const geminiKey = `${process.env.AI_API_KEY || ''}`.trim();
    if (!geminiKey) {
      return json(500, {
        error: 'Gemini TTS credentials missing',
        status: 500,
      }, event);
    }
    const clip = await geminiSpeech(text, geminiKey);
    if (!clip.audio_base64) {
      return json(502, {
        error: 'Gemini TTS returned empty audio',
        status: 502,
      }, event);
    }
    return json(200, clip, event);
  } catch (e) {
    const status = e.statusCode || 502;
    return json(status, {
      error: e.publicMessage || e.message || 'Gemini TTS failed',
      status,
    }, event);
  }
};

exports.GEMINI_TTS_MODEL = GEMINI_TTS_MODEL;
exports.isWavContainer = isWavContainer;
exports.ensureWav = ensureWav;
