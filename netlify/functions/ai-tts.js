const { json } = require('../lib/cors');
const { withAuth } = require('../lib/auth');

const VOICES = {
  polity: 'pNInz6obpgDQGcFmaJgB',
  history: '2EiwWnXFnvU5JabPnv8n',
  geography: 'ThT5KcBeYPX3keUQqHPh',
  economics: 'ErXwobaYiN019PkySvjV',
  science: '21m00Tcm4TlvDq8ikWAM',
  environment: 'ThT5KcBeYPX3keUQqHPh',
};

const GEMINI_TTS_MODEL = 'gemini-3.1-flash-tts-preview';
const GEMINI_VOICE = 'Kore';

function safeSnippet(text) {
  return `${text || ''}`
    .replace(/xi-api-key\s*[:=]\s*\S+/gi, '')
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
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_TTS_MODEL}:generateContent`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': apiKey,
        },
        body: JSON.stringify({
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
        }),
      },
    );
    const raw = await res.text();
    if (!res.ok) {
      throw new Error(
        `Gemini TTS failed HTTP ${res.status}: ${safeSnippet(raw)}`,
      );
    }
    const decoded = JSON.parse(raw);
    const parts = decoded?.candidates?.[0]?.content?.parts;
    const inline = parts?.[0]?.inlineData || parts?.[0]?.inline_data;
    const b64 = `${inline?.data || ''}`.trim();
    if (!b64) {
      throw new Error('Gemini TTS empty audio payload');
    }
    const pcm = Buffer.from(b64, 'base64');
    if (pcm.length < 256) {
      throw new Error('Gemini TTS returned empty audio');
    }
    const rate = parseRate(inline?.mimeType || inline?.mime_type);
    wavs.push(pcm16ToWav(pcm, rate || 24000));
  }
  const bytes = concatWav(wavs);
  return {
    audio_base64: bytes.toString('base64'),
    mimeType: 'audio/wav',
    durationMs: Math.min(12 * 60 * 1000, wavDurationMs(bytes)),
    voiceId: GEMINI_VOICE,
    modelId: 'gemini-tts',
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
    const elevenKey = `${process.env.ELEVENLABS_API_KEY || ''}`.trim();
    if (elevenKey) {
      const subject = `${map.subject || 'geography'}`.trim().toLowerCase();
      const voiceId = (
        `${map.voiceId || process.env.ELEVENLABS_VOICE_ID || ''}`.trim() ||
        VOICES[subject] ||
        VOICES.geography
      );
      const model = (
        `${map.modelId || process.env.ELEVENLABS_MODEL_ID || process.env.ELEVENLABS_MODEL || ''}`.trim() ||
        'eleven_multilingual_v2'
      );
      const res = await fetch(
        `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}/with-timestamps`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'xi-api-key': elevenKey,
            Accept: 'application/json',
          },
          body: JSON.stringify({
            text,
            model_id: model,
          }),
        },
      );
      const raw = await res.text();
      if (res.status < 200 || res.status >= 300) {
        const status =
          res.status === 429
            ? 429
            : res.status === 401 || res.status === 403
              ? res.status
              : 502;
        return json(status, {
          error: `ElevenLabs TTS failed (HTTP ${res.status}). ${safeSnippet(raw)}`,
          status: res.status,
        }, event);
      }
      const decoded = JSON.parse(raw);
      const audio = `${decoded.audio_base64 || ''}`.trim();
      if (!audio) {
        return json(502, {
          error: 'ElevenLabs returned empty audio',
          status: 502,
        }, event);
      }
      const alignment =
        decoded.normalized_alignment || decoded.alignment || {};
      const ends = Array.isArray(alignment.character_end_times_seconds)
        ? alignment.character_end_times_seconds
        : [];
      const durationMs =
        ends.length > 0
          ? Math.round(Number(ends[ends.length - 1]) * 1000)
          : Math.max(800, Math.round((text.length / 13) * 1000));
      return json(200, {
        audio_base64: audio,
        mimeType: 'audio/mpeg',
        voiceId,
        modelId: model,
        durationMs,
      }, event);
    }

    const geminiKey = `${process.env.AI_API_KEY || ''}`.trim();
    if (!geminiKey) {
      return json(500, {
        error: 'Marathi TTS credentials missing',
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
      error: e.publicMessage || e.message || 'TTS failed',
      status,
    }, event);
  }
};
