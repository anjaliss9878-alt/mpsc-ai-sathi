import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Default exam label for MPSC Combine RAG sources.
const String kMpscDefaultExam = 'MPSC Combined Group B and C';

/// Embedding dimensionality used with `gemini-embedding-001` (outputDimensionality 768).
const int kRagEmbeddingDimensions = 768;

/// Cleans extracted source text without inventing content.
///
/// Collapses noisy whitespace, strips NULs / form-feeds, and keeps
/// Devanagari + Latin as-is. Does not translate or paraphrase.
String cleanRagText(String raw) {
  var text = raw.replaceAll('\u0000', ' ').replaceAll('\f', '\n');
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = text.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  return text.trim();
}

/// SHA-256 of cleaned extracted text. Used to skip re-embedding unchanged docs.
String ragContentHash(String cleanedText) {
  return sha256.convert(utf8.encode(cleanedText)).toString();
}

/// Best-effort language tag. Never guesses a page number; this is script detection.
String detectRagLanguage(String text) {
  final sample = text.length > 800 ? text.substring(0, 800) : text;
  var devanagari = 0;
  var latin = 0;
  for (final rune in sample.runes) {
    if (rune >= 0x0900 && rune <= 0x097F) {
      devanagari++;
    } else if ((rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A)) {
      latin++;
    }
  }
  if (devanagari == 0 && latin == 0) return 'und';
  if (devanagari > 0 && latin > 0) return 'mr-en';
  if (devanagari > 0) return 'mr';
  return 'en';
}

/// Lowercased keyword tokens for hybrid (keyword + vector) retrieval.
List<String> ragKeywordTokens(String text, {int limit = 48}) {
  final seen = <String>{};
  final out = <String>[];
  final matches = RegExp(r'[\u0900-\u097F\w]{2,}', unicode: true)
      .allMatches(text.toLowerCase());
  for (final m in matches) {
    final t = m.group(0)!;
    if (seen.add(t)) {
      out.add(t);
      if (out.length >= limit) break;
    }
  }
  return out;
}

/// One extracted page. [pageNumber] is the 1-based PDF page index, or null
/// when the extractor could not observe a real page boundary.
class RagExtractedPage {
  const RagExtractedPage({this.pageNumber, required this.text});

  final int? pageNumber;
  final String text;
}
