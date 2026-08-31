import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Role of a `chapters/{id}` document in the content index.
///
/// The existing `chapters` collection is reused — there is no parallel
/// topics collection. Grouping chapters (`chapter`) sit under a subject;
/// topics and sub-topics are child documents via `parentChapterId`.
enum ContentNodeType { chapter, topic, subtopic }

ContentNodeType contentNodeTypeFromString(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'chapter':
      return ContentNodeType.chapter;
    case 'topic':
      return ContentNodeType.topic;
    case 'subtopic':
    case 'sub-topic':
    case 'sub_topic':
      return ContentNodeType.subtopic;
    default:
      // Legacy curriculum rows were stored as leaf chapters (student topics).
      return ContentNodeType.topic;
  }
}

String contentNodeTypeToString(ContentNodeType type) {
  switch (type) {
    case ContentNodeType.chapter:
      return 'chapter';
    case ContentNodeType.topic:
      return 'topic';
    case ContentNodeType.subtopic:
      return 'subtopic';
  }
}

/// Admin workflow for a note. Student visibility is [NoteWorkflowStatus.published]
/// only (mirrored on the existing `published` bool).
enum NoteWorkflowStatus {
  draft,
  underReview,
  approved,
  published,
  unpublished,
}

NoteWorkflowStatus noteWorkflowStatusFromString(
  String? value, {
  bool published = true,
}) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'draft':
      return NoteWorkflowStatus.draft;
    case 'underreview':
    case 'under_review':
    case 'under-review':
    case 'review':
      return NoteWorkflowStatus.underReview;
    case 'approved':
      return NoteWorkflowStatus.approved;
    case 'published':
      return NoteWorkflowStatus.published;
    case 'unpublished':
      return NoteWorkflowStatus.unpublished;
    default:
      return published
          ? NoteWorkflowStatus.published
          : NoteWorkflowStatus.draft;
  }
}

String noteWorkflowStatusToString(NoteWorkflowStatus status) {
  switch (status) {
    case NoteWorkflowStatus.draft:
      return 'draft';
    case NoteWorkflowStatus.underReview:
      return 'underReview';
    case NoteWorkflowStatus.approved:
      return 'approved';
    case NoteWorkflowStatus.published:
      return 'published';
    case NoteWorkflowStatus.unpublished:
      return 'unpublished';
  }
}

String noteWorkflowStatusLabel(NoteWorkflowStatus status) {
  switch (status) {
    case NoteWorkflowStatus.draft:
      return 'Draft';
    case NoteWorkflowStatus.underReview:
      return 'Under Review';
    case NoteWorkflowStatus.approved:
      return 'Approved';
    case NoteWorkflowStatus.published:
      return 'Published';
    case NoteWorkflowStatus.unpublished:
      return 'Unpublished';
  }
}

bool noteWorkflowIsStudentVisible(NoteWorkflowStatus status) {
  return status == NoteWorkflowStatus.published;
}

bool noteWorkflowPublishedFlag(NoteWorkflowStatus status) {
  return status == NoteWorkflowStatus.published;
}

/// Shared workflow alias used by PYQs, MCQs, and Tests (same five states as notes).
typedef ContentWorkflowStatus = NoteWorkflowStatus;

ContentWorkflowStatus contentWorkflowStatusFromString(
  String? value, {
  bool published = true,
}) =>
    noteWorkflowStatusFromString(value, published: published);

String contentWorkflowStatusToString(ContentWorkflowStatus status) =>
    noteWorkflowStatusToString(status);

String contentWorkflowStatusLabel(ContentWorkflowStatus status) =>
    noteWorkflowStatusLabel(status);

bool contentWorkflowIsStudentVisible(ContentWorkflowStatus status) =>
    noteWorkflowIsStudentVisible(status);

bool contentWorkflowPublishedFlag(ContentWorkflowStatus status) =>
    noteWorkflowPublishedFlag(status);

/// Group B / Group C / Both. Stored as `targetGroup` (and mirrored as `groupId`).
enum TargetGroup { groupB, groupC, both }

TargetGroup targetGroupFromString(String? value) {
  switch ((value ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '')) {
    case 'groupc':
    case 'c':
    case 'gc':
      return TargetGroup.groupC;
    case 'both':
    case 'all':
    case 'bc':
    case 'groupbandc':
      return TargetGroup.both;
    default:
      return TargetGroup.groupB;
  }
}

bool isValidTargetGroupLabel(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return false;
  final t = raw.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
  const ok = {
    'groupb',
    'groupc',
    'both',
    'b',
    'c',
    'all',
    'bc',
    'gb',
    'gc',
    'groupbandc',
  };
  return ok.contains(t);
}

String targetGroupToString(TargetGroup group) {
  switch (group) {
    case TargetGroup.groupB:
      return 'groupB';
    case TargetGroup.groupC:
      return 'groupC';
    case TargetGroup.both:
      return 'both';
  }
}

String targetGroupLabel(TargetGroup group) {
  switch (group) {
    case TargetGroup.groupB:
      return 'Group B';
    case TargetGroup.groupC:
      return 'Group C';
    case TargetGroup.both:
      return 'Both';
  }
}

/// True when a PYQ / MCQ / Test document is linked to [topicId]
/// via `topicId`, legacy `chapterId`, or a `topicIds` list.
bool contentLinkedToTopic({
  required String topicId,
  String topicIdField = '',
  String chapterIdField = '',
  List<String> topicIds = const [],
}) {
  if (topicId.isEmpty) return false;
  if (topicIdField == topicId) return true;
  if (chapterIdField == topicId) return true;
  return topicIds.contains(topicId);
}

