/// A student's profile, stored in Firestore under `students/{uid}`.
class StudentProfile {
  const StudentProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.mobile,
    required this.targetExam,
  });

  final String uid;
  final String name;
  final String email;
  final String mobile;
  final String targetExam;

  factory StudentProfile.fromMap(Map<String, dynamic> map, String uid) {
    return StudentProfile(
      uid: uid,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      mobile: map['mobile'] as String? ?? '',
      targetExam: map['targetExam'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'mobile': mobile,
      'targetExam': targetExam,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  StudentProfile copyWith({
    String? name,
    String? mobile,
    String? targetExam,
  }) {
    return StudentProfile(
      uid: uid,
      name: name ?? this.name,
      email: email,
      mobile: mobile ?? this.mobile,
      targetExam: targetExam ?? this.targetExam,
    );
  }
}
