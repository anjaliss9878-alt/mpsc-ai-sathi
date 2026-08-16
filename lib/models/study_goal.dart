/// Today's study goal for a student, stored at
/// `students/{uid}/dailyGoals/{yyyy-MM-dd}`.
class StudyGoal {
  const StudyGoal({
    required this.dateKey,
    required this.notesDone,
    required this.mcqsDone,
    required this.revisionDone,
    required this.testDone,
    this.lastSessionType = '',
    this.lastSessionTitle = '',
    this.updatedAt,
  });

  /// Local calendar day as `yyyy-MM-dd` (midnight reset key).
  final String dateKey;
  final bool notesDone;
  final bool mcqsDone;
  final bool revisionDone;
  final bool testDone;
  final String lastSessionType;
  final String lastSessionTitle;
  final DateTime? updatedAt;

  int get completedCount =>
      (notesDone ? 1 : 0) +
      (mcqsDone ? 1 : 0) +
      (revisionDone ? 1 : 0) +
      (testDone ? 1 : 0);

  int get totalCount => 4;

  double get progress => completedCount / totalCount;

  bool get isComplete => completedCount == totalCount;

  StudyGoal copyWith({
    bool? notesDone,
    bool? mcqsDone,
    bool? revisionDone,
    bool? testDone,
    String? lastSessionType,
    String? lastSessionTitle,
    DateTime? updatedAt,
  }) {
    return StudyGoal(
      dateKey: dateKey,
      notesDone: notesDone ?? this.notesDone,
      mcqsDone: mcqsDone ?? this.mcqsDone,
      revisionDone: revisionDone ?? this.revisionDone,
      testDone: testDone ?? this.testDone,
      lastSessionType: lastSessionType ?? this.lastSessionType,
      lastSessionTitle: lastSessionTitle ?? this.lastSessionTitle,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'dateKey': dateKey,
        'notesDone': notesDone,
        'mcqsDone': mcqsDone,
        'revisionDone': revisionDone,
        'testDone': testDone,
        'lastSessionType': lastSessionType,
        'lastSessionTitle': lastSessionTitle,
        'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
      };

  factory StudyGoal.fromMap(Map<String, dynamic> map, String dateKey) {
    return StudyGoal(
      dateKey: map['dateKey'] as String? ?? dateKey,
      notesDone: map['notesDone'] as bool? ?? false,
      mcqsDone: map['mcqsDone'] as bool? ?? false,
      revisionDone: map['revisionDone'] as bool? ?? false,
      testDone: map['testDone'] as bool? ?? false,
      lastSessionType: map['lastSessionType'] as String? ?? '',
      lastSessionTitle: map['lastSessionTitle'] as String? ?? '',
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? ''),
    );
  }

  factory StudyGoal.emptyForToday() => StudyGoal(
        dateKey: todayKey(),
        notesDone: false,
        mcqsDone: false,
        revisionDone: false,
        testDone: false,
      );

  static String todayKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}
