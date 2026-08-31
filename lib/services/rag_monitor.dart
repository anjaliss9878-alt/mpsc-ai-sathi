import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/rag_monitor_event.dart';

/// Last Multi-RAG monitor event (tests + optional owner-only Firestore).
class RagMonitor {
  RagMonitor({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  RagMonitorEvent? last;

  static const String collection = 'ragEvents';

  Future<void> record(RagMonitorEvent event) async {
    last = event;
    final db = _firestore;
    if (db == null || event.uid.isEmpty) return;
    try {
      await db
          .collection('students')
          .doc(event.uid)
          .collection(collection)
          .add(event.toMap());
    } catch (_) {
      // Monitoring must never break student answers.
    }
  }
}

final RagMonitor ragMonitor = RagMonitor();
