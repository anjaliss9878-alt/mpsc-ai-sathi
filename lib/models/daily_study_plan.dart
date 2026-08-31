import 'package:mpsc_combine_ai/models/study_goal.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

/// One scheduled block inside a student's daily plan.
///
/// Stored inside `students/{uid}/studyPlans/{yyyy-MM-dd}` (same collection
/// as the existing weekly [StudyPlan] docs, distinguished by [kind]).
enum DailyPlanTaskType { study, revision, practiceMcq, pyq, testQuiz }

enum DailyPlanTaskStatus { pending, completed, skipped, rescheduled }

class DailyPlanTask {
  const DailyPlanTask({
    required this.id,
    required this.type,
    required this.subject,
    required this.topic,
    required this.durationMinutes,
    this.subjectId = '',
    this.chapterId = '',
    this.studyMinutes = 0,
    this.revisionMinutes = 0,
    this.practiceMinutes = 0,
    this.status = DailyPlanTaskStatus.pending,
    this.reason = '',
    this.rescheduledToDateKey = '',
    this.priority = 0,
  });

  final String id;
  final DailyPlanTaskType type;
  final String subject;
  final String topic;
  final String subjectId;
  final String chapterId;

  /// Minutes the student should spend on this block.
  final int durationMinutes;

  /// Split of this block (study / revision / MCQ practice). Unused kinds stay 0.
  final int studyMinutes;
  final int revisionMinutes;
  final int practiceMinutes;

  final DailyPlanTaskStatus status;
  final String reason;
  final String rescheduledToDateKey;

  /// Higher values run first. Weak-topic work is scored above routine study.
  final int priority;

  bool get isOpen => status == DailyPlanTaskStatus.pending;
  bool get isDone => status == DailyPlanTaskStatus.completed;

  String get typeLabel => switch (type) {
        DailyPlanTaskType.study => 'Study',
        DailyPlanTaskType.revision => 'Revision',
        DailyPlanTaskType.practiceMcq => 'Targeted MCQs',
        DailyPlanTaskType.pyq => 'Related PYQs',
        DailyPlanTaskType.testQuiz => 'Test / Quiz',
      };

  String get priorityLabel {
    if (priority >= 40) return 'High';
    if (priority >= 20) return 'Medium';
    return 'Normal';
  }

  String get goalTaskKey => switch (type) {
        DailyPlanTaskType.study => 'notes',
        DailyPlanTaskType.revision => 'revision',
        DailyPlanTaskType.practiceMcq => 'mcqs',
        DailyPlanTaskType.pyq => 'mcqs',
        DailyPlanTaskType.testQuiz => 'test',
      };

  DailyPlanTask copyWith({
    DailyPlanTaskStatus? status,
    String? rescheduledToDateKey,
    int? priority,
  }) {
    return DailyPlanTask(
      id: id,
      type: type,
      subject: subject,
      topic: topic,
      durationMinutes: durationMinutes,
      subjectId: subjectId,
      chapterId: chapterId,
      studyMinutes: studyMinutes,
      revisionMinutes: revisionMinutes,
      practiceMinutes: practiceMinutes,
      status: status ?? this.status,
      reason: reason,
      rescheduledToDateKey: rescheduledToDateKey ?? this.rescheduledToDateKey,
      priority: priority ?? this.priority,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'subject': subject,
        'topic': topic,
        'subjectId': subjectId,
        'chapterId': chapterId,
        'durationMinutes': durationMinutes,
        'studyMinutes': studyMinutes,
        'revisionMinutes': revisionMinutes,
        'practiceMinutes': practiceMinutes,
        'status': status.name,
        'reason': reason,
        'rescheduledToDateKey': rescheduledToDateKey,
        'priority': priority,
      };

  factory DailyPlanTask.fromMap(Map<String, dynamic> map, {String? fallbackId}) {
    return DailyPlanTask(
      id: map['id'] as String? ?? fallbackId ?? '',
      type: dailyPlanTaskTypeFrom(map['type'] as String?),
      subject: map['subject'] as String? ?? '',
      topic: map['topic'] as String? ?? '',
      subjectId: map['subjectId'] as String? ?? '',
      chapterId: map['chapterId'] as String? ?? '',
      durationMinutes: asInt(map['durationMinutes']),
      studyMinutes: asInt(map['studyMinutes']),
      revisionMinutes: asInt(map['revisionMinutes']),
      practiceMinutes: asInt(map['practiceMinutes']),
      status: dailyPlanTaskStatusFrom(map['status'] as String?),
      reason: map['reason'] as String? ?? '',
      rescheduledToDateKey: map['rescheduledToDateKey'] as String? ?? '',
      priority: asInt(map['priority']),
    );
  }
}

DailyPlanTaskType dailyPlanTaskTypeFrom(String? raw) {
  switch ((raw ?? '').trim()) {
    case 'revision':
      return DailyPlanTaskType.revision;
    case 'practiceMcq':
    case 'mcq':
    case 'practice':
      return DailyPlanTaskType.practiceMcq;
    case 'pyq':
      return DailyPlanTaskType.pyq;
    case 'testQuiz':
    case 'test':
    case 'quiz':
      return DailyPlanTaskType.testQuiz;
    default:
      return DailyPlanTaskType.study;
  }
}

DailyPlanTaskStatus dailyPlanTaskStatusFrom(String? raw) {
  switch ((raw ?? '').trim()) {
    case 'completed':
      return DailyPlanTaskStatus.completed;
    case 'skipped':
      return DailyPlanTaskStatus.skipped;
    case 'rescheduled':
      return DailyPlanTaskStatus.rescheduled;
    default:
      return DailyPlanTaskStatus.pending;
  }
}

/// Personalized day plan. Document id is [dateKey] (`yyyy-MM-dd`).
class DailyStudyPlan {
  const DailyStudyPlan({
    required this.dateKey,
    required this.uid,
    required this.targetExam,
    required this.dailyHours,
    required this.tasks,
    this.examDate = '',
    this.adaptationNotes = const [],
    this.generatedAt,
  });

