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

  Future<void> saveProfile(StudentProfile profile) async {
    await _firestore
        .collection(studentsCollection)
        .doc(profile.uid)
        .set(profile.toMap(), SetOptions(merge: true));
  }
}

/// Shared instance used by the Signup/Profile screens.
final ProfileRepository profileRepository = ProfileRepository();
