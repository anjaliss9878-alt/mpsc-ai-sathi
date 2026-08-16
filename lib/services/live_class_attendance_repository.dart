import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/live_class_attendance_item.dart';

/// Reads/writes Live Class attendance records in Firestore at
/// `liveClassAttendance/{id}`. See `live_class_attendance_item.dart` for why
/// this is a flat top-level collection instead of a subcollection.
class LiveClassAttendanceRepository {
  LiveClassAttendanceRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'liveClassAttendance';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  /// All attendance entries for one class — used by the Admin "Attendance"
  /// screen.
  Stream<List<LiveClassAttendanceItem>> watchForClass(String liveClassId) {
    return _ref.where('liveClassId', isEqualTo: liveClassId).snapshots().map(
          (snap) => snap.docs
              .map((d) => LiveClassAttendanceItem.fromMap(d.data(), d.id))
              .toList()
            ..sort((a, b) => b.markedAt.compareTo(a.markedAt)),
        );
  }

  /// A student's own attendance history across every class — used by the
  /// student-facing "My Attendance" screen.
  Stream<List<LiveClassAttendanceItem>> watchForStudent(String uid) {
    return _ref.where('uid', isEqualTo: uid).snapshots().map(
          (snap) => snap.docs
              .map((d) => LiveClassAttendanceItem.fromMap(d.data(), d.id))
              .toList()
            ..sort((a, b) => b.markedAt.compareTo(a.markedAt)),
        );
  }

  /// Whether [uid] has already marked attendance for [liveClassId] — used to
  /// avoid double-marking (and double-counting) on repeated Join taps.
  Future<bool> hasMarked(String liveClassId, String uid) async {
    final snap = await _ref
        .where('liveClassId', isEqualTo: liveClassId)
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// Marks [uid] present for [liveClassId], skipping silently if already
  /// marked.
  Future<void> markAttendance({
    required String liveClassId,
    required String liveClassTitle,
    required String uid,
    required String studentName,
    required String studentEmail,
  }) async {
    if (await hasMarked(liveClassId, uid)) return;
    await _ref.add(
      LiveClassAttendanceItem(
        id: '',
        liveClassId: liveClassId,
        liveClassTitle: liveClassTitle,
        uid: uid,
        studentName: studentName,
        studentEmail: studentEmail,
        markedAt: DateTime.now(),
      ).toMap(),
    );
  }
}

/// Shared instance used by both the student Join screen and the Admin Panel.
final LiveClassAttendanceRepository liveClassAttendanceRepository =
    LiveClassAttendanceRepository();