  static const String kind = 'daily';

  final String dateKey;
  final String uid;
  final String targetExam;
  final String examDate;
  final double dailyHours;
  final List<DailyPlanTask> tasks;
  final List<String> adaptationNotes;
  final DateTime? generatedAt;

  List<DailyPlanTask> get openTasks =>
      tasks.where((t) => t.isOpen).toList(growable: false);

  List<DailyPlanTask> get completedTasks =>
      tasks.where((t) => t.isDone).toList(growable: false);

  List<DailyPlanTask> get remainingTasks {
    final list = openTasks.toList();
    list.sort((a, b) => b.priority.compareTo(a.priority));
    return list;
  }

  int get completedCount => completedTasks.length;

  int get actionableCount =>
      tasks.where((t) => t.status != DailyPlanTaskStatus.rescheduled).length;

  double get progress {
    if (actionableCount == 0) return 0;
    return completedCount / actionableCount;
  }

  int get totalStudyMinutes =>
      tasks.fold(0, (s, t) => s + t.studyMinutes);
  int get totalRevisionMinutes =>
      tasks.fold(0, (s, t) => s + t.revisionMinutes);
  int get totalPracticeMinutes =>
      tasks.fold(0, (s, t) => s + t.practiceMinutes);

  DailyStudyPlan copyWith({
    List<DailyPlanTask>? tasks,
    List<String>? adaptationNotes,
    DateTime? generatedAt,
  }) {
    return DailyStudyPlan(
      dateKey: dateKey,
      uid: uid,
      targetExam: targetExam,
      examDate: examDate,
      dailyHours: dailyHours,
      tasks: tasks ?? this.tasks,
      adaptationNotes: adaptationNotes ?? this.adaptationNotes,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }

  DailyStudyPlan withTask(DailyPlanTask updated) {
    return copyWith(
      tasks: [
        for (final t in tasks)
          if (t.id == updated.id) updated else t,
      ],
    );
  }

  Map<String, dynamic> toMap() => {
        'kind': kind,
        'dateKey': dateKey,
        'uid': uid,
        'targetExam': targetExam,
        'examDate': examDate,
        'dailyHours': dailyHours,
        'tasks': tasks.map((t) => t.toMap()).toList(),
        'adaptationNotes': adaptationNotes,
        'generatedAt': (generatedAt ?? DateTime.now()).toIso8601String(),
      };

  factory DailyStudyPlan.fromMap(Map<String, dynamic> map, String dateKey) {
    final rawTasks = asMapList(map['tasks']);
    return DailyStudyPlan(
      dateKey: map['dateKey'] as String? ?? dateKey,
      uid: map['uid'] as String? ?? '',
      targetExam: map['targetExam'] as String? ?? '',
      examDate: map['examDate'] as String? ?? '',
      dailyHours: (map['dailyHours'] as num?)?.toDouble() ?? 4,
      tasks: [
        for (var i = 0; i < rawTasks.length; i++)
          DailyPlanTask.fromMap(rawTasks[i], fallbackId: 'task_$i'),
      ],
      adaptationNotes: asStringList(map['adaptationNotes']),
      generatedAt: DateTime.tryParse(map['generatedAt'] as String? ?? ''),
    );
  }

  static String dateKeyFor([DateTime? now]) => StudyGoal.todayKey(now);

  static bool isDailyDoc(String id, [Map<String, dynamic>? data]) {
    if (data != null && (data['kind'] as String?) == kind) return true;
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(id);
  }
}

class WeeklyPlannerProgress {
  const WeeklyPlannerProgress({
    required this.completedTasks,
    required this.totalTasks,
    required this.daysWithPlan,
  });

  final int completedTasks;
  final int totalTasks;
  final int daysWithPlan;

  double get progress => totalTasks == 0 ? 0 : completedTasks / totalTasks;
}
