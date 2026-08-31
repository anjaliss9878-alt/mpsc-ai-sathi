import 'dart:async';

import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/models/syllabus_topic_record.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/lesson_progress_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';

export 'package:mpsc_combine_ai/models/syllabus_topic_record.dart'
    show
        SyllabusTopicStatus,
        syllabusTopicStatusFromString,
        syllabusTopicStatusToString;

class SyllabusTopicProgress {
  const SyllabusTopicProgress({
    required this.subject,
    required this.chapter,
    required this.status,
    this.classroomFraction = 0,
    this.quizAccuracy,
    this.studyMinutes = 0,
    this.revisionCount = 0,
    this.completedAt,
    this.lastStudiedAt,
    this.statusSource = '',
  });

  final SubjectItem subject;
  final ChapterItem chapter;
  final SyllabusTopicStatus status;
  final double classroomFraction;
  final double? quizAccuracy;
  final int studyMinutes;
  final int revisionCount;
  final DateTime? completedAt;
  final DateTime? lastStudiedAt;

  /// `manual` | `classroom` | `certificate` | `planner` | empty (inferred).
  final String statusSource;

  String get subjectId => subject.id;
  String get subjectTitle => subject.title;
  String get chapterId => chapter.id;
  String get chapterTitle => chapter.title;

  bool get isCompleted => status == SyllabusTopicStatus.completed;
  bool get isIncomplete => !isCompleted;
}

class SyllabusSubjectProgress {
  const SyllabusSubjectProgress({
    required this.subject,
    required this.topics,
  });

  final SubjectItem subject;
  final List<SyllabusTopicProgress> topics;

  int get totalTopics => topics.length;
  int get completedTopics => topics.where((t) => t.isCompleted).length;
  int get inProgressTopics =>
      topics.where((t) => t.status == SyllabusTopicStatus.inProgress).length;
  int get notStartedTopics =>
      topics.where((t) => t.status == SyllabusTopicStatus.pending).length;

  double get percent =>
      syllabusCompletionPercent(completed: completedTopics, total: totalTopics);

  String get statusLabel {
    if (totalTopics == 0) return 'रिक्त';
    if (completedTopics == totalTopics) return 'पूर्ण';
    if (completedTopics > 0 || inProgressTopics > 0) return 'सुरू आहे';
    return 'सुरू नाही';
  }
}

class SyllabusProgressSnapshot {
  const SyllabusProgressSnapshot({
    required this.topics,
  });

  final List<SyllabusTopicProgress> topics;

  List<SyllabusTopicProgress> get pending =>
      topics.where((t) => t.status == SyllabusTopicStatus.pending).toList();

  List<SyllabusTopicProgress> get inProgress =>
      topics.where((t) => t.status == SyllabusTopicStatus.inProgress).toList();

  List<SyllabusTopicProgress> get completed =>
      topics.where((t) => t.status == SyllabusTopicStatus.completed).toList();

  List<SyllabusTopicProgress> get incomplete =>
      topics.where((t) => t.isIncomplete).toList();

  int get totalTopics => topics.length;
  int get completedTopics => completed.length;

  /// Spec: completed topics / total topics × 100.
  double get overallPercent =>
      syllabusCompletionPercent(completed: completedTopics, total: totalTopics);

  double get overallFraction {
    if (topics.isEmpty) return 0;
    return (completedTopics / topics.length).clamp(0.0, 1.0);
  }

  bool get hasSyllabus => topics.isNotEmpty;

  SyllabusProgressSnapshot forSubjectIds(List<String> subjectIds) {
    if (subjectIds.isEmpty) return this;
    final allowed = subjectIds.toSet();
    return SyllabusProgressSnapshot(
      topics: topics.where((t) => allowed.contains(t.subjectId)).toList(),
    );
  }

  /// Future AI Weakness Tracker feed — do not implement that feature here.
  SyllabusWeaknessInputs get weaknessInputs => SyllabusWeaknessInputs(
        completedTopics: completed,
        incompleteTopics: incomplete,
      );

  List<SyllabusSubjectProgress> get subjects {
    final byId = <String, List<SyllabusTopicProgress>>{};
    final order = <String, SubjectItem>{};
    for (final topic in topics) {
      byId.putIfAbsent(topic.subjectId, () => []).add(topic);
      order.putIfAbsent(topic.subjectId, () => topic.subject);
    }
    final subjects = order.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (final s in subjects)
        SyllabusSubjectProgress(subject: s, topics: byId[s.id] ?? const []),
    ];
  }

  SyllabusSubjectProgress? subjectById(String subjectId) {
    for (final s in subjects) {
      if (s.subject.id == subjectId) return s;
    }
    return null;
  }
}

