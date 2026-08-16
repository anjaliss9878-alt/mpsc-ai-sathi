import 'package:mpsc_combine_ai/services/ai_teacher_system/faculty_narration.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/marathi_pronunciation_dictionary.dart';

/// Kind of teaching segment — drives pause / emphasis / rate in SSML.
enum SsmlSegmentKind {
  heading,
  definition,
  body,
  emphasis,
  revision,
}

/// One speakable chunk with optional slower rate (definitions).
class SsmlSpeechChunk {
  const SsmlSpeechChunk({
    required this.plainText,
    required this.ssml,
    this.kind = SsmlSegmentKind.body,
    this.speakingRate,
  });

  final String plainText;
  final String ssml;
  final SsmlSegmentKind kind;

  /// Optional Cloud TTS speakingRate override (null = service default).
  final double? speakingRate;
}

/// Module 3 — Convert Marathi faculty script into natural SSML + safe chunks.
class MarathiSsmlConverter {
  MarathiSsmlConverter({
    MarathiPronunciationDictionary? dictionary,
  }) : _dictionary = dictionary ?? marathiPronunciationDictionary;

  final MarathiPronunciationDictionary _dictionary;

  /// Build a full `<speak>` document for a narration segment.
  String toSsml(
    String text, {
    SsmlSegmentKind kind = SsmlSegmentKind.body,
    bool wrapSpeak = true,
  }) {
    final cleaned = facultyNarration(text);
    if (cleaned.isEmpty) {
      return wrapSpeak ? '<speak></speak>' : '';
    }

    final escaped = _escape(cleaned);
    final withPronunciation = _dictionary.applySsmlSubAliases(escaped);
    final withBreaks = _injectPauses(withPronunciation, kind: kind);
    final emphasized = _applyEmphasis(withBreaks, kind: kind);
    final body = _wrapProsody(emphasized, kind: kind);

    return wrapSpeak ? '<speak>$body</speak>' : body;
  }

  /// Soft Cloud TTS UTF-8 budget for Marathi (~5000 byte API limit).
  static const int maxChunkChars = 4200;

  /// Split long narration safely under Cloud TTS limits, returning SSML chunks.
  List<SsmlSpeechChunk> toChunks(
    String text, {
    SsmlSegmentKind kind = SsmlSegmentKind.body,
    int maxChars = maxChunkChars,
  }) {
    final cleaned = facultyNarration(text);
    if (cleaned.isEmpty) return const [];

    final plainChunks = chunkTeachingParagraph(cleaned, maxChars: maxChars);
    return [
      for (final chunk in plainChunks)
        SsmlSpeechChunk(
          plainText: chunk,
          ssml: toSsml(chunk, kind: kind),
          kind: kind,
          speakingRate: kind == SsmlSegmentKind.definition ? 0.82 : null,
        ),
    ];
  }

  /// Infer segment kind from slide title / scene hints (generic, not topic-specific).
  static SsmlSegmentKind inferKind({
    required String text,
    String title = '',
    bool isHeading = false,
  }) {
    if (isHeading) return SsmlSegmentKind.heading;
    final blob = '$title $text'.toLowerCase();
    if (RegExp(r'व्याख्या|definition|म्हणजे काय|अर्थ').hasMatch(blob)) {
      return SsmlSegmentKind.definition;
    }
    if (RegExp(r'पुनरावलोकन|revision|सारांश|summary').hasMatch(blob)) {
      return SsmlSegmentKind.revision;
    }
    if (RegExp(r'महत्त्व|लक्षात|स्मरण|युक्ती|important').hasMatch(blob)) {
      return SsmlSegmentKind.emphasis;
    }
    return SsmlSegmentKind.body;
  }

  String _injectPauses(String escaped, {required SsmlSegmentKind kind}) {
    final headingBreak = kind == SsmlSegmentKind.heading ? '700ms' : '480ms';
    final sentenceBreak = kind == SsmlSegmentKind.definition ? '420ms' : '320ms';

    var out = escaped.replaceAllMapped(
      RegExp(r'([।?!…])\s+'),
      (m) => '${m[1]}<break time="$sentenceBreak"/> ',
    );
    out = out.replaceAllMapped(
      RegExp(r'\.\s+(?=[\u0900-\u097F\w])'),
      (m) => '.<break time="$sentenceBreak"/> ',
    );
    // Heading-style colon / em-dash breaths.
    out = out.replaceAllMapped(
      RegExp(r'([:：—–])\s+'),
      (m) => '${m[1]}<break time="$headingBreak"/> ',
    );
    // Soft comma breath (short).
    out = out.replaceAllMapped(
      RegExp(r'([,;])\s+'),
      (m) => '${m[1]}<break time="140ms"/> ',
    );
    return out;
  }

  String _applyEmphasis(String text, {required SsmlSegmentKind kind}) {
    if (kind != SsmlSegmentKind.emphasis && kind != SsmlSegmentKind.definition) {
      return text;
    }
    // Emphasize short quoted / parenthetical exam keywords without nesting tags badly.
    return text.replaceAllMapped(
      RegExp(r'[""]([^""]{2,40})[""]'),
      (m) => '<emphasis level="moderate">${m[1]}</emphasis>',
    );
  }

  String _wrapProsody(String inner, {required SsmlSegmentKind kind}) {
    switch (kind) {
      case SsmlSegmentKind.definition:
        return '<prosody rate="92%" pitch="-1st" volume="medium">$inner</prosody>';
      case SsmlSegmentKind.heading:
        return '<prosody rate="96%" pitch="-1st" volume="medium">$inner</prosody>';
      case SsmlSegmentKind.revision:
        return '<prosody rate="98%" pitch="-1st" volume="medium">$inner</prosody>';
      case SsmlSegmentKind.emphasis:
        return '<prosody rate="94%" pitch="-1st" volume="medium">$inner</prosody>';
      case SsmlSegmentKind.body:
        return '<prosody pitch="-1st" volume="medium">$inner</prosody>';
    }
  }

  static String _escape(String text) {
    return text
        .trim()
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}

final MarathiSsmlConverter marathiSsmlConverter = MarathiSsmlConverter();
