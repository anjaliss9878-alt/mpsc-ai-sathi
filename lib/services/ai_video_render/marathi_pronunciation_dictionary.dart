/// Marathi / MPSC pronunciation corrections for Cloud TTS SSML.
///
/// Keys are matched as whole words (Devanagari or Latin). Values are the
/// preferred spoken form inserted via `<sub alias="…">`.
///
/// Keep this dictionary generic — never topic-hardcoded lesson content.
class MarathiPronunciationDictionary {
  const MarathiPronunciationDictionary();

  /// High-frequency MPSC / civics / exam terms that WaveNet often misreads.
  static const Map<String, String> defaults = {
    // Latin abbreviations commonly appearing in Marathi lessons
    'MPSC': 'एम पी एस सी',
    'UPSC': 'यू पी एस सी',
    'GDP': 'जी डी पी',
    'GST': 'जी एस टी',
    'RBI': 'आर बी आय',
    'SBI': 'एस बी आय',
    'NITI': 'नीती',
    'AYUSH': 'आयुष',
    'UNESCO': 'युनेस्को',
    'WHO': 'डब्ल्यू एच ओ',
    'UNO': 'यू एन ओ',
    'UN': 'यू एन',
    'GDP.': 'जी डी पी',
    // Articles / constitution shorthand
    'Art.': 'अनुच्छेद',
    'Article': 'अनुच्छेद',
    'ART': 'अनुच्छेद',
    // Common civics terms WaveNet sometimes flattens
    'Lok Sabha': 'लोकसभा',
    'Rajya Sabha': 'राज्यसभा',
    'Vidhan Sabha': 'विधानसभा',
    'Vidhan Parishad': 'विधान परिषद',
    'High Court': 'हायकोर्ट',
    'Supreme Court': 'सुप्रीम कोर्ट',
    'Preamble': 'प्रीअँबल',
    // Marathi spellings that benefit from alias spacing
    'राज्यपाल': 'राज्यपाल',
    'महाधिवक्ता': 'महा-अधिवक्ता',
    'नियंत्रक': 'नियंत्रक',
    'महा लेखापरीक्षक': 'महालेखापरीक्षक',
    'C&AG': 'सी अँड ए जी',
    'CAG': 'सी ए जी',
    'IAS': 'आय ए एस',
    'IPS': 'आय पी एस',
    'IFS': 'आय एफ एस',
    'PDS': 'पी डी एस',
    'MSP': 'एम एस पी',
    'FRBM': 'एफ आर बी एम',
    'SEBI': 'सेबी',
    'NABARD': 'नाबार्ड',
    'TRIPs': 'ट्रिप्स',
    'WTO': 'डब्ल्यू टी ओ',
    'PYQ': 'पी वाय क्यू',
    'MCQ': 'एम सी क्यू',
    'DPSP': 'डी पी एस पी',
    'NGO': 'एन जी ओ',
  };

  Map<String, String> get entries => defaults;

  /// Apply longest-key-first whole-phrase replacements for alias mapping.
  String applyAliases(String text) {
    var out = text;
    final keys = defaults.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      final alias = defaults[key]!;
      if (alias == key) continue;
      out = out.replaceAllMapped(
        RegExp(_wordPattern(key), caseSensitive: false),
        (_) => alias,
      );
    }
    return out;
  }

  /// Same as [applyAliases] but wraps matches in SSML `<sub alias>` (text must
  /// already be XML-escaped except for the tags we insert).
  String applySsmlSubAliases(String escapedText) {
    var out = escapedText;
    final keys = defaults.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      final alias = defaults[key]!;
      if (alias == key) continue;
      final safeAlias = _escapeSsml(alias);
      out = out.replaceAllMapped(
        RegExp(_wordPattern(_escapeSsml(key)), caseSensitive: false),
        (m) => '<sub alias="$safeAlias">${m[0]}</sub>',
      );
    }
    return out;
  }

  static String _wordPattern(String key) {
    final escaped = RegExp.escape(key);
    // Allow Latin word boundaries; for Devanagari use lookaround on spaces/punct.
    return '(?<![\\w\\u0900-\\u097F])$escaped(?![\\w\\u0900-\\u097F])';
  }

  static String _escapeSsml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

const MarathiPronunciationDictionary marathiPronunciationDictionary =
    MarathiPronunciationDictionary();
