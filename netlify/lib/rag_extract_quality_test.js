const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ragExtractedTextLooksCorrupted,
} = require('./rag_extract_quality');

test('good Unicode Marathi is not corrupted', () {
  assert.equal(
    ragExtractedTextLooksCorrupted(
      'भारतीय संविधानातील संसद ही द्विसदनी आहे. लोकसभा आणि राज्यसभा.',
    ),
    false,
  );
});

test('English text is not corrupted', () {
  assert.equal(
    ragExtractedTextLooksCorrupted(
      'Parliament is bicameral. Article 14 guarantees equality before law.',
    ),
    false,
  );
});

test('isolated matra and CID junk is corrupted', () {
  assert.equal(
    ragExtractedTextLooksCorrupted(
      'िाव (लॉडण एन. 9DUlj : बा. भारतीय संविधान लोकसभा राज्यसभा',
    ),
    true,
  );
});
