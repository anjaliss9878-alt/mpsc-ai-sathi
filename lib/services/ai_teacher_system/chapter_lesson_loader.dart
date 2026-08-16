import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/pdf_content_block.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';

/// Notes + optional PDF bytes loaded from Firebase for chapter teaching.
class ChapterLessonSource {
  const ChapterLessonSource({
    required this.chapter,
    required this.subjectTitle,
    required this.notesText,
    this.note,
    this.pdfBytes,
    this.pdfFileName = '',
    this.pdfStructuredBlocks = const [],
    this.pdfIsPrimary = false,
  });

  final ChapterItem chapter;
  final String subjectTitle;
  final String notesText;
  final NoteItem? note;
  final Uint8List? pdfBytes;
  final String pdfFileName;

  /// Typed blocks extracted from the Topic PDF (never a flat paragraph dump).
  final List<PdfContentBlock> pdfStructuredBlocks;

  /// True when a PDF is available and should drive AI Classroom slides.
  final bool pdfIsPrimary;

  bool get hasPdf =>
      (pdfBytes != null && pdfBytes!.isNotEmpty) ||
      pdfStructuredBlocks.isNotEmpty ||
      chapter.pdfUrl.trim().isNotEmpty;
}

/// Loads chapter notes from Firestore and, when a PDF attachment / pdfUrl
/// exists, downloads its bytes so Gemini can use the PDF as the primary source.
class ChapterLessonLoader {
  ChapterLessonLoader({
    NotesRepository? notes,
    http.Client? client,
  })  : _notes = notes ?? notesRepository,
        _client = client ?? http.Client();

  final NotesRepository _notes;
  final http.Client _client;

  /// Max PDF size sent to Gemini (base64 expands ~33%). Keep uploads lean.
  static const int maxPdfBytes = 8 * 1024 * 1024;

  Future<ChapterLessonSource> load({
    required ChapterItem chapter,
    required String subjectTitle,
    bool publishedOnly = false,
  }) async {
    final rawNote = await _notes.getNoteForChapter(chapter.id);
    final note = (rawNote != null && publishedOnly && !rawNote.published)
        ? null
        : rawNote;

    final pdfBlocks = note?.pdfStructuredBlocks ?? const <PdfContentBlock>[];
    final pdfAttachment = _resolvePdfAttachment(note: note, chapter: chapter);

    final buffer = StringBuffer();
    buffer.writeln('Subject: $subjectTitle');
    buffer.writeln('Chapter: ${chapter.title}');
    if (chapter.description.trim().isNotEmpty) {
      buffer.writeln('Description: ${chapter.description}');
    }

    final hasPdfCandidate = pdfAttachment != null ||
        pdfBlocks.isNotEmpty ||
        chapter.pdfUrl.trim().isNotEmpty;

    if (hasPdfCandidate) {
      buffer.writeln();
      buffer.writeln(
        'PRIMARY SOURCE: Topic PDF'
        '${pdfAttachment == null ? '' : ' ("${pdfAttachment.name}")'}.',
      );
      buffer.writeln(
        'Generate classroom slides from the PDF structure '
        '(headings, tables, bullets, timelines, flowcharts, diagrams, charts). '
        'Do NOT flatten the PDF into one paragraph.',
      );
    }

    if (pdfBlocks.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(pdfBlocksToStructuredDocument(pdfBlocks));
    }

    if (note != null) {
      buffer.writeln();
      buffer.writeln(
        hasPdfCandidate
            ? 'SECONDARY TEXT NOTES (use only to fill gaps; PDF wins on conflict):'
            : 'Verified text notes:',
      );
      if (note.importantPoints.isNotEmpty) {
        buffer.writeln('Important points:');
        for (final p in note.importantPoints) {
          buffer.writeln('- $p');
        }
      }
      if (note.revisionSummary.isNotEmpty) {
        buffer.writeln('Revision summary:');
        for (final p in note.revisionSummary) {
          buffer.writeln('- $p');
        }
      }
      if (note.contentMarkdown.trim().isNotEmpty) {
        buffer.writeln('Notes markdown:');
        buffer.writeln(note.contentMarkdown);
      }
      if (note.keywords.isNotEmpty) {
        buffer.writeln('Keywords: ${note.keywords.join(', ')}');
      }
    } else if (!hasPdfCandidate) {
      buffer.writeln(
        'No detailed notes document found — teach from the chapter title '
        'and MPSC syllabus knowledge only. Do not invent specific statutes '
        'or figures you are unsure about.',
      );
    }

    Uint8List? pdfBytes;
    var pdfName = pdfAttachment?.name ?? '';
    if (pdfAttachment != null) {
      try {
        final response = await _client
            .get(Uri.parse(pdfAttachment.url))
            .timeout(const Duration(seconds: 45));
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            response.bodyBytes.isNotEmpty &&
            response.bodyBytes.length <= maxPdfBytes) {
          pdfBytes = response.bodyBytes;
        } else if (response.bodyBytes.length > maxPdfBytes) {
          buffer.writeln(
            'PDF "${pdfAttachment.name}" was too large to attach '
            '(${response.bodyBytes.length} bytes). '
            'Teach from the structured PDF blocks / text notes above.',
          );
        }
      } catch (_) {
        buffer.writeln(
          'PDF "${pdfAttachment.name}" could not be downloaded. '
          'Teach from the structured PDF blocks / text notes above.',
        );
      }
    }

    final pdfIsPrimary = (pdfBytes != null && pdfBytes.isNotEmpty) ||
        pdfBlocks.isNotEmpty;

    return ChapterLessonSource(
      chapter: chapter,
      subjectTitle: subjectTitle,
      notesText: buffer.toString(),
      note: note,
      pdfBytes: pdfBytes,
      pdfFileName: pdfName,
      pdfStructuredBlocks: pdfBlocks,
      pdfIsPrimary: pdfIsPrimary,
    );
  }

  NoteAttachment? _resolvePdfAttachment({
    required NoteItem? note,
    required ChapterItem chapter,
  }) {
    final fromNote =
        note?.attachments.where((a) => a.type == 'pdf' && a.url.isNotEmpty);
    if (fromNote != null && fromNote.isNotEmpty) return fromNote.first;
    final url = chapter.pdfUrl.trim();
    if (url.isEmpty) return null;
    return NoteAttachment(name: 'Topic PDF', url: url, type: 'pdf');
  }
}

final ChapterLessonLoader chapterLessonLoader = ChapterLessonLoader();

/// Helper for Gemini multimodal parts.
String encodePdfBase64(Uint8List bytes) => base64Encode(bytes);
