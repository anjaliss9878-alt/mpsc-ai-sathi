const fs = require('fs');
const path = require('path');
const assert = require('assert');
const { test } = require('node:test');

const src = fs.readFileSync(
  path.join(__dirname, '..', 'functions', 'ai-tts.js'),
  'utf8',
);

test('/ai/tts is Google Gemini TTS only', () => {
  assert.match(src, /gemini-3\.1-flash-tts-preview/);
  assert.match(src, /withAuth/);
  assert.equal(src.includes('api.elevenlabs.io'), false);
  assert.equal(src.includes('ELEVENLABS_API_KEY'), false);
  assert.equal(src.includes('xi-api-key'), false);
  assert.match(src, /Empty lesson script/);
  assert.match(src, /Gemini TTS failed/);
  assert.match(src, /ensureWav/);
  assert.match(src, /isWavContainer/);
});

test('PCM is wrapped as WAV and existing WAV is not double-wrapped', () => {
  const { ensureWav, isWavContainer } = require('../functions/ai-tts.js');
  const pcm = Buffer.alloc(480);
  const wav = ensureWav(pcm, 'audio/L16;rate=24000');
  assert.equal(isWavContainer(wav), true);
  assert.equal(wav.length, 44 + pcm.length);
  const again = ensureWav(wav, 'audio/wav');
  assert.equal(again.length, wav.length);
  assert.deepEqual(again.subarray(0, 12), wav.subarray(0, 12));
});
