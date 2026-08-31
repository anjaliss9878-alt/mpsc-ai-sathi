import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';
import 'package:mpsc_combine_ai/services/ai_weakness_tracker.dart';
import 'package:mpsc_combine_ai/services/profile_repository.dart';
import 'package:mpsc_combine_ai/services/syllabus_progress_tracker.dart';

class StudentRagAccessException implements Exception {
  const StudentRagAccessException(
    this.message, [
    this.code = 'student_rag_forbidden',
  ]);

  final String message;
  final String code;

  @override
  String toString() => message;
}

/// In-memory personalization snapshot. Never written to `ragChunks`.
class StudentRagContext {
  const StudentRagContext({
    required this.uid,
    this.examId = kDefaultExamId,
    this.targetExam = '',
    this.performance = const [],
    this.weakTopics = const [],
  });

  final String uid;
  final String examId;
  final String targetExam;
  final List<StudentPerformanceRecord> performance;
  final List<WeakTopicSignal> weakTopics;

  bool get hasWeakTopics => weakTopics.isNotEmpty;

  WeakTopicSignal? matchWeakTopic({
    String question = '',
    String subjectId = '',
    String chapterId = '',
    String topicId = '',
  }) {
    if (weakTopics.isEmpty) return null;
    if (chapterId.isNotEmpty) {
      for (final w in weakTopics) {
        if (w.chapterId == chapterId) return w;
      }
    }
    if (topicId.isNotEmpty) {
      for (final w in weakTopics) {
        if (w.chapterId == topicId) return w;
      }
    }
    if (subjectId.isNotEmpty) {
      for (final w in weakTopics) {
        if (w.subjectId == subjectId) return w;
      }
    }
    final q = question.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final w in weakTopics) {
      final label = w.label.trim().toLowerCase();
      final subject = w.subjectTitle.trim().toLowerCase();
      if (label.isNotEmpty && q.contains(label)) return w;
      if (subject.isNotEmpty && q.contains(subject)) return w;
    }
    return null;
  }
}

List<StudentPerformanceRecord> studentPerformanceRecordsFromWeakness(
  WeaknessSnapshot snapshot, {
  String examId = '',
}) {
  return [
    for (final signal in snapshot.signals)
      StudentPerformanceRecord(
        label: signal.label,
        examId: examId,
        subjectId: signal.subjectId,
        chapterId: signal.chapterId,
        topicId: signal.chapterId,
        scorePercent: signal.scorePercent,
        source: signal.source,
        status: signal.isWeak ? 'weak' : (signal.isStrong ? 'strong' : ''),
      ),
  ];
}

/// Loads profile + syllabus + weakness (tests / MCQs / classroom) for ONE uid.
class StudentRagContextService {
  StudentRagContextService({
    ProfileRepository? profiles,
    SyllabusProgressTracker? syllabus,
    AiWeaknessTracker? weakness,
  })  : _profilesOverride = profiles,
        _syllabusOverride = syllabus,
        _weaknessOverride = weakness;

  final ProfileRepository? _profilesOverride;
  final SyllabusProgressTracker? _syllabusOverride;
  final AiWeaknessTracker? _weaknessOverride;

  ProfileRepository get _profiles => _profilesOverride ?? profileRepository;
  SyllabusProgressTracker get _syllabus =>
      _syllabusOverride ?? syllabusProgressTracker;
  AiWeaknessTracker get _weakness => _weaknessOverride ?? aiWeaknessTracker;

  Future<StudentRagContext> load({
    required String uid,
    required String requesterUid,
  }) async {
    if (uid.trim().isEmpty || requesterUid.trim().isEmpty) {
      throw const StudentRagAccessException(
        'Student personalization requires a signed-in student.',
      );
    }
    if (uid != requesterUid) {
      throw const StudentRagAccessException(
        'Students may only use their own performance context.',
      );
    }

    StudentProfile? profile;
    try {
      profile = await _profiles.getProfile(uid);
    } catch (_) {
      profile = null;
    }

    final syllabus = await _syllabus.load(uid);
    final weakness = await _weakness.load(uid, syllabus: syllabus);
    final examId = kDefaultExamId;

    return StudentRagContext(
      uid: uid,
      examId: examId,
      targetExam: profile?.targetExam ?? '',
      performance: studentPerformanceRecordsFromWeakness(
        weakness,
        examId: examId,
      ),
      weakTopics: weakness.weakTopics,
    );
  }
}

final StudentRagContextService studentRagContextService =
    StudentRagContextService();
