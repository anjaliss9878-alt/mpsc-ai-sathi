import 'package:mpsc_combine_ai/rag/rag_extract_quality.dart';
import 'package:mpsc_combine_ai/rag/rag_pdf_page_image.dart';
import 'package:mpsc_combine_ai/rag/rag_text.dart';

const String kRagPdfImageOcrSystemPrompt =
    'You transcribe rendered PDF page images for RAG. JSON only. '
    'Never invent page numbers. Never invent text that is not visible.';

const String kRagPdfExtractFallbackFailed =
    'PDF extraction failed: page-image OCR fallback could not recover '
    'the document.';

/// Max in-flight Gemini page-OCR calls on the local worker.
const int kRagPageOcrConcurrency = 3;

/// Runs [task] for `0..count-1` with at most [limit] tasks in flight.
Future<List<T>> ragMapLimited<T>(
  int count,
  int limit,
  Future<T> Function(int index) task,
) async {
  if (count <= 0) return const [];
  final out = List<T?>.filled(count, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final i = next;
      next += 1;
      if (i >= count) return;
      out[i] = await task(i);
    }
  }

  final n = limit < 1 ? 1 : (limit > count ? count : limit);
  await Future.wait([for (var i = 0; i < n; i++) worker()]);
  return [for (final v in out) v as T];
}

/// Worker / debug trace. HTTP `/rag/extract` still returns `{pages:[...]}` only.
class RagPdfExtractTrace {
  const RagPdfExtractTrace({
    required this.corrupted,
    required this.rasterizedPages,
    required this.ocrPages,
    required this.path,
  });

  final bool corrupted;
  final int rasterizedPages;
  final int ocrPages;

  /// `pdf-bytes` or `image-ocr`.
  final String path;
}

/// Strong OCR prompt: read pixels, emit NFC Devanagari, keep English as-is.
String ragPdfImageOcrUserPrompt({required String title}) {
  final hint = title.trim().isEmpty ? '(none)' : title.trim();
  return 'Transcribe ALL visible text from this rendered PDF page image.\n'
      'This is OCR of PIXELS only. Ignore any broken/hidden PDF text layer.\n'
      'Marathi must be correct Unicode Devanagari (NFC). '
      'Do not emit isolated vowel signs such as ि at the start of a cluster; '
      'attach matras to the proper consonants. '
      'Do not copy Kruti/DevLys/CID encodings or ASCII mojibake.\n'
      'Preserve English, digits, punctuation, and mixed Marathi–English exactly. '
      'Do not translate. Do not invent headings or paragraphs.\n'
      'Return ONE JSON object only: {"pages":[{"page":<N>,"text":"..."}]}.\n'
      '"page" MUST be the 1-based PDF page index given with the image.\n'
      'Title hint: $hint';
}

/// True when the PDF-bytes Gemini call failed because JSON was truncated
/// or otherwise unparseable — use page-image OCR instead of HTTP 500.
bool ragPdfBytesExtractShouldUseImageFallback(Object error) {
  final lower = '$error'.toLowerCase();
  return lower.contains('response parsing') ||
      lower.contains('max_tokens') ||
      lower.contains('truncated');
}

