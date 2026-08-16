/// One attendance record — a student marking themselves present for a live
/// class — stored in Firestore at `liveClassAttendance/{id}`.
///
/// Kept as a flat top-level collection (rather than a subcollection under
/// `liveClasses`) so both "attendance for this class" (Admin) and "my
/// attendance across all classes" (student) are simple single-field-equality
/// queries, consistent with every other collection in this app.
class LiveClassAttendanceItem {
  const LiveClassAttendanceItem({
    required this.id,
    required this.liveClassId,
    required this.liveClassTitle,
    required this.uid,
    required this.studentName,
    required this.studentEmail,
    required this.markedAt,
  });

  final String id;
  final String liveClassId;

  /// Denormalized so the attendance list never needs a second read per row.
  final String liveClassTitle;
  final String uid;
  final String studentName;
  final String studentEmail;
  final DateTime markedAt;

  factory LiveClassAttendanceItem.fromMap(Map<String, dynamic> map, String id) {
    return LiveClassAttendanceItem(
      id: id,
      liveClassId: map['liveClassId'] as String? ?? '',
      liveClassTitle: map['liveClassTitle'] as String? ?? '',
      uid: map['uid'] as String? ?? '',
      studentName: map['studentName'] as String? ?? '',
      studentEmail: map['studentEmail'] as String? ?? '',
      markedAt: DateTime.tryParse(map['markedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'liveClassId': liveClassId,
      'liveClassTitle': liveClassTitle,
      'uid': uid,
      'studentName': studentName,
      'studentEmail': studentEmail,
      'markedAt': markedAt.toIso8601String(),
    };
  }
}
