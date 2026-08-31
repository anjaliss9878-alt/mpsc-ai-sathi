import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
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
    this.examId = kDefaultExamId,
    this.topicId = '',
    this.subTopicId = '',
    this.title = '',
    this.description = '',
    this.language = '',
    this.difficulty = '',
    this.source = '',
    this.contentMarkdown = '',
    this.attachments = const [],
    this.pdfStructuredBlocks = const [],
    this.pdfUrl = '',
    this.pdfStoragePath = '',
    this.pdfFileName = '',
    this.pdfFileSize = 0,
    this.pdfPageCount = 0,
    this.videoUrl = '',
    this.imageUrls = const [],
    this.docxUrl = '',
    this.keywords = const [],
    this.mcqs = const [],
    this.published = true,
    this.status = NoteWorkflowStatus.published,
    this.ragStatus = NoteRagStatus.notIndexed,
    this.ragSourceId = '',
    this.ragError = '',
    this.aiSummary = '',
    this.tags = const [],
    this.updatedAt,
  });

  final String id;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final String subTopicId;

  /// Display title for this note package (falls back to topic title in UI).
  final String title;
  final String description;
  final String language;
  final String difficulty;

  /// Source / reference shown in admin (also copied onto RAG metadata).
  final String source;
  final List<String> importantPoints;
  final List<String> revisionSummary;
  final String contentMarkdown;
  final List<NoteAttachment> attachments;

  /// Structure-preserving extraction of the Topic PDF for AI Classroom slides.
  final List<PdfContentBlock> pdfStructuredBlocks;

  /// Primary PDF URL (mirrored from the first `pdf` attachment). Original bytes
  /// are never rewritten — students receive this same file.
  final String pdfUrl;
  final String pdfStoragePath;
  final String pdfFileName;
  final int pdfFileSize;
  final int pdfPageCount;
  final String videoUrl;

  /// Image attachment URLs (flat list of strings — never nested).
  final List<String> imageUrls;

  /// Primary DOCX URL (mirrored from the first `docx` attachment).
  final String docxUrl;
  final List<String> keywords;
  final List<NoteMcq> mcqs;
  final bool published;
  final NoteWorkflowStatus status;
  final NoteRagStatus ragStatus;
  final String ragSourceId;
  final String ragError;
  final String aiSummary;
  final List<String> tags;
  final DateTime? updatedAt;

  bool get isStudentVisible =>
      published && status == NoteWorkflowStatus.published;

  String get resolvedTopicId => topicId.isNotEmpty ? topicId : chapterId;

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
    final published = asBool(map['published'], defaultValue: true);
    final pdfUrl = _firstUrl(
      map['pdfUrl'],
      attachments.where((a) => a.type == 'pdf').map((a) => a.url),
    );
    NoteAttachment? pdfAttachment;
    for (final a in attachments) {
      if (a.type == 'pdf') {
        pdfAttachment = a;
        break;
      }
    }
    return NoteItem(
      id: id,
      examId: (map['examId'] as String?)?.trim().isNotEmpty == true
          ? (map['examId'] as String).trim()
          : kDefaultExamId,
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      topicId: map['topicId'] as String? ?? '',
      subTopicId: map['subTopicId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      language: map['language'] as String? ?? '',
      difficulty: map['difficulty'] as String? ?? '',
      source: map['source'] as String? ?? map['reference'] as String? ?? '',
      importantPoints: asStringList(map['importantPoints']),
      revisionSummary: asStringList(map['revisionSummary']),
      contentMarkdown: map['contentMarkdown'] as String? ?? '',
      attachments: attachments,
      pdfStructuredBlocks: asMapList(
        map['pdfStructuredBlocks'] ?? map['pdfBlocks'],
      ).map(PdfContentBlock.fromMap).toList(),
      pdfUrl: pdfUrl,
      pdfStoragePath: map['pdfStoragePath'] as String? ?? '',
      pdfFileName: (map['pdfFileName'] as String?)?.trim().isNotEmpty == true
          ? (map['pdfFileName'] as String).trim()
          : (pdfAttachment?.name ?? ''),
      pdfFileSize: asInt(map['pdfFileSize']),
      pdfPageCount: asInt(map['pdfPageCount']),
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
      published: published,
      status: noteWorkflowStatusFromString(
        map['status'] as String?,
        published: published,
      ),
      ragStatus: noteRagStatusFromString(map['ragStatus'] as String?),
      ragSourceId: map['ragSourceId'] as String? ?? '',
      ragError: map['ragError'] as String? ?? '',
      aiSummary: map['aiSummary'] as String? ?? '',
      tags: asStringList(map['tags']),
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'examId': examId.isEmpty ? kDefaultExamId : examId,
      'subjectId': subjectId,
      'chapterId': chapterId,
      'topicId': topicId,
      'subTopicId': subTopicId,
      'title': title,
      'description': description,
      'language': language,
      'difficulty': difficulty,
      'source': source,
      'importantPoints': importantPoints,
      'revisionSummary': revisionSummary,
      'contentMarkdown': contentMarkdown,
      'attachments': attachments.map((a) => a.toMap()).toList(),
      'pdfStructuredBlocks':
          pdfStructuredBlocks.map((b) => b.toMap()).toList(),
      'pdfUrl': pdfUrl,
      'pdfStoragePath': pdfStoragePath,
      'pdfFileName': pdfFileName,
      'pdfFileSize': pdfFileSize,
      'pdfPageCount': pdfPageCount,
      'videoUrl': videoUrl,
      'imageUrls': imageUrls,
      'docxUrl': docxUrl,
      'keywords': keywords,
      'mcqs': mcqs.map((m) => m.toMap()).toList(),
      'published': noteWorkflowPublishedFlag(status),
      'status': noteWorkflowStatusToString(status),
      'ragStatus': noteRagStatusToString(ragStatus),
      'ragSourceId': ragSourceId,
      'ragError': ragError,
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