/// Pure percent helper — completed / total × 100. Never uses hardcoded values.
double syllabusCompletionPercent({required int completed, required int total}) {
  if (total <= 0) return 0;
  return (completed / total) * 100;
}

double syllabusTopicPercent(SyllabusTopicStatus status) {
  switch (status) {
    case SyllabusTopicStatus.completed:
      return 100;
    case SyllabusTopicStatus.inProgress:
      return 0;
    case SyllabusTopicStatus.pending:
      return 0;
  }
}

/// Clean read-model the future Weakness Tracker can consume.
class SyllabusWeaknessInputs {
  const SyllabusWeaknessInputs({
    required this.completedTopics,
    required this.incompleteTopics,
  });

  final List<SyllabusTopicProgress> completedTopics;
  final List<SyllabusTopicProgress> incompleteTopics;

  int get totalStudyMinutes => [
        ...completedTopics,
        ...incompleteTopics,
      ].fold<int>(0, (s, t) => s + t.studyMinutes);

  int get totalRevisions => [
        ...completedTopics,
        ...incompleteTopics,
      ].fold<int>(0, (s, t) => s + t.revisionCount);
}

/// Reads published subjects/chapters plus the student's syllabusProgress,
/// classroom, and certificates. Daily Planner depends only on [load].
abstract class SyllabusProgressTracker {
  Future<SyllabusProgressSnapshot> load(String uid);

  Stream<SyllabusProgressSnapshot> watch(String uid) async* {
    yield await load(uid);
  }

  Future<void> setTopicStatus({
    required String uid,
    required SyllabusTopicProgress topic,
    required SyllabusTopicStatus status,
    String source = 'manual',
    int extraStudyMinutes = 0,
    String? plannerDateKey,
  }) async {}
}

class FirestoreSyllabusProgressTracker implements SyllabusProgressTracker {
  FirestoreSyllabusProgressTracker({
    NotesRepository? notes,
    LessonProgressRepository? classroom,
    StudentProgressRepository? progress,
  })  : _notes = notes ?? notesRepository,
        _classroom = classroom ?? lessonProgressRepository,
        _progress = progress ?? studentProgressRepository;

  final NotesRepository _notes;
  final LessonProgressRepository _classroom;
  final StudentProgressRepository _progress;

  @override
  Future<SyllabusProgressSnapshot> load(String uid) async {
    final subjects = (await _notes.getSubjectsOnce())
        .where((s) => s.published)
        .toList();
    final records = await _progress.getSyllabusRecords(uid);
    return _assemble(uid: uid, subjects: subjects, records: records);
  }

  @override
  Stream<SyllabusProgressSnapshot> watch(String uid) {
    return Stream.multi((controller) {
      List<SubjectItem>? subjects;
      var records = <SyllabusTopicRecord>[];
      var classroom = <ClassroomProgress>[];
      var certified = <String>{};

      Future<void> emit() async {
        if (subjects == null) return;
        try {
          controller.add(
            await _assemble(
              uid: uid,
              subjects: subjects!,
              records: records,
              classroom: classroom,
              certifiedChapters: certified,
              classroomLoaded: true,
            ),
          );
        } catch (e, st) {
          controller.addError(e, st);
        }
      }

      final subSubjects = _notes.watchPublishedSubjects().listen(
        (list) {
          subjects = list;
          emit();
        },
        onError: controller.addError,
      );
      final subRecords = _progress.watchSyllabusRecords(uid).listen(
        (list) {
          records = list;
          emit();
        },
        onError: controller.addError,
      );
      final subClass = _classroom.watchAll(uid, limit: 400).listen(
        (list) {
          classroom = list;
          emit();
        },
        onError: controller.addError,
      );
      final subCert = _progress.watchCertificates(uid).listen(
        (list) {
          certified = list
              .where((c) => c.type == 'chapter' && c.refId.isNotEmpty)
              .map((c) => c.refId)
              .toSet();
          emit();
        },
        onError: controller.addError,
      );

      controller.onCancel = () async {
        await subSubjects.cancel();
        await subRecords.cancel();
        await subClass.cancel();
        await subCert.cancel();
      };
    });
  }

