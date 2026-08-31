import 'package:mpsc_combine_ai/rag/rag_text.dart';

/// A chunk of source text plus the page it started on (if known).
class RagTextChunk {
  const RagTextChunk({
    required this.index,
    required this.text,
    this.pageNumber,
  });

  final int index;
  final String text;
  final int? pageNumber;
}

/// Intelligent packing of cleaned pages into overlapping chunks.
///
/// Splits on paragraph / sentence boundaries. Page numbers are copied from
/// the originating [RagExtractedPage] only — never invented.
class RagChunker {
  const RagChunker({
    this.targetChars = 1200,
    this.maxChars = 1800,
    this.minChars = 40,
    this.overlapChars = 180,
  });

  final int targetChars;
  final int maxChars;
  final int minChars;
  final int overlapChars;

  List<RagTextChunk> chunkPages(List<RagExtractedPage> pages) {
    final units = <_Unit>[];
    for (final page in pages) {
      final cleaned = cleanRagText(page.text);
      if (cleaned.isEmpty) continue;
      final pageNumber = _validPage(page.pageNumber);
      units.addAll(_splitIntoUnits(cleaned, pageNumber));
    }
    return _pack(units);
  }

  List<RagTextChunk> chunkText(String text, {int? pageNumber}) {
    return chunkPages([
      RagExtractedPage(pageNumber: pageNumber, text: text),
    ]);
  }

  int? _validPage(int? page) {
    if (page == null) return null;
    if (page < 1) return null;
    return page;
  }

  List<_Unit> _splitIntoUnits(String text, int? pageNumber) {
    final paragraphs = text
        .split(RegExp(r'\n{2,}'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty && text.trim().isNotEmpty) {
      paragraphs.add(text.trim());
    }
    final units = <_Unit>[];
    for (final para in paragraphs) {
      if (para.length <= maxChars) {
        units.add(_Unit(para, pageNumber));
        continue;
      }
      for (final sentence in _splitSentences(para)) {
        if (sentence.length <= maxChars) {
          units.add(_Unit(sentence, pageNumber));
          continue;
        }
        for (final piece in _hardWrap(sentence, maxChars)) {
          units.add(_Unit(piece, pageNumber));
        }
      }
    }
    return units;
  }

  List<String> _splitSentences(String text) {
    final parts = text.split(RegExp(r'(?<=[।.!?])\s+'));
    return [
      for (final p in parts)
        if (p.trim().isNotEmpty) p.trim(),
    ];
  }

  List<String> _hardWrap(String text, int width) {
    final out = <String>[];
    var remaining = text;
    while (remaining.length > width) {
      var cut = remaining.lastIndexOf(' ', width);
      if (cut < width ~/ 2) cut = width;
      out.add(remaining.substring(0, cut).trim());
      remaining = remaining.substring(cut).trim();
    }
    if (remaining.isNotEmpty) out.add(remaining);
    return out;
  }

  List<RagTextChunk> _pack(List<_Unit> units) {
    if (units.isEmpty) return const [];
    final chunks = <RagTextChunk>[];
    var buf = StringBuffer();
    int? page;
    var index = 0;

    void flush() {
      final text = cleanRagText(buf.toString());
      buf = StringBuffer();
      if (text.length < minChars) {
        page = null;
        return;
      }
      chunks.add(RagTextChunk(index: index, text: text, pageNumber: page));
      index++;
      page = null;
    }

    for (final unit in units) {
      final next = unit.text;
      if (buf.isEmpty) {
        buf.write(next);
        page = unit.pageNumber;
        continue;
      }
      final pageChanged = unit.pageNumber != page;
      if (pageChanged || buf.length + 1 + next.length > targetChars) {
        final overlap = pageChanged ? '' : _overlapTail(buf.toString());
        flush();
        if (overlap.isNotEmpty) {
          buf.write(overlap);
          buf.write('\n\n');
        }
        buf.write(next);
        page = unit.pageNumber;
        continue;
      }
      buf.write('\n\n');
      buf.write(next);
    }
    flush();
    if (chunks.isEmpty) {
      final all = cleanRagText(units.map((u) => u.text).join('\n\n'));
      if (all.isNotEmpty) {
        chunks.add(
          RagTextChunk(index: 0, text: all, pageNumber: units.first.pageNumber),
        );
      }
    }
    return chunks;
  }

  String _overlapTail(String text) {
    if (overlapChars <= 0 || text.length <= overlapChars) return '';
    var tail = text.substring(text.length - overlapChars);
    final breakAt = tail.indexOf(RegExp(r'\s'));
    if (breakAt > 0 && breakAt < tail.length - 8) {
      tail = tail.substring(breakAt).trimLeft();
    }
    return tail.trim();
  }
}

class _Unit {
  const _Unit(this.text, this.pageNumber);
  final String text;
  final int? pageNumber;
}

const RagChunker ragChunker = RagChunker();
