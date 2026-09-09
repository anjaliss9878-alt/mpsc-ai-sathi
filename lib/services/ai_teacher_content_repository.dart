import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/ai_teacher_content_item.dart';

/// Reads/writes admin-authored AI Teacher lessons in Firestore at
/// `aiTeacherContent/{id}`.
class AiTeacherContentRepository {
  AiTeacherContentRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'aiTeacherContent';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<AiTeacherContentItem>> watchAll() {
    return _ref.snapshots().map(
          (snap) => snap.docs
              .map((d) => AiTeacherContentItem.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  Stream<List<AiTeacherContentItem>> watchPublished() {
    return Stream.multi((controller) {
      StreamSubscription<List<AiTeacherContentItem>>? sub;
      var usingFallback = false;

      List<AiTeacherContentItem> filter(List<AiTeacherContentItem> all) =>
          all.where((l) => l.isStudentVisible).toList();

      void listenPublished({required bool requirePublishedStatus}) {
        Query<Map<String, dynamic>> query =
            _ref.where('published', isEqualTo: true);
        if (requirePublishedStatus) {
          query = query.where('status', isEqualTo: 'published');
        }
        sub = query.snapshots().map((snap) {
          return filter(
            snap.docs
                .map((d) => AiTeacherContentItem.fromMap(d.data(), d.id))
                .toList(),
          );
        }).listen(
          controller.add,
          onError: (Object error, StackTrace stackTrace) {
            if (!usingFallback &&
                !requirePublishedStatus &&
                error.toString().contains('permission-denied')) {
              usingFallback = true;
              sub?.cancel();
              listenPublished(requirePublishedStatus: true);
              return;
            }
            controller.addError(error, stackTrace);
          },
          onDone: controller.close,
        );
      }

      listenPublished(requirePublishedStatus: false);
      controller.onCancel = () async {
        await sub?.cancel();
      };
    });
  }

  Future<String> add(AiTeacherContentItem item) async {
    final doc = await _ref.add(item.toMap());
    return doc.id;
  }

  Future<void> update(AiTeacherContentItem item) async {
    await _ref.doc(item.id).set(item.toMap(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await _ref.doc(id).delete();
  }

  /// Finds the first *published* authored lesson whose keywords match
  /// [question]. Drafts never play for students. Returns `null` if none
  /// match — the classroom then falls back to live Gemini as before.
  Future<AiTeacherContentItem?> findMatchingLesson(String question) async {
    final normalized = question.toLowerCase();
    if (normalized.trim().isEmpty) return null;
    final items = await _studentPublishedOnce();
    for (final item in items) {
      for (final keyword in item.keywords) {
        if (keyword.trim().isEmpty) continue;
        if (normalized.contains(keyword.toLowerCase().trim())) {
          return item;
        }
      }
    }
    return null;
  }

  Future<List<AiTeacherContentItem>> _studentPublishedOnce() async {
    try {
      final snap = await _ref.where('published', isEqualTo: true).get();
      return snap.docs
          .map((d) => AiTeacherContentItem.fromMap(d.data(), d.id))
          .where((l) => l.isStudentVisible)
          .toList();
    } catch (error) {
      if (!error.toString().contains('permission-denied')) rethrow;
      final snap = await _ref
          .where('published', isEqualTo: true)
          .where('status', isEqualTo: 'published')
          .get();
      return snap.docs
          .map((d) => AiTeacherContentItem.fromMap(d.data(), d.id))
          .where((l) => l.isStudentVisible)
          .toList();
    }
  }
}

/// Shared instance used by the Admin Panel and the AI Teacher Classroom.
final AiTeacherContentRepository aiTeacherContentRepository =
    AiTeacherContentRepository();
