function isDevanagari(cp) {
  return cp >= 0x0900 && cp <= 0x097f;
}

function isAsciiAlnum(cp) {
  return (
    (cp >= 0x30 && cp <= 0x39) ||
    (cp >= 0x41 && cp <= 0x5a) ||
    (cp >= 0x61 && cp <= 0x7a)
  );
}

function isDevanagariBase(cp) {
  return (
    (cp >= 0x0904 && cp <= 0x0939) ||
    (cp >= 0x0958 && cp <= 0x095f) ||
    cp === 0x0960 ||
    cp === 0x0961
  );
}

function isDevanagariCombining(cp) {
  return (
    cp === 0x0900 ||
    cp === 0x0901 ||
    cp === 0x0902 ||
    cp === 0x0903 ||
    cp === 0x093a ||
    cp === 0x093b ||
    cp === 0x093c ||
    (cp >= 0x093e && cp <= 0x094f) ||
    (cp >= 0x0951 && cp <= 0x0957) ||
    cp === 0x0962 ||
    cp === 0x0963
  );
}

function isolatedCombiningCount(text) {
  let count = 0;
  let inCluster = false;
  for (const ch of text) {
    const cp = ch.codePointAt(0);
    if (isDevanagariCombining(cp)) {
      if (!inCluster) count += 1;
    } else if (isDevanagariBase(cp) || isDevanagari(cp)) {
      inCluster = true;
    } else {
      inCluster = false;
    }
  }
  return count;
}

function brokenViramaCount(text) {
  let count = 0;
  let prev = 0;
  for (const ch of text) {
    const cp = ch.codePointAt(0);
    if (cp === 0x094d && !isDevanagariBase(prev) && prev !== 0x094d) {
      count += 1;
    }
    prev = cp;
  }
  return count;
}

function cidLikeTokenCount(text) {
  const matches = `${text}`.match(
    /(?:\d+[A-Za-z]{2,}[A-Za-z0-9]*|[A-Za-z]{2,}\d+[A-Za-z0-9]+)/g,
  );
  return matches ? matches.length : 0;
}

function interleavedScriptNoiseCount(text) {
  const matches = `${text}`.match(
    /[\u0900-\u097F][A-Za-z0-9]{1,6}[\u0900-\u097F]/g,
  );
  return matches ? matches.length : 0;
}

function ragExtractedTextLooksCorrupted(raw) {
  const text = `${raw || ''}`.trim();
  if (!text) return false;
  let devanagari = 0;
  let asciiAlnum = 0;
  for (const ch of text) {
    const cp = ch.codePointAt(0);
    if (isDevanagari(cp)) devanagari += 1;
    else if (isAsciiAlnum(cp)) asciiAlnum += 1;
  }
  if (devanagari < 8) return false;
  if (text.includes('\uFFFD')) return true;
  if (isolatedCombiningCount(text) >= 1) return true;
  if (brokenViramaCount(text) >= 2) return true;
  if (cidLikeTokenCount(text) >= 1) return true;
  if (interleavedScriptNoiseCount(text) >= 2) return true;
  const letterish = asciiAlnum + devanagari;
  if (
    letterish >= 40 &&
    asciiAlnum / letterish > 0.42 &&
    interleavedScriptNoiseCount(text) >= 1
  ) {
    return true;
  }
  return false;
}

function ragExtractedPagesLookCorrupted(pages) {
  return (Array.isArray(pages) ? pages : []).some((p) =>
    ragExtractedTextLooksCorrupted(p && p.text),
  );
}

module.exports = {
  ragExtractedTextLooksCorrupted,
  ragExtractedPagesLookCorrupted,
};
