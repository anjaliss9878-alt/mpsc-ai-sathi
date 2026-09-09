import 'package:mpsc_combine_ai/utils/json_list.dart';

/// A student's profile, stored in Firestore under `students/{uid}`.
class StudentProfile {
  const StudentProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.mobile,
    required this.targetExam,
    this.examDate = '',
    this.dailyStudyHours = 4,
    this.preparationDurationDays = 0,
    this.studyMode = '',
    this.preparationStage = '',
    this.preferredLanguage = '',
    this.onboardingCompleted = true,
    this.diagnosticCompleted = true,
    this.createdAt = '',
    this.isBlocked = false,
    this.isPremium = true,
    this.assignedSubjectIds = const [],
  });

  final String uid;
  final String name;
  final String email;
  final String mobile;
  final String targetExam;

  /// Target exam calendar day as `yyyy-MM-dd`. Empty until the student sets it
  /// in the daily planner.
  final String examDate;

  /// Hours the student can study per day. Used by the personalized planner.
  final double dailyStudyHours;

  /// Used when [examDate] is empty. 0 means the planner default (90 days).
  final int preparationDurationDays;

  /// `part_time` or `full_time`.
  final String studyMode;

  final String preparationStage;
  final String preferredLanguage;

  /// Explicit onboarding flag. Missing on legacy profiles is treated as
  /// completed so existing students are not forced through the new flow.
  final bool onboardingCompleted;

  /// Explicit diagnostic flag. Missing on legacy profiles is treated as
  /// completed. New onboarding writes `false` until the diagnostic is done.
  final bool diagnosticCompleted;

  final String createdAt;

  /// Set by an admin from Student Management — a blocked student is signed
  /// out immediately and cannot sign back in until unblocked.
  final bool isBlocked;
  final bool isPremium;

  /// Subjects/courses an admin has explicitly assigned to this student.
  /// Empty means "no restriction" — every student sees every subject by
  /// default, exactly as before this field existed.
  final List<String> assignedSubjectIds;

  bool get needsOnboarding => !onboardingCompleted;

  bool get needsDiagnostic => onboardingCompleted && !diagnosticCompleted;

  factory StudentProfile.fromMap(Map<String, dynamic> map, String uid) {
    final hasOnboardingFlag = map.containsKey('onboardingCompleted');
    final hasDiagnosticFlag = map.containsKey('diagnosticCompleted');
    return StudentProfile(
      uid: uid,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      mobile: map['mobile'] as String? ?? '',
      targetExam: map['targetExam'] as String? ?? '',
      examDate: map['examDate'] as String? ?? '',
      dailyStudyHours: (map['dailyStudyHours'] as num?)?.toDouble() ?? 4,
      preparationDurationDays:
          (map['preparationDurationDays'] as num?)?.toInt() ?? 0,
      studyMode: map['studyMode'] as String? ?? '',
      preparationStage: map['preparationStage'] as String? ?? '',
      preferredLanguage: map['preferredLanguage'] as String? ?? '',
      onboardingCompleted: hasOnboardingFlag
          ? map['onboardingCompleted'] == true
          : true,
      diagnosticCompleted: hasDiagnosticFlag
          ? map['diagnosticCompleted'] == true
          : true,
      createdAt: map['createdAt'] as String? ?? '',
      isBlocked: map['isBlocked'] as bool? ?? false,
      isPremium: map['isPremium'] as bool? ?? true,
      assignedSubjectIds: asStringList(map['assignedSubjectIds']),
    );
  }

  Map<String, dynamic> toMap() {
    final now = DateTime.now().toIso8601String();
    return {
      'name': name,
      'email': email,
      'mobile': mobile,
      'targetExam': targetExam,
      'examDate': examDate,
      'dailyStudyHours': dailyStudyHours,
      'preparationDurationDays': preparationDurationDays,
      'studyMode': studyMode,
      'preparationStage': preparationStage,
      'preferredLanguage': preferredLanguage,
      'onboardingCompleted': onboardingCompleted,
      'diagnosticCompleted': diagnosticCompleted,
      'createdAt': createdAt.isNotEmpty ? createdAt : now,
      'isBlocked': isBlocked,
      'isPremium': isPremium,
      'assignedSubjectIds': assignedSubjectIds,
      'updatedAt': now,
    };
  }

  StudentProfile copyWith({
    String? name,
    String? mobile,
    String? targetExam,
    String? examDate,
    double? dailyStudyHours,
    int? preparationDurationDays,
    String? studyMode,
    String? preparationStage,
    String? preferredLanguage,
    bool? onboardingCompleted,
    bool? diagnosticCompleted,
    String? createdAt,
    bool? isBlocked,
    bool? isPremium,
    List<String>? assignedSubjectIds,
  }) {
    return StudentProfile(
      uid: uid,
      name: name ?? this.name,
      email: email,
      mobile: mobile ?? this.mobile,
      targetExam: targetExam ?? this.targetExam,
      examDate: examDate ?? this.examDate,
      dailyStudyHours: dailyStudyHours ?? this.dailyStudyHours,
      preparationDurationDays:
          preparationDurationDays ?? this.preparationDurationDays,
      studyMode: studyMode ?? this.studyMode,
      preparationStage: preparationStage ?? this.preparationStage,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      diagnosticCompleted: diagnosticCompleted ?? this.diagnosticCompleted,
      createdAt: createdAt ?? this.createdAt,
      isBlocked: isBlocked ?? this.isBlocked,
      isPremium: isPremium ?? this.isPremium,
      assignedSubjectIds: assignedSubjectIds ?? this.assignedSubjectIds,
    );
  }
}
