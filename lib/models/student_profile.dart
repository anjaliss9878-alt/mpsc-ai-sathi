import 'package:mpsc_combine_ai/utils/json_list.dart';

/// A student's profile, stored in Firestore under `students/{uid}`.
class StudentProfile {
  const StudentProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.mobile,
    required this.targetExam,
    this.isBlocked = false,
    this.isPremium = true,
    this.assignedSubjectIds = const [],
  });

  final String uid;
  final String name;
  final String email;
  final String mobile;
  final String targetExam;

  /// Set by an admin from Student Management — a blocked student is signed
  /// out immediately and cannot sign back in until unblocked.
  final bool isBlocked;
  final bool isPremium;

  /// Subjects/courses an admin has explicitly assigned to this student.
  /// Empty means "no restriction" — every student sees every subject by
  /// default, exactly as before this field existed.
  final List<String> assignedSubjectIds;

  factory StudentProfile.fromMap(Map<String, dynamic> map, String uid) {
    return StudentProfile(
      uid: uid,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      mobile: map['mobile'] as String? ?? '',
      targetExam: map['targetExam'] as String? ?? '',
      isBlocked: map['isBlocked'] as bool? ?? false,
      isPremium: map['isPremium'] as bool? ?? true,
      assignedSubjectIds: asStringList(map['assignedSubjectIds']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'mobile': mobile,
      'targetExam': targetExam,
      'isBlocked': isBlocked,
      'isPremium': isPremium,
      'assignedSubjectIds': assignedSubjectIds,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  StudentProfile copyWith({
    String? name,
    String? mobile,
    String? targetExam,
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
      isBlocked: isBlocked ?? this.isBlocked,
      isPremium: isPremium ?? this.isPremium,
      assignedSubjectIds: assignedSubjectIds ?? this.assignedSubjectIds,
    );
  }
}