  @override
  Future<void> setTopicStatus({
    required String uid,
    required SyllabusTopicProgress topic,
    required SyllabusTopicStatus status,
    String source = 'manual',
    int extraStudyMinutes = 0,
    String? plannerDateKey,
  }) async {
    await _progress.upsertSyllabusRecord(
      uid: uid,
      chapterId: topic.chapterId,
      subjectId: topic.subjectId,
      status: status,
      source: source,
      extraStudyMinutes: extraStudyMinutes,
    );
    if (status == SyllabusTopicStatus.completed) {
      await _progress.ensureChapterCertificate(
        uid: uid,
        chapterId: topic.chapterId,
        title: topic.chapterTitle,
        subtitle: topic.subjectTitle,
      );
      await _progress.completeOpenPlannerTasksForChapter(
        uid: uid,
        chapterId: topic.chapterId,
        dateKey: plannerDateKey,
      );
      await _progress.markGoalTask(
        uid: uid,
        task: 'notes',
        done: true,
        sessionType: 'syllabus',
        sessionTitle: topic.chapterTitle,
      );
      await _progress.upsertContinueSession(
        uid: uid,
        id: 'syllabus_${topic.chapterId}',
        type: 'notes',
        title: topic.chapterTitle,
        subtitle: topic.subjectTitle,
        progress: 1,
        payload: {
          'chapterId': topic.chapterId,
          'subjectId': topic.subjectId,
        },
      );
    } else {
      await _progress.upsertContinueSession(
        uid: uid,
        id: 'syllabus_${topic.chapterId}',
        type: 'notes',
        title: topic.chapterTitle,
        subtitle: topic.subjectTitle,
        progress: status == SyllabusTopicStatus.inProgress ? 0.5 : 0,
        payload: {
          'chapterId': topic.chapterId,
          'subjectId': topic.subjectId,
        },
      );
    }
  }

  Future<SyllabusProgressSnapshot> _assemble({
    required String uid,
    required List<SubjectItem> subjects,
    required List<SyllabusTopicRecord> records,
    List<ClassroomProgress>? classroom,
    Set<String>? certifiedChapters,
    bool classroomLoaded = false,
  }) async {
    if (subjects.isEmpty) {
      return const SyllabusProgressSnapshot(topics: []);
    }

    var byChapterClass = <String, ClassroomProgress>{};
    if (classroomLoaded) {
      for (final p in classroom ?? const <ClassroomProgress>[]) {
        if (p.chapterId.isNotEmpty) byChapterClass[p.chapterId] = p;
      }
    } else {
      final loaded = await _classroom.getAllOnce(uid);
      for (final p in loaded) {
        if (p.chapterId.isNotEmpty) byChapterClass[p.chapterId] = p;
      }
    }

    Set<String> certified;
    if (certifiedChapters != null) {
      certified = certifiedChapters;
    } else {
      final certs = await _progress.getCertificates(uid);
      certified = certs
          .where((c) => c.type == 'chapter' && c.refId.isNotEmpty)
          .map((c) => c.refId)
          .toSet();
    }

    final byRecord = <String, SyllabusTopicRecord>{
      for (final r in records)
        if (r.chapterId.isNotEmpty) r.chapterId: r,
    };

    final topics = <SyllabusTopicProgress>[];
    for (final subject in subjects) {
      final chapters = (await _notes.getChaptersOnce(subject.id))
          .where((c) => c.published)
          .toList();
      for (final chapter in chapters) {
        final prog = byChapterClass[chapter.id];
        final record = byRecord[chapter.id];
        final fraction = prog?.fraction ?? 0;
        final inferredCompleted =
            certified.contains(chapter.id) || (prog?.completed ?? false) || fraction >= 0.95;
        SyllabusTopicStatus inferred;
        String inferredSource = '';
        if (inferredCompleted) {
          inferred = SyllabusTopicStatus.completed;
          inferredSource = certified.contains(chapter.id) ? 'certificate' : 'classroom';
        } else if (prog != null && (fraction > 0 || prog.scenesCompleted > 0)) {
          inferred = SyllabusTopicStatus.inProgress;
          inferredSource = 'classroom';
        } else {
          inferred = SyllabusTopicStatus.pending;
        }

        final status = record?.status ?? inferred;
        final source = record != null ? 'manual' : inferredSource;
        double? quizAccuracy;
        if (prog != null && prog.quizTotal > 0) {
          quizAccuracy = prog.quizScore / prog.quizTotal;
        }
        topics.add(
          SyllabusTopicProgress(
            subject: subject,
            chapter: chapter,
            status: status,
            classroomFraction: fraction,
            quizAccuracy: quizAccuracy,
            studyMinutes: record?.studyMinutes ?? 0,
            revisionCount: record?.revisionCount ?? 0,
            completedAt: record?.completedAt,
            lastStudiedAt: record?.lastStudiedAt,
            statusSource: source,
          ),
        );
      }
    }
    return SyllabusProgressSnapshot(topics: topics);
  }
}

final SyllabusProgressTracker syllabusProgressTracker =
    FirestoreSyllabusProgressTracker();
