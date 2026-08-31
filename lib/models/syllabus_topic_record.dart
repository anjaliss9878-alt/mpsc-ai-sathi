import 'package:mpsc_combine_ai/utils/json_list.dart';

/// Completion state of one published syllabus topic (`chapters/{id}`).
enum SyllabusTopicStatus { pending, inProgress, completed }

SyllabusTopicStatus syllabusTopicStatusFromString(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'completed':
    case 'complete':
      return SyllabusTopicStatus.completed;
    case 'inprogress':
    case 'in_progress':
    case 'in-progress':
      return SyllabusTopicStatus.inProgress;
    default:
      return SyllabusTopicStatus.pending;
  }
}

String syllabusTopicStatusToString(SyllabusTopicStatus status) {
  switch (status) {
    case SyllabusTopicStatus.completed:
      return 'completed';
    case SyllabusTopicStatus.inProgress:
      return 'inProgress';
    case SyllabusTopicStatus.pending:
      return 'pending';
  }
}

/// One status-change event stored on `students/{uid}/syllabusProgress/{chapterId}`.
class SyllabusStatusEvent {
  const SyllabusStatusEvent({
    required this.status,
    required this.at,
    this.source = 'manual',
  });

  final SyllabusTopicStatus status;
  final DateTime at;
  final String source;

  Map<String, dynamic> toMap() => {
        'status': syllabusTopicStatusToString(status),
        'at': at.toIso8601String(),
        'source': source,
      };

  factory SyllabusStatusEvent.fromMap(Map<String, dynamic> map) {
    return SyllabusStatusEvent(
      status: syllabusTopicStatusFromString(map['status'] as String?),
      at: DateTime.tryParse(map['at'] as String? ?? '') ?? DateTime.now(),
      source: map['source'] as String? ?? '',
    );
  }
}

/// Student-owned progress for one published syllabus topic (`chapters/{id}`).
class SyllabusTopicRecord {
  const SyllabusTopicRecord({
    required this.chapterId,
    required this.subjectId,
    required this.status,
    this.studyMinutes = 0,
    this.revisionCount = 0,
    this.completedAt,
    this.lastStudiedAt,
    this.history = const [],
  });

  final String chapterId;
  final String subjectId;
  final SyllabusTopicStatus status;
  final int studyMinutes;
  final int revisionCount;
  final DateTime? completedAt;
  final DateTime? lastStudiedAt;
  final List<SyllabusStatusEvent> history;

  bool get isCompleted => status == SyllabusTopicStatus.completed;

  SyllabusTopicRecord copyWith({
    SyllabusTopicStatus? status,
    int? studyMinutes,
    int? revisionCount,
    DateTime? completedAt,
    DateTime? lastStudiedAt,
    List<SyllabusStatusEvent>? history,
    bool clearCompletedAt = false,
  }) {
    return SyllabusTopicRecord(
      chapterId: chapterId,
      subjectId: subjectId,
      status: status ?? this.status,
      studyMinutes: studyMinutes ?? this.studyMinutes,
      revisionCount: revisionCount ?? this.revisionCount,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      lastStudiedAt: lastStudiedAt ?? this.lastStudiedAt,
      history: history ?? this.history,
    );
  }

  Map<String, dynamic> toMap() => {
        'chapterId': chapterId,
        'subjectId': subjectId,
        'status': syllabusTopicStatusToString(status),
        'studyMinutes': studyMinutes,
        'revisionCount': revisionCount,
        'completedAt': completedAt?.toIso8601String() ?? '',
        'lastStudiedAt': lastStudiedAt?.toIso8601String() ?? '',
        'history': history.map((e) => e.toMap()).toList(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

  factory SyllabusTopicRecord.fromMap(Map<String, dynamic> map, String id) {
    final completedRaw = map['completedAt'] as String? ?? '';
    final studiedRaw = map['lastStudiedAt'] as String? ?? '';
    return SyllabusTopicRecord(
      chapterId: map['chapterId'] as String? ?? id,
      subjectId: map['subjectId'] as String? ?? '',
      status: syllabusTopicStatusFromString(map['status'] as String?),
      studyMinutes: asInt(map['studyMinutes']),
      revisionCount: asInt(map['revisionCount']),
      completedAt: DateTime.tryParse(completedRaw),
      lastStudiedAt: DateTime.tryParse(studiedRaw),
      history: asMapList(map['history']).map(SyllabusStatusEvent.fromMap).toList(),
    );
  }
}