bool _sameCalendarDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Shared Admin list filters (Group / Subject / Chapter / Topic / Status /
/// Difficulty / Date / search). Empty filter values are ignored.
bool matchesAdminContentFilters({
  String query = '',
  Iterable<String> fields = const [],
  String? targetGroup,
  String itemTargetGroup = '',
  NoteWorkflowStatus? status,
  NoteWorkflowStatus? itemStatus,
  String? difficulty,
  String itemDifficulty = '',
  String? language,
  String itemLanguage = '',
  String? subjectId,
  String itemSubjectId = '',
  String? chapterId,
  String itemChapterId = '',
  String? topicId,
  String itemTopicId = '',
  DateTime? date,
  DateTime? itemDate,
}) {
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    var hit = false;
    for (final field in fields) {
      if (field.toLowerCase().contains(q)) {
        hit = true;
        break;
      }
    }
    if (!hit) return false;
  }
  if (targetGroup != null &&
      targetGroup.isNotEmpty &&
      itemTargetGroup != targetGroup) {
    return false;
  }
  if (status != null && itemStatus != status) return false;
  if (difficulty != null &&
      difficulty.isNotEmpty &&
      itemDifficulty != difficulty) {
    return false;
  }
  if (language != null &&
      language.isNotEmpty &&
      itemLanguage != language) {
    return false;
  }
  if (subjectId != null &&
      subjectId.isNotEmpty &&
      itemSubjectId != subjectId) {
    return false;
  }
  if (chapterId != null &&
      chapterId.isNotEmpty &&
      itemChapterId != chapterId &&
      itemTopicId != chapterId) {
    return false;
  }
  if (topicId != null &&
      topicId.isNotEmpty &&
      itemTopicId != topicId &&
      itemChapterId != topicId) {
    return false;
  }
  if (date != null && itemDate != null && !_sameCalendarDay(date, itemDate)) {
    return false;
  }
  return true;
}

/// RAG index lifecycle stored on the note (mirrors `ragSources.status`).
enum NoteRagStatus { notIndexed, processing, indexed, failed }

NoteRagStatus noteRagStatusFromString(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'processing':
    case 'uploading':
      return NoteRagStatus.processing;
    case 'indexed':
    case 'ready':
      return NoteRagStatus.indexed;
    case 'failed':
      return NoteRagStatus.failed;
    default:
      return NoteRagStatus.notIndexed;
  }
}

String noteRagStatusToString(NoteRagStatus status) {
  switch (status) {
    case NoteRagStatus.notIndexed:
      return 'notIndexed';
    case NoteRagStatus.processing:
      return 'processing';
    case NoteRagStatus.indexed:
      return 'indexed';
    case NoteRagStatus.failed:
      return 'failed';
  }
}

String noteRagStatusLabel(NoteRagStatus status) {
  switch (status) {
    case NoteRagStatus.notIndexed:
      return 'Not Indexed';
    case NoteRagStatus.processing:
      return 'Processing';
    case NoteRagStatus.indexed:
      return 'Indexed';
    case NoteRagStatus.failed:
      return 'Failed';
  }
}

/// Admin Notes form: RAG is independent of PDF upload/viewer.
String noteRagStatusAdminLabel(NoteRagStatus status) {
  switch (status) {
    case NoteRagStatus.notIndexed:
      return 'Pending';
    case NoteRagStatus.processing:
      return 'Processing';
    case NoteRagStatus.indexed:
      return 'Indexed';
    case NoteRagStatus.failed:
      return 'Failed';
  }
}

/// Content-type tag attached to RAG sources created from a notes PDF.
const String kNotesPdfContentType = 'notes_pdf';
const String kFlashcardContentType = 'flashcard';
const String kSmartTrickContentType = 'smart_trick';
const String kCurrentAffairsContentType = 'current_affairs';
const String kAiLessonContentType = 'ai_lesson';
const String kPyqContentType = 'pyq';
const String kSyllabusContentType = 'syllabus';
const String kStudentPerformanceContentType = 'student_performance';

/// Future video pipeline placeholder. Not generated in Part 3.
const String kVideoStatusNone = 'none';

/// Snapshot of how much existing content is linked to one topic id.
class TopicContentCounts {
  const TopicContentCounts({
    this.notes = 0,
    this.pyqs = 0,
    this.mcqs = 0,
    this.tests = 0,
    this.flashcards = 0,
    this.smartTricks = 0,
    this.currentAffairs = 0,
    this.videos = 0,
    this.aiLessons = 0,
  });

  final int notes;
  final int pyqs;
  final int mcqs;
  final int tests;
  final int flashcards;
  final int smartTricks;
  final int currentAffairs;
  final int videos;
  final int aiLessons;

  static const TopicContentCounts empty = TopicContentCounts();

  factory TopicContentCounts.fromMap(Map<String, dynamic> map) {
    return TopicContentCounts(
      notes: asInt(map['notes']),
      pyqs: asInt(map['pyqs']),
      mcqs: asInt(map['mcqs']),
      tests: asInt(map['tests']),
      flashcards: asInt(map['flashcards']),
      smartTricks: asInt(map['smartTricks']),
      currentAffairs: asInt(map['currentAffairs']),
      videos: asInt(map['videos']),
      aiLessons: asInt(map['aiLessons']),
    );
  }

  String get compactLabel {
    return 'Notes $notes · PYQs $pyqs · MCQs $mcqs · Tests $tests · '
        'Flashcards $flashcards · Tricks $smartTricks · '
        'CA $currentAffairs · Videos $videos · AI $aiLessons';
  }
}