/// PDF-bytes extract first. Image OCR when Unicode looks corrupted **or**
/// when Gemini returns truncated / unparseable JSON (MAX_TOKENS).
///
/// Never returns known-corrupt PDF-bytes text as a successful extract.
Future<Map<String, dynamic>> extractPdfWithCorruptionFallback({
  required Future<Map<String, dynamic>> Function() extractFromPdfBytes,
  required Future<List<RagPdfPageImage>> Function({required Set<int> pageNumbers})
      rasterizePages,
  required Future<Map<String, dynamic>> Function(List<RagPdfPageImage> images)
      extractFromPageImages,
  void Function(RagPdfExtractTrace trace)? onTrace,
}) async {
  void trace({
    required bool corrupted,
    required int rasterizedPages,
    required int ocrPages,
    required String path,
  }) {
    onTrace?.call(
      RagPdfExtractTrace(
        corrupted: corrupted,
        rasterizedPages: rasterizedPages,
        ocrPages: ocrPages,
        path: path,
      ),
    );
  }

  Object? firstError;
  Map<String, dynamic>? first;
  try {
    first = await extractFromPdfBytes();
  } catch (e) {
    if (!ragPdfBytesExtractShouldUseImageFallback(e)) rethrow;
    firstError = e;
  }

  final cleaned =
      first == null ? <Map<String, dynamic>>[] : _normalizeExtractPages(first);
  final pageModels = [
    for (final p in cleaned)
      RagExtractedPage(
        pageNumber: p['page'] is int ? p['page'] as int : null,
        text: '${p['text']}',
      ),
  ];
  final corrupted =
      pageModels.isNotEmpty && ragExtractedPagesLookCorrupted(pageModels);
  if (firstError == null && !corrupted) {
    trace(
      corrupted: false,
      rasterizedPages: 0,
      ocrPages: 0,
      path: 'pdf-bytes',
    );
    if (first != null && cleaned.isEmpty) return first;
    return {'pages': cleaned};
  }

  List<RagPdfPageImage> images;
  try {
    images = await rasterizePages(
      pageNumbers: firstError != null
          ? const {}
          : ragCorruptExtractPageNumbers(pageModels),
    );
  } catch (e) {
    throw StateError('$kRagPdfExtractFallbackFailed Rasterization failed: $e');
  }
  if (images.isEmpty) {
    throw StateError(
      '$kRagPdfExtractFallbackFailed Rasterization returned no page images.',
    );
  }

  Map<String, dynamic> ocr;
  try {
    ocr = await extractFromPageImages(images);
  } catch (e) {
    throw StateError('$kRagPdfExtractFallbackFailed OCR failed: $e');
  }
  final ocrPages = _normalizeExtractPages(ocr);
  if (ocrPages.isEmpty) {
    throw StateError(
      '$kRagPdfExtractFallbackFailed OCR returned no page text.',
    );
  }
  trace(
    corrupted: true,
    rasterizedPages: images.length,
    ocrPages: ocrPages.length,
    path: 'image-ocr',
  );
  if (firstError != null || cleaned.isEmpty) {
    return {'pages': ocrPages};
  }
  return {
    'pages': _mergeExtractPages(cleaned, ocrPages, images),
  };
}

List<Map<String, dynamic>> _normalizeExtractPages(Map<String, dynamic> map) {
  final raw = map['pages'];
  final out = <Map<String, dynamic>>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is! Map) continue;
      final text = '${item['text'] ?? ''}'.trim();
      if (text.isEmpty) continue;
      final page = item['page'];
      if (page is num && page.toInt() >= 1) {
        out.add({'page': page.toInt(), 'text': text});
      } else {
        out.add({'text': text});
      }
    }
  }
  if (out.isEmpty) {
    final blob = '${map['text'] ?? ''}'.trim();
    if (blob.isNotEmpty) out.add({'text': blob});
  }
  return out;
}

List<Map<String, dynamic>> _mergeExtractPages(
  List<Map<String, dynamic>> original,
  List<Map<String, dynamic>> ocr,
  List<RagPdfPageImage> images,
) {
  final byPage = <int, String>{};
  for (final p in ocr) {
    final page = p['page'];
    final text = '${p['text'] ?? ''}'.trim();
    if (page is int && text.isNotEmpty) byPage[page] = text;
  }
  if (ocr.length == images.length) {
    for (var i = 0; i < images.length; i++) {
      final text = '${ocr[i]['text']}'.trim();
      if (text.isNotEmpty) byPage[images[i].pageNumber] = text;
    }
  }
  if (byPage.isEmpty) return ocr;

  final numbered = original.every((p) => p['page'] is int);
  if (!numbered) return ocr;

  return [
    for (final p in original)
      if (byPage.containsKey(p['page'] as int))
        {'page': p['page'], 'text': byPage[p['page'] as int]!}
      else
        p,
  ];
}
