import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';

/// Reads/writes `ragSources/{sourceId}`.
class RagSourceRepository {
  RagSourceRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String collection = 'ragSources';

  CollectionReference<Map<String, dynamic>> get _ref =>
      _firestore.collection(collection);

  Stream<List<RagSource>> watchAll() {
    return _ref.snapshots().map((snap) {
      final items = snap.docs
          .map((d) => RagSource.fromMap(d.data(), d.id))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    });
  }

  /// Student/catalog: published + Ready only. The query constraints must
  /// match firestore.rules (`published == true` and `status == Ready`) so
  /// list listeners are not permission-denied.
  Query<Map<String, dynamic>> get _publishedReadyQuery => _ref
      .where('published', isEqualTo: true)
      .where(
        'status',
        isEqualTo: ragSourceStatusToString(RagSourceStatus.ready),
      );

  Stream<List<RagSource>> watchPublishedReady() {
    return _publishedReadyQuery.snapshots().map((snap) {
      final items = snap.docs
          .map((d) => RagSource.fromMap(d.data(), d.id))
          .where((s) => s.isUsableForRetrieval)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    });
  }

  Future<List<RagSource>> getPublishedReadyOnce() async {
    final snap = await _publishedReadyQuery.get();
    return snap.docs
        .map((d) => RagSource.fromMap(d.data(), d.id))
        .where((s) => s.isUsableForRetrieval)
        .toList();
  }

  Future<RagSource?> get(String id) async {
    if (id.isEmpty) return null;
    final snap = await _ref.doc(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return RagSource.fromMap(snap.data()!, snap.id);
  }

  Future<String> create(RagSource source) async {
    try {
      final doc = source.id.isEmpty ? _ref.doc() : _ref.doc(source.id);
      await doc.set(source.copyWith().toMap());
      return doc.id;
    } catch (e) {
      throw RagException.fromError(e);
    }
  }

  Future<void> update(RagSource source) async {
    try {
      await _ref.doc(source.id).set(source.toMap(), SetOptions(merge: true));
    } catch (e) {
      throw RagException.fromError(e);
    }
  }

  Future<void> patch(String id, Map<String, dynamic> fields) async {
    try {
      await _ref.doc(id).set(
        {
          ...fields,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      throw RagException.fromError(e);
    }
  }

  Future<RagSource?> findLinked({
    required String collection,
    required String linkedId,
  }) async {
    if (linkedId.isEmpty) return null;
    final snap = await _ref.get();
    for (final d in snap.docs) {
      final source = RagSource.fromMap(d.data(), d.id);
      if (source.linkedCollection == collection && source.linkedId == linkedId) {
        return source;
      }
    }
    return null;
  }

  Future<void> delete(String id) async {
    try {
      await _ref.doc(id).delete();
    } catch (e) {
      throw RagException.fromError(e);
    }
  }

  /// Sources allowed by a retrieval filter (published/Ready enforced).
  Future<List<RagSource>> resolveFilter(RagSourceFilter filter) async {
    final all = filter.onlyPublishedReady
        ? await getPublishedReadyOnce()
        : (await _ref.get())
            .docs
            .map((d) => RagSource.fromMap(d.data(), d.id))
            .toList();
    return applyFilter(all, filter);
  }

  static List<RagSource> applyFilter(
    List<RagSource> sources,
    RagSourceFilter filter,
  ) {
    Iterable<RagSource> list = sources;
    if (filter.onlyPublishedReady) {
      list = list.where((s) => s.isUsableForRetrieval);
    }
    switch (filter.scope) {
      case RagSourceScope.allPublished:
        break;
      case RagSourceScope.selectedSources:
        final ids = filter.sourceIds.toSet();
        list = list.where((s) => ids.contains(s.id));
        break;
      case RagSourceScope.subjectChapter:
        if (filter.subjectId.isNotEmpty) {
          list = list.where((s) => s.subjectId == filter.subjectId);
        } else if (filter.subject.trim().isNotEmpty) {
          final q = filter.subject.trim().toLowerCase();
          list = list.where((s) => s.subject.toLowerCase() == q);
        }
        if (filter.chapterId.isNotEmpty) {
          list = list.where((s) => s.chapterId == filter.chapterId);
        } else if (filter.chapter.trim().isNotEmpty) {
          final q = filter.chapter.trim().toLowerCase();
          list = list.where((s) => s.chapter.toLowerCase() == q);
        }
        break;
    }
    if (filter.exam.trim().isNotEmpty) {
      final q = filter.exam.trim().toLowerCase();
      list = list.where((s) => s.exam.toLowerCase() == q);
    }
    if (filter.sourceType.trim().isNotEmpty) {
      final q = filter.sourceType.trim().toLowerCase();
      list = list.where(
        (s) => ragSourceTypeToString(s.sourceType) == q,
      );
    }
    return list.where((s) => matchesRagSourceMetadata(s, filter)).toList();
  }
}

final RagSourceRepository ragSourceRepository = RagSourceRepository();
