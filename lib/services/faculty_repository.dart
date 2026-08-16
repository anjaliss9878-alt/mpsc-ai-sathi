import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/faculty_item.dart';

/// Reads/writes faculty profiles in Firestore at `faculty/{id}`.
class FacultyRepository {
  FacultyRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'faculty';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<FacultyItem>> watchAll() {
    return _ref.snapshots().map(
          (snap) => snap.docs.map((d) => FacultyItem.fromMap(d.data(), d.id)).toList(),
        );
  }

  Future<FacultyItem?> getById(String id) async {
    if (id.isEmpty) return null;
    final doc = await _ref.doc(id).get();
    if (!doc.exists) return null;
    return FacultyItem.fromMap(doc.data()!, doc.id);
  }

  Future<String> add(FacultyItem item) async {
    final doc = await _ref.add(item.toMap());
    return doc.id;
  }

  Future<void> update(FacultyItem item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }
}

/// Shared instance used by both the Live Class admin/student screens.
final FacultyRepository facultyRepository = FacultyRepository();
