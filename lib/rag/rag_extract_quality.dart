import 'package:mpsc_combine_ai/rag/rag_text.dart';

/// True when Gemini PDF-bytes extract looks like a broken CID/Kruti/visual-order
/// Devanagari layer rather than Unicode Marathi.
///
/// English (no Devanagari) is never treated as corrupted unless it is CID-like
/// junk. Mixed Marathi–English with normal spaces (e.g. `संविधान Article 14`)
/// and well-formed Unicode (`निवड`, `निज`, `संविधान`) stay on the first path.
bool ragExtractedTextLooksCorrupted(String raw) {
  final text = cleanRagText(raw);
  if (text.isEmpty) return false;

  var devanagari = 0;
  var asciiAlnum = 0;
  for (final rune in text.runes) {
    if (_isDevanagari(rune)) {
      devanagari++;
    } else if (_isAsciiAlnum(rune)) {
      asciiAlnum++;
    }
  }

  final cid = _cidLikeTokenCount(text);
  // CID/Kruti junk must be caught even on pages with almost no Devanagari.
  if (cid >= 1) return true;
  // Visual-order ि before a consonant (e.g. िज्यघटना) — even on short pages.
  if (_preConsonantIMatraCount(text) >= 1) return true;
  if (devanagari < 8) return false;

  if (text.contains('\uFFFD')) return true;
  if (_isolatedCombiningCount(text) >= 1) return true;
  if (_brokenViramaCount(text) >= 2) return true;
  if (_interleavedScriptNoiseCount(text) >= 2) return true;

  final letterish = asciiAlnum + devanagari;
  if (letterish >= 40 &&
      asciiAlnum / letterish > 0.42 &&
      _interleavedScriptNoiseCount(text) >= 1) {
    return true;
  }
  return false;
}

bool ragExtractedPagesLookCorrupted(Iterable<RagExtractedPage> pages) {
  final list = pages.toList();
  for (final page in list) {
    if (ragExtractedTextLooksCorrupted(page.text)) return true;
  }
  if (list.length > 1) {
    final joined = list.map((p) => p.text).join('\n');
    if (ragExtractedTextLooksCorrupted(joined)) return true;
  }
  return false;
}

/// 1-based PDF pages that need image OCR. Empty set means the whole document
/// (no reliable page numbers, or corruption only visible on the joined text).
Set<int> ragCorruptExtractPageNumbers(Iterable<RagExtractedPage> pages) {
  final list = pages.toList();
  if (list.isEmpty) return const {};
  final numbered = list.every((p) => p.pageNumber != null && p.pageNumber! >= 1);
  if (!numbered) return const {};
  final marked = {
    for (final p in list)
      if (ragExtractedTextLooksCorrupted(p.text)) p.pageNumber!,
  };
  if (marked.isEmpty && ragExtractedPagesLookCorrupted(list)) {
    return const {};
  }
  return marked;
}

bool _isDevanagari(int rune) => rune >= 0x0900 && rune <= 0x097F;

bool _isAsciiAlnum(int rune) =>
    (rune >= 0x30 && rune <= 0x39) ||
    (rune >= 0x41 && rune <= 0x5A) ||
    (rune >= 0x61 && rune <= 0x7A);

bool _isDevanagariBase(int rune) {
  return (rune >= 0x0904 && rune <= 0x0939) ||
      (rune >= 0x0958 && rune <= 0x095F) ||
      rune == 0x0960 ||
      rune == 0x0961;
}

bool _isDevanagariConsonant(int rune) {
  return (rune >= 0x0915 && rune <= 0x0939) ||
      (rune >= 0x0958 && rune <= 0x095F);
}

bool _isDevanagariCombining(int rune) {
  return rune == 0x0900 ||
      rune == 0x0901 ||
      rune == 0x0902 ||
      rune == 0x0903 ||
      rune == 0x093A ||
      rune == 0x093B ||
      rune == 0x093C ||
      (rune >= 0x093E && rune <= 0x094F) ||
      (rune >= 0x0951 && rune <= 0x0957) ||
      rune == 0x0962 ||
      rune == 0x0963;
}

/// Visual-order / Kruti ि (U+093F) before a consonant at cluster start.
///
/// `िज्यघटना` is corrupt. `निवड` / `निज` / `संविधान` store ि *after* the
/// consonant, so they are not flagged.
int _preConsonantIMatraCount(String text) {
  var count = 0;
  var prev = 0;
  final runes = text.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    final rune = runes[i];
    if (rune == 0x093F &&
        !_isDevanagariBase(prev) &&
        i + 1 < runes.length &&
        _isDevanagariConsonant(runes[i + 1])) {
      count++;
    }
    prev = rune;
  }
  return count;
}

int _isolatedCombiningCount(String text) {
  var count = 0;
  var inCluster = false;
  for (final rune in text.runes) {
    if (_isDevanagariCombining(rune)) {
      if (!inCluster) count++;
    } else if (_isDevanagariBase(rune)) {
      inCluster = true;
    } else if (_isDevanagari(rune)) {
      inCluster = true;
    } else {
      inCluster = false;
    }
  }
  return count;
}

int _brokenViramaCount(String text) {
  var count = 0;
  var prev = 0;
  for (final rune in text.runes) {
    if (rune == 0x094D && !_isDevanagariBase(prev) && prev != 0x094D) {
      count++;
    }
    prev = rune;
  }
  return count;
}

/// Digit-led mixed alphanumerics (CID / `9D0fjYpn` / `9DUlj`), not `Article 14`.
int _cidLikeTokenCount(String text) {
  return RegExp(r'(?<![A-Za-z])\d+[A-Za-z][A-Za-z0-9]{2,}')
      .allMatches(text)
      .length;
}

int _interleavedScriptNoiseCount(String text) {
  return RegExp(r'[\u0900-\u097F][A-Za-z0-9]{1,6}[\u0900-\u097F]')
      .allMatches(text)
      .length;
}
