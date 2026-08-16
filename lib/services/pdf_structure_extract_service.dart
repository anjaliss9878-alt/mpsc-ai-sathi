import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/models/pdf_content_block.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Extracts typed content blocks from a Topic PDF via Gemini multimodal.
///
/// Preserves headings, tables, bullets, timelines, flowcharts, diagrams, and
/// charts as separate [PdfContentBlock]s — never a single flattened paragraph.
/// Optimized for Marathi (Devanagari) study PDFs.
class PdfStructureExtractService {
  PdfStructureExtractService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const String _apiKey = String.fromEnvironment('AI_API_KEY');
  static const String _model = String.fromEnvironment(
    'AI_MODEL',
    defaultValue: 'gemini-flash-latest',
  );
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Soft cap for extraction uploads (base64 expands ~33%).
  static const int maxPdfBytes = 8 * 1024 * 1024;

  bool get isConfigured => _apiKey.trim().isNotEmpty;

  Future<List<PdfContentBlock>> extractFromPdfBytes({
    required Uint8List bytes,
    String fileName = 'notes.pdf',
    String topicHint = '',
  }) async {
    if (bytes.isEmpty) return const [];
    if (!isConfigured) {
      debugPrint(
        '[PdfExtract] AI_API_KEY missing — skipping structured extraction.',
      );
      return const [];
    }
    if (bytes.length > maxPdfBytes) {
      throw StateError(
        'PDF is too large for structured extraction '
        '(${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB). '
        'Keep under ${maxPdfBytes ~/ (1024 * 1024)} MB.',
      );
    }

    final topic = topicHint.trim();
    final prompt = StringBuffer()
      ..writeln(
        'You extract STRUCTURED study content from an MPSC Topic PDF.',
      )
      ..writeln(
        'Language: preserve Marathi (Devanagari) exactly — do not transliterate '
        'or translate unless the PDF itself is English.',
      )
      ..writeln(
        'CRITICAL: Do NOT flatten the PDF into one paragraph or one text blob.',
      )
      ..writeln(
        'Return ONE JSON object: {"blocks":[...]} where each block keeps its type.',
      )
      ..writeln()
      ..writeln('Allowed block "type" values:')
      ..writeln('- heading — section / chapter titles')
      ..writeln('- paragraph — short body text under a heading')
      ..writeln('- bullets — list items (use "bullets":["..."])')
      ..writeln(
        '- table — comparison / data tables '
        '("tableHeaders":[...],"tableRows":[[...]])',
      )
      ..writeln(
        '- timeline — chronology '
        '("timeline":[{"year":"...","label":"..."}])',
      )
      ..writeln(
        '- flowchart — process / steps '
        '("flowchart":[{"id":"1","label":"...","nextIds":["2"]}])',
      )
      ..writeln(
        '- diagram — figures / mind-map style visuals '
        '("title","caption","bullets" for labeled parts)',
      )
      ..writeln(
        '- chart — bar/pie style data '
        '("chartLabels":[...],"chartValues":[numbers])',
      )
      ..writeln()
      ..writeln('Rules:')
      ..writeln('- Cover the whole PDF syllabus in order.')
      ..writeln('- Keep board-friendly short titles.')
      ..writeln('- Prefer many typed blocks over one long paragraph.')
      ..writeln('- Optional "pageHint" (1-based page number) when clear.')
      ..writeln(
        topic.isEmpty ? '' : 'Topic hint: $topic',
      )
      ..writeln('File name: $fileName');

    final uri = Uri.parse('$_baseUrl/$_model:generateContent');
    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {
            'text':
                'You are a careful Marathi MPSC notes parser. Output JSON only. '
                'Never invent facts absent from the PDF. Never flatten structure.',
          },
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt.toString()},
            {
              'inline_data': {
                'mime_type': 'application/pdf',
                'data': base64Encode(bytes),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'temperature': 0.2,
      },
    });

    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': _apiKey,
          },
          body: body,
        )
        .timeout(const Duration(seconds: 180));

    if (response.statusCode != 200) {
      final snippet = response.body.length > 240
          ? '${response.body.substring(0, 240)}…'
          : response.body;
      throw StateError(
        'PDF structure extraction failed (HTTP ${response.statusCode}). $snippet',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = asMapList(decoded['candidates']);
    if (candidates.isEmpty) return const [];
    final content = candidates.first['content'];
    final contentMap =
        content is Map ? Map<String, dynamic>.from(content) : null;
    final parts = asMapList(contentMap?['parts']);
    final text = parts.isNotEmpty ? parts.first['text'] as String? : null;
    if (text == null || text.trim().isEmpty) return const [];

    final parsed = jsonDecode(_stripFences(text)) as Map<String, dynamic>;
    final blocks = asMapList(parsed['blocks'] ?? parsed['content'])
        .map(PdfContentBlock.fromMap)
        .where(_isUsefulBlock)
        .toList(growable: false);
    return blocks;
  }

  bool _isUsefulBlock(PdfContentBlock b) {
    return b.title.trim().isNotEmpty ||
        b.text.trim().isNotEmpty ||
        b.bullets.isNotEmpty ||
        b.tableHeaders.isNotEmpty ||
        b.tableRows.isNotEmpty ||
        b.timeline.isNotEmpty ||
        b.flowchart.isNotEmpty ||
        b.chartLabels.isNotEmpty ||
        b.caption.trim().isNotEmpty;
  }

  String _stripFences(String raw) {
    var t = raw.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
      t = t.replaceFirst(RegExp(r'\s*```$'), '');
    }
    return t.trim();
  }
}

final PdfStructureExtractService pdfStructureExtractService =
    PdfStructureExtractService();
