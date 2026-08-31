import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/job_alert.dart';

/// Reads/writes job / exam alerts at `jobAlerts/{id}`.
///
/// Shared by the Admin Panel (full CRUD) and the student Job Alerts screen
/// (published documents only). There is no external job-source API.
class JobAlertsRepository {
  JobAlertsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'jobAlerts';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<JobAlert>> watchAll() {
    return _ref.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => JobAlert.fromMap(d.data(), d.id))
          .toList()
        ..sort(_compare);
      return list;
    });
  }

  Stream<List<JobAlert>> watchPublished() {
    return watchAll().map(
      (list) => list.where((a) => a.published).toList(),
    );
  }

  Future<List<JobAlert>> getPublished() async {
    final snap = await _ref.get();
    final list = snap.docs
        .map((d) => JobAlert.fromMap(d.data(), d.id))
        .where((a) => a.published)
        .toList()
      ..sort(_compare);
    return list;
  }

  Future<String> add(JobAlert item) async {
    final data = item.toMap();
    data['createdAt'] = DateTime.now().toIso8601String();
    final doc = await _ref.add(data);
    return doc.id;
  }

  Future<void> update(JobAlert item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }

  int _compare(JobAlert a, JobAlert b) {
    final aClose = a.lastDateTime ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bClose = b.lastDateTime ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bClose.compareTo(aClose);
  }
}

JobAlertsRepository? _jobAlertsRepository;
JobAlertsRepository get jobAlertsRepository =>
    _jobAlertsRepository ??= JobAlertsRepository();
