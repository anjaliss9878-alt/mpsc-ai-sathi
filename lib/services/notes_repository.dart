import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';

/// Reads/writes the Subjects → Chapters → Notes hierarchy in Firestore:
/// `subjects/{id}`, `chapters/{id}` (with `subjectId`), `notes/{id}` (with
/// `subjectId` + `chapterId`).
///
/// Shared by both the student-facing Notes screens (read-only streams) and
/// the Admin Panel (full CRUD) — content updated from the Admin Panel is
/// picked up instantly by any open student screen via `.snapshots()`.
class NotesRepository {
  NotesRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String subjectsCollection = 'subjects';
  static const String chaptersCollection = 'chapters';
  static const String notesCollection = 'notes';

  CollectionReference<Map<String, dynamic>> get _subjectsRef =>
      _firestore.collection(subjectsCollection);
  CollectionReference<Map<String, dynamic>> get _chaptersRef =>
      _firestore.collection(chaptersCollection);
  CollectionReference<Map<String, dynamic>> get _notesRef =>
      _firestore.collection(notesCollection);

  // ── Subjects ──────────────────────────────────────────────────────────

  Stream<List<SubjectItem>> watchSubjects() {
    return _subjectsRef.orderBy('order').snapshots().map(
          (snap) => snap.docs
              .map((d) => SubjectItem.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  Future<String> addSubject(SubjectItem subject) async {
    final doc = await _subjectsRef.add(subject.toMap());
    return doc.id;
  }

  Future<void> updateSubject(SubjectItem subject) async {
    await _subjectsRef.doc(subject.id).set(subject.toMap(), SetOptions(merge: true));
  }

  /// Deletes a subject along with its chapters and notes.
  Future<void> deleteSubject(String subjectId) async {
    final chapters = await _chaptersRef.where('subjectId', isEqualTo: subjectId).get();
    final notes = await _notesRef.where('subjectId', isEqualTo: subjectId).get();
    final batch = _firestore.batch();
    for (final d in chapters.docs) {
      batch.delete(d.reference);
    }
    for (final d in notes.docs) {
      batch.delete(d.reference);
    }
    batch.delete(_subjectsRef.doc(subjectId));
    await batch.commit();
  }

  // ── Chapters ──────────────────────────────────────────────────────────

  Stream<List<ChapterItem>> watchChapters(String subjectId) {
    return _chaptersRef
        .where('subjectId', isEqualTo: subjectId)
        .orderBy('order')
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => ChapterItem.fromMap(d.data(), d.id)).toList(),
        );
  }

  Future<String> addChapter(ChapterItem chapter) async {
    final doc = await _chaptersRef.add(chapter.toMap());
    return doc.id;
  }

  Future<void> updateChapter(ChapterItem chapter) async {
    await _chaptersRef.doc(chapter.id).set(chapter.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteChapter(String chapterId) async {
    final notes = await _notesRef.where('chapterId', isEqualTo: chapterId).get();
    final batch = _firestore.batch();
    for (final d in notes.docs) {
      batch.delete(d.reference);
    }
    batch.delete(_chaptersRef.doc(chapterId));
    await batch.commit();
  }

  // ── Notes ─────────────────────────────────────────────────────────────

  Stream<NoteItem?> watchNoteForChapter(String chapterId) {
    return _notesRef.where('chapterId', isEqualTo: chapterId).limit(1).snapshots().map(
          (snap) => snap.docs.isEmpty
              ? null
              : NoteItem.fromMap(snap.docs.first.data(), snap.docs.first.id),
        );
  }

  Future<NoteItem?> getNoteForChapter(String chapterId) async {
    final snap = await _notesRef.where('chapterId', isEqualTo: chapterId).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return NoteItem.fromMap(snap.docs.first.data(), snap.docs.first.id);
  }

  /// Creates or updates the single note document for [chapterId].
  Future<void> saveNote({
    String? noteId,
    required String subjectId,
    required String chapterId,
    required List<String> importantPoints,
    required List<String> revisionSummary,
  }) async {
    final data = NoteItem(
      id: noteId ?? '',
      subjectId: subjectId,
      chapterId: chapterId,
      importantPoints: importantPoints,
      revisionSummary: revisionSummary,
    ).toMap();
    if (noteId == null || noteId.isEmpty) {
      await _notesRef.add(data);
    } else {
      await _notesRef.doc(noteId).set(data, SetOptions(merge: true));
    }
  }
}

/// Shared instance used by both student Notes screens and the Admin Panel.
final NotesRepository notesRepository = NotesRepository();
