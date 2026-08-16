import 'package:mpsc_combine_ai/services/ai_teacher_system/speakable_marathi.dart';

/// Formats narration for natural MPSC-faculty pacing before TTS.
///
/// Strips PDF symbols and expands abbreviations so the voice never reads
/// "plus", "minus", or "percent".
String facultyNarration(String text) {
  return speakableMarathi(text);
}

/// True when [text] contains Devanagari (Marathi / Hindi script).
bool looksLikeMarathi(String text) =>
    RegExp(r'[\u0900-\u097F]').hasMatch(text);

/// Pause between spoken sentences (faculty breath). 300–500 ms target.
const Duration kTeachingSentencePause = Duration(milliseconds: 400);

/// Longer pause when the teaching stage changes (concept transition).
const Duration kTeachingParagraphPause = Duration(milliseconds: 850);

/// Soft upper bound for one spoken paragraph (chars). Sentence-mode ignores
/// this for splitting — kept for legacy callers / API chunking.
const int kMaxTeachingParagraphChars = 480;

/// Split narration into individual teachable sentences (Marathi danda / Latin).
List<String> splitTeachingSentences(String text) {
  final cleaned = text.trim();
  if (cleaned.isEmpty) return const [];
  final parts = cleaned
      .split(RegExp(r'(?<=[।.?!…])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  return parts.isEmpty ? [cleaned] : parts;
}

/// Smart Faculty pedagogy stages — exact classroom teaching pipeline.
enum SmartFacultyStage {
  introduction,
  concept,
  example,
  memoryTrick,
  pyq,
  mcq,
  revision,
  summary,
}

/// Ordered Smart Faculty pipeline (every concept / lesson).
const List<SmartFacultyStage> kSmartFacultyPipeline = [
  SmartFacultyStage.introduction,
  SmartFacultyStage.concept,
  SmartFacultyStage.example,
  SmartFacultyStage.memoryTrick,
  SmartFacultyStage.pyq,
  SmartFacultyStage.mcq,
  SmartFacultyStage.revision,
  SmartFacultyStage.summary,
];

/// Strips UI/card label prefixes so TTS never sounds like OCR label reading.
String stripFacultyLabelPrefixes(String text) {
  var t = text.trim();
  if (t.isEmpty) return t;
  t = t.replaceFirst(
    RegExp(
      r'^(PYQ\s*Insight|Exam\s*Tip|Memory\s*Trick|Common\s*Mistake|AI\s*MCQ|'
      r'Quick\s*Revision|Key\s*facts|PYQ\s*insight|Memory\s*trick|'
      r'Exam\s*trick|Exam\s*tip)\s*[:.\-—–]?\s*',
      caseSensitive: false,
    ),
    '',
  );
  t = t.replaceFirst(
    RegExp(
      r'^(PYQ\s*दृष्टी|परीक्षा\s*टिप|परीक्षा\s*युक्ती|स्मरण\s*युक्ती|'
      r'सामान्य\s*चूक|जलद\s*पुनरावलोकन|महत्त्वाची\s*तथ्ये|'
      r'युक्ती)\s*[:.\-—–]?\s*',
    ),
    '',
  );
  return t.trim();
}

/// Merges related teaching lines into one continuous paragraph for TTS.
/// Prefer this over speaking many tiny clips back-to-back.
String mergeTeachingParagraph(List<String> parts) {
  final cleaned = parts
      .map((p) => stripFacultyLabelPrefixes(p.trim()))
      .where((p) => p.isNotEmpty)
      .toList();
  if (cleaned.isEmpty) return '';
  if (cleaned.length == 1) return cleaned.first;

  final buf = StringBuffer();
  for (var i = 0; i < cleaned.length; i++) {
    var part = cleaned[i];
    // Ensure sentence-ish ending before joining.
    if (!RegExp(r'[।.?!…]$').hasMatch(part)) {
      part = '$part.';
    }
    if (i > 0) buf.write(' ');
    buf.write(part);
  }
  return buf.toString();
}

/// Builds spoken text for one Smart Faculty stage.
///
/// Faculty voice only — never pastes raw slide OCR / bullet lists.
/// Optional [bridge] is a short warm lead-in; [body] is the teaching content.
String buildSmartFacultyStageSpeech({
  required SmartFacultyStage stage,
  required String body,
  String bridge = '',
  bool marathi = true,
}) {
  final cleanedBody = stripFacultyLabelPrefixes(body);
  final cleanedBridge = stripFacultyLabelPrefixes(bridge);

  String defaultBridge() {
    switch (stage) {
      case SmartFacultyStage.introduction:
        return marathi
            ? 'नमस्कार विद्यार्थी मित्रांनो.'
            : 'Hello students.';
      case SmartFacultyStage.concept:
        return marathi
            ? 'आधी संकल्पना स्वच्छ समजून घेऊया.'
            : 'First, let us understand the concept clearly.';
      case SmartFacultyStage.example:
        return marathi
            ? 'आता एक सोपे, परीक्षेला उपयुक्त उदाहरण पाहूया.'
            : 'Now a simple, exam-useful example.';
      case SmartFacultyStage.memoryTrick:
        return marathi
            ? 'लक्षात राहण्यासाठी ही सोपी युक्ती वापरा.'
            : 'Here is an easy way to remember this.';
      case SmartFacultyStage.pyq:
        return marathi
            ? 'मागील वर्षीच्या प्रश्नांच्या नजरेतून पाहूया.'
            : 'Let us look at this through previous-year questions.';
      case SmartFacultyStage.mcq:
        return marathi
            ? 'थोडा चेक प्रश्न — उत्तर मनात ठरवा.'
            : 'A short check question — decide the answer in your mind.';
      case SmartFacultyStage.revision:
        return marathi
            ? 'जलद पुनरावलोकन करूया.'
            : 'Let us revise quickly.';
      case SmartFacultyStage.summary:
        return marathi
            ? 'थोडक्यात समारोप.'
            : 'A short closing summary.';
    }
  }

  final lead = cleanedBridge.isNotEmpty ? cleanedBridge : defaultBridge();
  if (cleanedBody.isEmpty) {
    return mergeTeachingParagraph([lead]);
  }
  // Avoid duplicating lead when body already starts with similar framing.
  if (cleanedBody.toLowerCase().startsWith(lead.toLowerCase().substring(
        0,
        lead.length > 12 ? 12 : lead.length,
      ))) {
    return mergeTeachingParagraph([cleanedBody]);
  }
  return mergeTeachingParagraph([lead, cleanedBody]);
}

/// Legacy helper: merges explain → example → trick → question into one
/// paragraph. Prefer [buildSmartFacultyStageSpeech] with one stage per beat.
String buildFacultyTeachingParagraph({
  required String explain,
  String example = '',
  String trick = '',
  String question = '',
  bool marathi = true,
}) {
  final parts = <String>[
    stripFacultyLabelPrefixes(explain),
    if (example.trim().isNotEmpty) stripFacultyLabelPrefixes(example),
    if (trick.trim().isNotEmpty) stripFacultyLabelPrefixes(trick),
    if (question.trim().isNotEmpty) stripFacultyLabelPrefixes(question),
  ].where((p) => p.isNotEmpty).toList();

  if (parts.isEmpty) {
    return marathi
        ? 'ही संकल्पना परीक्षा दृष्टीने महत्त्वाची आहे — समजून घेऊया.'
        : 'This concept matters for the exam — let us understand it.';
  }
  return mergeTeachingParagraph(parts);
}

/// Splits an oversized paragraph into speakable chunks at sentence boundaries.
List<String> chunkTeachingParagraph(
  String text, {
  int maxChars = kMaxTeachingParagraphChars,
}) {
  final cleaned = text.trim();
  if (cleaned.isEmpty) return const [];
  if (cleaned.length <= maxChars) return [cleaned];

  final sentences = cleaned
      .split(RegExp(r'(?<=[।.?!…])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (sentences.isEmpty) return [cleaned.substring(0, maxChars)];

  final chunks = <String>[];
  final buf = StringBuffer();
  for (final s in sentences) {
    final next = buf.isEmpty ? s : '${buf.toString()} $s';
    if (next.length > maxChars && buf.isNotEmpty) {
      chunks.add(buf.toString().trim());
      buf
        ..clear()
        ..write(s);
    } else {
      buf
        ..clear()
        ..write(next);
    }
  }
  final last = buf.toString().trim();
  if (last.isNotEmpty) chunks.add(last);
  return chunks;
}
