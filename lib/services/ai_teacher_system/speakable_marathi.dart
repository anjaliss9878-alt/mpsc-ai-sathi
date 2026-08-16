import 'package:mpsc_combine_ai/services/ai_video_render/marathi_pronunciation_dictionary.dart';

/// Turns PDF / slide text into speech the Marathi faculty voice can read
/// without saying "plus", "minus", "percent", page numbers, or bullets.
String speakableMarathi(String text) {
  var t = text.trim();
  if (t.isEmpty) return t;

  t = _stripPdfChrome(t);
  t = marathiPronunciationDictionary.applyAliases(t);
  t = _speakSymbols(t);
  t = _expandLeftoverLatinAcronyms(t);
  t = _softenMarkup(t);

  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

/// Board text may keep short labels; still strip OCR chrome and page numbers.
String cleanBoardText(String text) {
  var t = text.trim();
  if (t.isEmpty) return t;
  t = _stripPdfChrome(t);
  t = t.replaceAll(RegExp(r'[•●○▪►▸■□◆◇‣∙·]'), ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

String _stripPdfChrome(String text) {
  var t = text;
  t = t.replaceAll(RegExp(r'\bpage\s*\d+\b', caseSensitive: false), ' ');
  t = t.replaceAll(
    RegExp(r'\bpages?\s*\d+\s*[-–—]\s*\d+\b', caseSensitive: false),
    ' ',
  );
  t = t.replaceAll(RegExp(r'\bp\.\s*\d+\b', caseSensitive: false), ' ');
  t = t.replaceAll(
    RegExp(r'\bfig(?:ure)?\.?\s*\d+\b', caseSensitive: false),
    'आकृती ',
  );
  t = t.replaceAll(RegExp(r'\btable\s*\d+\b', caseSensitive: false), 'तक्ता ');
  t = t.replaceAll(RegExp(r'\bcontents\b', caseSensitive: false), ' ');
  t = t.replaceAll(RegExp(r'^\s*\d{1,3}\s*$', multiLine: true), ' ');
  t = t.replaceAll(RegExp(r'[•●○▪►▸■□◆◇‣∙·]'), ' ');
  t = t.replaceAll(
    RegExp(r'^\s*[\-\*\u2013\u2014•]+\s+', multiLine: true),
    '',
  );
  t = t.replaceAll(RegExp(r'\*{1,2}'), '');
  t = t.replaceAll(RegExp(r'`+'), '');
  t = t.replaceAll(RegExp(r'#+\s*'), '');
  return t;
}

String _speakSymbols(String text) {
  var t = text;

  t = t.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)\s*%'),
    (m) => '${m[1]} टक्के',
  );
  t = t.replaceAll('%', ' टक्के ');

  t = t.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)\s*\+\s*(\d+(?:\.\d+)?)'),
    (m) => '${m[1]} अधिक ${m[2]}',
  );
  t = t.replaceAll('+', ' ');

  t = t.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)\s*[-–—]\s*(\d+(?:\.\d+)?)'),
    (m) => '${m[1]} ते ${m[2]}',
  );

  t = t.replaceAllMapped(
    RegExp(r'([^\s])\s*/\s*([^\s])'),
    (m) => '${m[1]} किंवा ${m[2]}',
  );

  t = t.replaceAll('=', ' म्हणजे ');
  t = t.replaceAll('&', ' आणि ');
  t = t.replaceAllMapped(
    RegExp(r'\b(plus|minus|percent|percentage)\b', caseSensitive: false),
    (m) {
      switch (m[1]!.toLowerCase()) {
        case 'plus':
          return 'अधिक';
        case 'minus':
          return 'वजा';
        default:
          return 'टक्के';
      }
    },
  );
  t = t.replaceAllMapped(
    RegExp(r'\b(vs\.?|versus)\b', caseSensitive: false),
    (_) => 'विरुद्ध',
  );
  t = t.replaceAllMapped(
    RegExp(r'\b(etc\.?|ie\.?|e\.g\.?)\b', caseSensitive: false),
    (_) => 'इत्यादी',
  );
  t = t.replaceAll(RegExp(r'[@#_\\|<>\[\]\{\}~^$*]'), ' ');
  t = t.replaceAll(RegExp(r'(?<=\s)[-–—]+(?=\s)'), ' ');
  t = t.replaceAll(RegExp(r'^[-–—]+|[-–—]+$'), ' ');
  t = t.replaceAll(RegExp(r'[+\-/%=*]+'), ' ');
  t = t.replaceAll(RegExp(r'[।.]{2,}'), '।');
  return t;
}

/// Remaining Latin tokens: ALL-CAPS acronyms become Marathi letter names;
/// leftover English words are dropped so TTS never spells them.
String _expandLeftoverLatinAcronyms(String text) {
  const letters = <String, String>{
    'A': 'ए',
    'B': 'बी',
    'C': 'सी',
    'D': 'डी',
    'E': 'ई',
    'F': 'एफ',
    'G': 'जी',
    'H': 'एच',
    'I': 'आय',
    'J': 'जे',
    'K': 'के',
    'L': 'एल',
    'M': 'एम',
    'N': 'एन',
    'O': 'ओ',
    'P': 'पी',
    'Q': 'क्यू',
    'R': 'आर',
    'S': 'एस',
    'T': 'टी',
    'U': 'यू',
    'V': 'व्ही',
    'W': 'डब्ल्यू',
    'X': 'एक्स',
    'Y': 'वाय',
    'Z': 'झेड',
  };
  return text.replaceAllMapped(RegExp(r'\b[A-Za-z]{2,}\b'), (m) {
    final raw = m[0]!;
    final upper = raw.toUpperCase();
    final isAcronym = raw == upper && raw.length >= 2 && raw.length <= 6;
    if (isAcronym) {
      return upper.split('').map((c) => letters[c] ?? c).join(' ');
    }
    return '';
  });
}

String _softenMarkup(String text) {
  var t = text;
  t = t.replaceAll(RegExp(r'\.{3,}'), '।');
  t = t.replaceAll(RegExp(r'…+'), '।');
  t = t.replaceAllMapped(RegExp(r'([।?!])\s*'), (m) => '${m[1]} ');
  t = t.replaceAllMapped(RegExp(r'\.\s+(?=[^\s])'), (m) => '. ');
  t = t.replaceAllMapped(RegExp(r'([,;:])\s*'), (m) => '${m[1]} ');
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  return t;
}
