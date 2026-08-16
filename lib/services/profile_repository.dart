import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/student_profile.dart';

/// Reads/writes [StudentProfile] documents in Firestore at
/// `students/{uid}`, keyed by the authenticated user's UID.
class ProfileRepository {
  ProfileRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String studentsCollection = 'students';

  Future<StudentProfile?> getProfile(String uid) async {
    final doc =
        await _firestore.collection(studentsCollection).doc(uid).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    return StudentProfile.fromMap(data, uid);
  }

  /// Real-time profile stream — used by [AuthGate] so an admin blocking a
  /// student takes effect immediately, even mid-session.
  Stream<StudentProfile?> watchProfile(String uid) {
    return _firestore.collection(studentsCollection).doc(uid).snapshots().map(
          (doc) {
            final data = doc.data();
            if (!doc.exists || data == null) return null;
            return StudentProfile.fromMap(data, uid);
          },
        );
  }

  /// Every student profile, live — used by Admin Panel Student Management.
  /// Search/filter/pagination are applied client-side on top of this single
  /// stream, which keeps the Admin Panel simple while student counts stay
  /// in the thousands (well within what Firestore + Flutter can hold in
  /// memory comfortably).
  Stream<List<StudentProfile>> watchAllStudents() {
    return _firestore.collection(studentsCollection).snapshots().map(
          (snap) => snap.docs
              .map((d) => StudentProfile.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  Future<void> setBlocked(String uid, bool isBlocked) async {
    await _firestore.collection(studentsCollection).doc(uid).set(
      {'isBlocked': isBlocked, 'updatedAt': DateTime.now().toIso8601String()},
      SetOptions(merge: true),
    );
  }

  Future<void> setAssignedSubjects(String uid, List<String> subjectIds) async {
    await _firestore.collection(studentsCollection).doc(uid).set(
      {'assignedSubjectIds': subjectIds, 'updatedAt': DateTime.now().toIso8601String()},
      SetOptions(merge: true),
    );
  }

  Future<void> saveProfile(StudentProfile profile) async {
    await _firestore
        .collection(studentsCollection)
        .doc(profile.uid)
        .set(profile.toMap(), SetOptions(merge: true));
  }

  /// Used by the student-facing Profile screen, which only ever lets a
  /// student edit their own name/mobile/target exam. Writes only those
  /// fields so it can never clobber admin-managed fields (`isBlocked`,
  /// `assignedSubjectIds`) that this screen doesn't know about.
  Future<void> updateSelfEditableFields({
    required String uid,
    required String name,
    required String mobile,
    required String targetExam,
  }) async {
    await _firestore.collection(studentsCollection).doc(uid).set({
      'name': name,
      'mobile': mobile,
      'targetExam': targetExam,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }
}

/// Shared instance used by the Signup/Profile screens.
final ProfileRepository profileRepository = ProfileRepository();
