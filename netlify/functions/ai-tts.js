const { json, optionsResponse, requireEnv } = require('../lib/gemini');

const VOICES = {
  polity: 'pNInz6obpgDQGcFmaJgB',
  history: '2EiwWnXFnvU5JabPnv8n',
  geography: 'ThT5KcBeYPX3keUQqHPh',
  economics: 'ErXwobaYiN019PkySvjV',
  science: '21m00Tcm4TlvDq8ikWAM',
  environment: 'ThT5KcBeYPX3keUQqHPh',
};

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') return optionsResponse();
  if (event.httpMethod !== 'POST') {
    return json(405, { error: 'method not allowed' });
  }
  try {
    const apiKey = requireEnv('ELEVENLABS_API_KEY');
    const map = JSON.parse(event.body || '{}');
    const text = `${map.text || ''}`.trim();
    if (!text) return json(400, { error: 'text required' });
    const subject = `${map.subject || 'geography'}`.trim().toLowerCase();
    const voiceId = VOICES[subject] || VOICES.geography;
    const model =
      (process.env.ELEVENLABS_MODEL || 'eleven_multilingual_v2').trim();
    const res = await fetch(
      `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}/with-timestamps`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'xi-api-key': apiKey,
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
      return json(500, { error: 'ElevenLabs TTS failed' });
    }
    const decoded = JSON.parse(raw);
    const audio = `${decoded.audio_base64 || ''}`.trim();
    if (!audio) return json(500, { error: 'ElevenLabs returned empty audio' });
    return json(200, {
      audio_base64: audio,
      mimeType: 'audio/mpeg',
      voiceId,
    });
  } catch (e) {
    return json(500, { error: e.publicMessage || 'ElevenLabs TTS failed' });
  }
};
