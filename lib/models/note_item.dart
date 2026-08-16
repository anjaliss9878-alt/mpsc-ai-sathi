import 'package:mpsc_combine_ai/models/pdf_content_block.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// A file (PDF/DOCX/image) attached to a [NoteItem], uploaded to Firebase
/// Storage from the Admin Panel.
class NoteAttachment {
  const NoteAttachment({required this.name, required this.url, required this.type});

  final String name;
  final String url;

  /// One of: `pdf`, `docx`, `image`, `other` — used to pick an icon/preview.
  final String type;

  factory NoteAttachment.fromMap(Map<String, dynamic> map) {
    return NoteAttachment(
      name: map['name'] as String? ?? '',
      url: map['url'] as String? ?? '',
      type: map['type'] as String? ?? 'other',
    );
  }

  Map<String, dynamic> toMap() => {'name': name, 'url': url, 'type': type};
}

/// Optional MCQ authored with a chapter's notes (stored on the note document).
class NoteMcq {
  const NoteMcq({
    required this.question,
    required this.options,
    required this.correctIndex,
    this.explanation = '',
  });

  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  factory NoteMcq.fromMap(Map<String, dynamic> map) {
    return NoteMcq(
      question: map['question'] as String? ?? '',
      options: asStringList(map['options']),
      correctIndex: (map['correctIndex'] as num?)?.toInt() ?? 0,
      explanation: map['explanation'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'question': question,
        'options': asStringList(options),
        'correctIndex': correctIndex,
        'explanation': explanation,
      };
}

/// Detailed notes for a chapter, stored in Firestore at `notes/{id}`.
///
/// Two content styles live side by side so nothing existing breaks:
/// - [importantPoints] / [revisionSummary]: the original "one bullet per
///   line" lists rendered by the existing student `NotesDetailScreen`.
/// - [contentMarkdown]: an optional richer Markdown body (headings, bold,
///   lists, tables) authored in the Admin Panel's Markdown editor and
///   rendered with the same Markdown renderer already used by the AI
///   Teacher chat. Empty by default — legacy notes keep working exactly as
///   before.
/// - [attachments]: optional PDF/DOCX/image files uploaded to Storage.
/// - [pdfUrl] / [videoUrl] / [imageUrls] / [docxUrl]: denormalized media
///   URLs so clients do not have to scan [attachments].
/// - [pdfStructuredBlocks]: typed blocks extracted from the Topic PDF
///   (headings / tables / timelines / flowcharts / …) — never a flat dump.
/// - [keywords] / [mcqs]: optional chapter learning extras.
class NoteItem {
  const NoteItem({
    required this.id,
    required this.subjectId,
    required this.chapterId,
    required this.importantPoints,
    required this.revisionSummary,
    this.title = '',
    this.contentMarkdown = '',
    this.attachments = const [],
    this.pdfStructuredBlocks = const [],
    this.pdfUrl = '',
    this.videoUrl = '',
    this.imageUrls = const [],
    this.docxUrl = '',
    this.keywords = const [],
    this.mcqs = const [],
    this.published = true,
    this.aiSummary = '',
    this.tags = const [],
    this.updatedAt,
  });

  final String id;
  final String subjectId;
  final String chapterId;

  /// Display title for this note package (falls back to topic title in UI).
  final String title;
  final List<String> importantPoints;
  final List<String> revisionSummary;
  final String contentMarkdown;
  final List<NoteAttachment> attachments;

  /// Structure-preserving extraction of the Topic PDF for AI Classroom slides.
  final List<PdfContentBlock> pdfStructuredBlocks;

  /// Primary PDF URL (mirrored from the first `pdf` attachment).
  final String pdfUrl;
  final String videoUrl;

  /// Image attachment URLs (flat list of strings — never nested).
  final List<String> imageUrls;

  /// Primary DOCX URL (mirrored from the first `docx` attachment).
  final String docxUrl;
  final List<String> keywords;
  final List<NoteMcq> mcqs;
  final bool published;
  final String aiSummary;
  final List<String> tags;
  final DateTime? updatedAt;

  factory NoteItem.fromMap(Map<String, dynamic> map, String id) {
    DateTime? updatedAt;
    final rawUpdated = map['updatedAt'];
    if (rawUpdated is String && rawUpdated.isNotEmpty) {
      updatedAt = DateTime.tryParse(rawUpdated);
    }
    final attachments = asMapList(map['attachments'])
        .map(NoteAttachment.fromMap)
        .toList();
    final storedImages = asStringList(map['imageUrls']);
    return NoteItem(
      id: id,
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      importantPoints: asStringList(map['importantPoints']),
      revisionSummary: asStringList(map['revisionSummary']),
      contentMarkdown: map['contentMarkdown'] as String? ?? '',
      attachments: attachments,
      pdfStructuredBlocks: asMapList(
        map['pdfStructuredBlocks'] ?? map['pdfBlocks'],
      ).map(PdfContentBlock.fromMap).toList(),
      pdfUrl: _firstUrl(
        map['pdfUrl'],
        attachments.where((a) => a.type == 'pdf').map((a) => a.url),
      ),
      videoUrl: (map['videoUrl'] as String?)?.trim() ?? '',
      imageUrls: storedImages.isNotEmpty
          ? storedImages
          : [
              for (final a in attachments)
                if (a.type == 'image' && a.url.isNotEmpty) a.url,
            ],
      docxUrl: _firstUrl(
        map['docxUrl'],
        attachments.where((a) => a.type == 'docx').map((a) => a.url),
      ),
      keywords: asStringList(map['keywords']),
      mcqs: asMapList(map['mcqs']).map(NoteMcq.fromMap).toList(),
      published: asBool(map['published'], defaultValue: true),
      aiSummary: map['aiSummary'] as String? ?? '',
      tags: asStringList(map['tags']),
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'subjectId': subjectId,
      'chapterId': chapterId,
      'title': title,
      'importantPoints': importantPoints,
      'revisionSummary': revisionSummary,
      'contentMarkdown': contentMarkdown,
      'attachments': attachments.map((a) => a.toMap()).toList(),
      'pdfStructuredBlocks':
          pdfStructuredBlocks.map((b) => b.toMap()).toList(),
      'pdfUrl': pdfUrl,
      'videoUrl': videoUrl,
      'imageUrls': imageUrls,
      'docxUrl': docxUrl,
      'keywords': keywords,
      'mcqs': mcqs.map((m) => m.toMap()).toList(),
      'published': published,
      'aiSummary': aiSummary,
      'tags': tags,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }
}

String _firstUrl(dynamic stored, Iterable<String> fromAttachments) {
  if (stored is String && stored.trim().isNotEmpty) return stored.trim();
  for (final url in fromAttachments) {
    if (url.trim().isNotEmpty) return url.trim();
  }
  return '';
}
