import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/content_index.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/note_item.dart';
import 'package:mpsc_combine_ai/models/pdf_content_block.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/data/mpsc_group_b_structure.dart';
import 'package:mpsc_combine_ai/data/mpsc_group_b_chapters.dart';
import 'package:mpsc_combine_ai/data/student_curriculum.dart';
import 'package:mpsc_combine_ai/utils/firestore_payload.dart';
import 'package:mpsc_combine_ai/utils/json_list.dart';

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
  static const String examsCollection = 'exams';

  CollectionReference<Map<String, dynamic>> get _subjectsRef =>
      _firestore.collection(subjectsCollection);
  CollectionReference<Map<String, dynamic>> get _chaptersRef =>
      _firestore.collection(chaptersCollection);
  CollectionReference<Map<String, dynamic>> get _notesRef =>
      _firestore.collection(notesCollection);
  CollectionReference<Map<String, dynamic>> get _examsRef =>
      _firestore.collection(examsCollection);

  // ── Exams ─────────────────────────────────────────────────────────────

  Stream<List<ExamItem>> watchExams() {
    return Stream.multi((controller) {
      final sub = _examsRef.snapshots().listen(
        (snap) {
          final exams = snap.docs
              .map((d) => ExamItem.fromMap(d.data(), d.id))
              .toList()
            ..sort((a, b) => a.order.compareTo(b.order));
          controller.add(exams.isEmpty ? [ExamItem.groupBCombined()] : exams);
        },
        onError: (Object error, StackTrace stack) {
          if (error is FirebaseException && error.code == 'permission-denied') {
            controller.add([ExamItem.groupBCombined()]);
          } else {
            controller.addError(error, stack);
          }
        },
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  /// Reads `exams`. If the collection list is denied (stale deployed rules
  /// without `match /exams/{examId}`), falls back to the Group B Combined
  /// exam so Notes / Content Index still load.
  Future<List<ExamItem>> getExamsOnce() async {
    try {
      final snap = await _examsRef.get();
      final exams = snap.docs
          .map((d) => ExamItem.fromMap(d.data(), d.id))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      if (exams.isNotEmpty) return exams;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
    return [await ensureDefaultExam()];
  }

  Future<ExamItem> ensureDefaultExam() async {
    final exam = ExamItem.mpscCombine();
    var result = exam;
    try {
      final snap = await _examsRef.doc(kDefaultExamId).get();
      if (snap.exists && snap.data() != null) {
        result = ExamItem.fromMap(snap.data()!, snap.id);
      } else {
        await _examsRef.doc(exam.id).set(exam.toMap(), SetOptions(merge: true));
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
    await ensureMpscGroupBCombinedStructure();
    return result;
  }

  /// Exam + subject + grouping-chapter level (no topics). Idempotent by id.
  Future<ExamItem> ensureMpscGroupBCombinedStructure() async {
    final exam = ExamItem.groupBCombined();
    try {
      await _examsRef.doc(exam.id).set(exam.toMap(), SetOptions(merge: true));
      for (final subject in mpscGroupBCombinedSubjects()) {
        await upsertSubjectById(subject);
      }
      for (final chapter in mpscGroupBCombinedChapters()) {
        await upsertChapterById(chapter);
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
    final snap = await _examsRef.doc(exam.id).get();
    if (snap.exists && snap.data() != null) {
      return ExamItem.fromMap(snap.data()!, snap.id);
    }
    return exam;
  }

  Future<String> upsertSubjectById(SubjectItem subject) async {
    if (subject.id.isEmpty) return addSubject(subject);
    final snap = await _subjectsRef.doc(subject.id).get();
    if (!snap.exists || snap.data() == null) {
      final data = subject.toMap();
      data['published'] = subject.published;
      data['order'] = subject.order;
      await _subjectsRef.doc(subject.id).set(data, SetOptions(merge: true));
      return subject.id;
    }
    final existing = SubjectItem.fromMap(snap.data()!, snap.id);
    await updateSubject(
      SubjectItem(
        id: existing.id,
        title: subject.title,
        subtitle: subject.subtitle,
        iconName: subject.iconName,
        order: subject.order,
        imageUrl:
            subject.imageUrl.isNotEmpty ? subject.imageUrl : existing.imageUrl,
        slug: subject.slug,
        nameEn: subject.nameEn,
        examId: subject.examId,
        stageId: subject.stageId,
        paperId: subject.paperId,
        published: subject.published,
      ),
    );
    return existing.id;
  }

  Future<String> upsertChapterById(ChapterItem chapter) async {
    if (chapter.id.isEmpty) return upsertChapterBySlug(chapter);
    final snap = await _chaptersRef.doc(chapter.id).get();
    if (!snap.exists || snap.data() == null) {
      await _chaptersRef
          .doc(chapter.id)
          .set(chapter.toMap(), SetOptions(merge: true));
      return chapter.id;
    }
    final existing = ChapterItem.fromMap(snap.data()!, snap.id);
    await updateChapter(
      ChapterItem(
        id: existing.id,
        subjectId: chapter.subjectId,
        title: chapter.title,
        order: chapter.order,
        estimatedStudyMinutes: chapter.estimatedStudyMinutes > 0
            ? chapter.estimatedStudyMinutes
            : existing.estimatedStudyMinutes,
        description: chapter.description.isNotEmpty
            ? chapter.description
            : existing.description,
        slug: chapter.slug,
        titleEn: chapter.titleEn.isNotEmpty ? chapter.titleEn : existing.titleEn,
        examId: chapter.examId.isNotEmpty ? chapter.examId : existing.examId,
        parentChapterId: existing.parentChapterId.isNotEmpty
            ? existing.parentChapterId
            : chapter.parentChapterId,
        nodeType:
            chapter.nodeType.isNotEmpty ? chapter.nodeType : existing.nodeType,
        published: chapter.published,
        tags: chapter.tags.isNotEmpty ? chapter.tags : existing.tags,
        thumbnailUrl: existing.thumbnailUrl.isNotEmpty
            ? existing.thumbnailUrl
            : chapter.thumbnailUrl,
        pdfUrl: existing.pdfUrl.isNotEmpty ? existing.pdfUrl : chapter.pdfUrl,
        aiSummary:
            existing.aiSummary.isNotEmpty ? existing.aiSummary : chapter.aiSummary,
        revisionNotes: existing.revisionNotes.isNotEmpty
            ? existing.revisionNotes
            : chapter.revisionNotes,
        classroomLessonId: existing.classroomLessonId.isNotEmpty
            ? existing.classroomLessonId
            : chapter.classroomLessonId,
      ),
    );
    return existing.id;
  }

  Future<String> addExam(ExamItem exam) async {
    final data = exam.toMap();
    if (exam.id.isNotEmpty) {
      await _examsRef.doc(exam.id).set(data, SetOptions(merge: true));
      return exam.id;
    }
    final doc = await _examsRef.add(data);
    return doc.id;
  }

  Future<void> updateExam(ExamItem exam) async {
    await _examsRef.doc(exam.id).set(exam.toMap(), SetOptions(merge: true));
  }

  // ── Subjects ──────────────────────────────────────────────────────────

  /// Admin: all subjects from `subjects` (same collection students read).
  ///
  /// Uses a plain collection snapshot + client-side sort (same pattern as
  /// [watchChapters]). Firestore `orderBy('order')` **excludes** documents
  /// that are missing the `order` field, which made Admin/student lists look
  /// empty after console imports or older writes.
  Stream<List<SubjectItem>> watchSubjects() {
    return _subjectsRef.snapshots().map(_mapSubjectsSnapshot);
  }

  /// Student: published subjects only from the same `subjects` collection.
  /// When [examId] is non-empty, only published subjects belonging to that exam
  /// are returned. When omitted or empty, all published subjects are returned.
  ///
  /// Strategy (works with both current and legacy deployed rules):
  /// 1. Prefer a full-collection listen + client `published` filter — this
  ///    also surfaces docs that omit `published` (treated as published).
  /// 2. If that listen is denied (legacy rules gating list queries on
  ///    `published == true`), fall back to an equality query that satisfies
  ///    those rules. Admin writes always set `published` as a bool.
  Stream<List<SubjectItem>> watchPublishedSubjects({
    String? examId,
  }) {
    return Stream.multi((controller) {
      StreamSubscription<List<SubjectItem>>? sub;
      var usingFallback = false;

      bool filterSubject(SubjectItem s) {
        if (!s.published) return false;
        if (examId == null || examId.isEmpty) return true;
        return subjectBelongsToExam(s, examId);
      }

      void listenFallback() {
        usingFallback = true;
        sub = _subjectsRef
            .where('published', isEqualTo: true)
            .snapshots()
            .map(_mapSubjectsSnapshot)
            .listen(
              (all) => controller.add(all.where(filterSubject).toList()),
              onError: controller.addError,
              onDone: controller.close,
            );
      }

      sub = watchSubjects().listen(
        (all) => controller.add(all.where(filterSubject).toList()),
        onError: (Object error, StackTrace stackTrace) {
          if (usingFallback) {
            controller.addError(error, stackTrace);
            return;
          }
          sub?.cancel();
          listenFallback();
        },
        onDone: () {
          if (!usingFallback) controller.close();
        },
      );

      controller.onCancel = () async {
        await sub?.cancel();
      };
    });
  }

  List<SubjectItem> _mapSubjectsSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final subjects = snap.docs
        .map((d) => SubjectItem.fromMap(d.data(), d.id))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return subjects;
  }

  Future<List<SubjectItem>> getSubjectsOnce({
    String? examId,
  }) async {
    final snap = await _subjectsRef.get();
    final subjects = snap.docs
        .map((d) => SubjectItem.fromMap(d.data(), d.id))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    if (examId == null || examId.isEmpty) return subjects;
    return subjects.where((s) => subjectBelongsToExam(s, examId)).toList();
  }

  Future<SubjectItem?> findSubjectBySlug(String slug) async {
    if (slug.isEmpty) return null;
    final snap = await _subjectsRef.where('slug', isEqualTo: slug).limit(1).get();
    if (snap.docs.isEmpty) {
      // Fallback: older seeds may lack slug — match by title/nameMr once.
      final all = await getSubjectsOnce();
      for (final s in all) {
        if (s.slug == slug) return s;
      }
      return null;
    }
    final d = snap.docs.first;
    return SubjectItem.fromMap(d.data(), d.id);
  }

  Future<String> addSubject(SubjectItem subject) async {
    // Always persist explicit bool/int fields so student queries and
    // legacy published-gated rules never miss Admin-created subjects.
    final data = subject.toMap();
    data['published'] = subject.published;
    data['order'] = subject.order;
    final doc = await _subjectsRef.add(data);
    return doc.id;
  }

  Future<void> updateSubject(SubjectItem subject) async {
    final data = subject.toMap();
    data['published'] = subject.published;
    data['order'] = subject.order;
    await _subjectsRef.doc(subject.id).set(
      data,
      SetOptions(merge: true),
    );
  }

  /// Creates or updates a subject identified by [SubjectItem.slug].
  /// Returns the Firestore document id.
  Future<String> upsertSubjectBySlug(SubjectItem subject) async {
    final existing = await findSubjectBySlug(subject.slug);
    if (existing == null) {
      return addSubject(subject);
    }
    await updateSubject(
      SubjectItem(
        id: existing.id,
        title: subject.title,
        subtitle: subject.subtitle,
        iconName: subject.iconName,
        order: subject.order,
        imageUrl: subject.imageUrl.isNotEmpty ? subject.imageUrl : existing.imageUrl,
        slug: subject.slug,
        nameEn: subject.nameEn,
        examId: subject.examId.isNotEmpty ? subject.examId : existing.examId,
        stageId: subject.stageId.isNotEmpty ? subject.stageId : existing.stageId,
        paperId: subject.paperId.isNotEmpty ? subject.paperId : existing.paperId,
        published: subject.published,
      ),
    );
    return existing.id;
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

  /// Admin: all chapters for a subject.
  Stream<List<ChapterItem>> watchChapters(String subjectId) {
    // Equality-only query (no composite index). Order is applied client-side
    // so Admin/student chapter lists work immediately without a Firestore
    // composite index on (subjectId, order).
    return _chaptersRef.where('subjectId', isEqualTo: subjectId).snapshots().map(
      (snap) {
        final chapters = snap.docs
            .map((d) => ChapterItem.fromMap(d.data(), d.id))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
        return chapters;
      },
    );
  }

  /// Student curriculum rows for a subject (`subjectId` equality query).
  ///
  /// Published topics stay first when they exist. If the subject only has
  /// grouping `nodeType=chapter` documents (Group B Phase 2), those are shown.
  Stream<List<ChapterItem>> watchPublishedChapters(String subjectId) {
    return watchChapters(subjectId).map(selectStudentCurriculumChapters);
  }

  /// Admin: root chapters for a subject (`parentChapterId` empty).
  Stream<List<ChapterItem>> watchRootChapters(String subjectId) {
    return watchChapters(subjectId).map(
      (all) => all.where((c) => c.parentChapterId.isEmpty).toList(),
    );
  }

  /// Admin: topics (and sub-topics) under a chapter.
  Stream<List<ChapterItem>> watchChildChapters(String parentChapterId) {
    if (parentChapterId.isEmpty) return Stream.value(const []);
    return _chaptersRef
        .where('parentChapterId', isEqualTo: parentChapterId)
        .snapshots()
        .map((snap) {
      final chapters = snap.docs
          .map((d) => ChapterItem.fromMap(d.data(), d.id))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      return chapters;
    });
  }

  Future<List<ChapterItem>> getChildChaptersOnce(String parentChapterId) async {
    if (parentChapterId.isEmpty) return const [];
    final snap = await _chaptersRef
        .where('parentChapterId', isEqualTo: parentChapterId)
        .get();
    final chapters = snap.docs
        .map((d) => ChapterItem.fromMap(d.data(), d.id))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return chapters;
  }

  Future<List<ChapterItem>> getChaptersOnce(String subjectId) async {
    final snap = await _chaptersRef.where('subjectId', isEqualTo: subjectId).get();
    final chapters = snap.docs
        .map((d) => ChapterItem.fromMap(d.data(), d.id))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return chapters;
  }

  /// All `chapters` documents (roots + topics). Used by bulk import to
  /// resolve names onto Part 1 ids without a second tree.
  Future<List<ChapterItem>> getAllChaptersOnce() async {
    final snap = await _chaptersRef.get();
    final chapters = snap.docs
        .map((d) => ChapterItem.fromMap(d.data(), d.id))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return chapters;
  }

  Future<ChapterItem?> findChapterBySlug({
    required String subjectId,
    required String slug,
  }) async {
    if (slug.isEmpty) return null;
    final chapters = await getChaptersOnce(subjectId);
    for (final c in chapters) {
      if (c.slug == slug) return c;
    }
    return null;
  }

  Future<String> addChapter(ChapterItem chapter) async {
    final data = chapter.toMap();
    final doc = await _chaptersRef.add(data);
    return doc.id;
  }

  Future<void> updateChapter(ChapterItem chapter) async {
    await _chaptersRef.doc(chapter.id).set(
      chapter.toMap(),
      SetOptions(merge: true),
    );
  }

  /// Creates or updates a chapter identified by [ChapterItem.slug] within
  /// [ChapterItem.subjectId]. Returns the Firestore document id.
  Future<String> upsertChapterBySlug(ChapterItem chapter) async {
    final existing = await findChapterBySlug(
      subjectId: chapter.subjectId,
      slug: chapter.slug,
    );
    if (existing == null) {
      return addChapter(chapter);
    }
    await updateChapter(
      ChapterItem(
        id: existing.id,
        subjectId: chapter.subjectId,
        title: chapter.title,
        order: chapter.order,
        estimatedStudyMinutes:
            chapter.estimatedStudyMinutes > 0
                ? chapter.estimatedStudyMinutes
                : existing.estimatedStudyMinutes,
        description:
            chapter.description.isNotEmpty ? chapter.description : existing.description,
        slug: chapter.slug,
        titleEn: chapter.titleEn.isNotEmpty ? chapter.titleEn : existing.titleEn,
        examId: chapter.examId.isNotEmpty ? chapter.examId : existing.examId,
        parentChapterId: chapter.parentChapterId.isNotEmpty
            ? chapter.parentChapterId
            : existing.parentChapterId,
        nodeType: chapter.nodeType.isNotEmpty ? chapter.nodeType : existing.nodeType,
        published: chapter.published,
        tags: chapter.tags.isNotEmpty ? chapter.tags : existing.tags,
        thumbnailUrl:
            chapter.thumbnailUrl.isNotEmpty ? chapter.thumbnailUrl : existing.thumbnailUrl,
        pdfUrl: chapter.pdfUrl.isNotEmpty ? chapter.pdfUrl : existing.pdfUrl,
        aiSummary: chapter.aiSummary.isNotEmpty ? chapter.aiSummary : existing.aiSummary,
        revisionNotes:
            chapter.revisionNotes.isNotEmpty ? chapter.revisionNotes : existing.revisionNotes,
        classroomLessonId: chapter.classroomLessonId.isNotEmpty
            ? chapter.classroomLessonId
            : existing.classroomLessonId,
      ),
    );
    return existing.id;
  }

  Future<void> deleteChapter(String chapterId) async {
    final children = await _chaptersRef
        .where('parentChapterId', isEqualTo: chapterId)
        .get();
    final noteRefs = <String, DocumentReference<Map<String, dynamic>>>{};
    Future<void> collectNotes(String id) async {
      final byChapter = await _notesRef.where('chapterId', isEqualTo: id).get();
      final byTopic = await _notesRef.where('topicId', isEqualTo: id).get();
      for (final d in [...byChapter.docs, ...byTopic.docs]) {
        noteRefs[d.id] = d.reference;
      }
    }

    await collectNotes(chapterId);
    for (final child in children.docs) {
      await collectNotes(child.id);
    }

    final batch = _firestore.batch();
    for (final ref in noteRefs.values) {
      batch.delete(ref);
    }
    for (final child in children.docs) {
      batch.delete(child.reference);
    }
    batch.delete(_chaptersRef.doc(chapterId));
    await batch.commit();
  }

  // ── Notes ─────────────────────────────────────────────────────────────

  /// All note documents (used by global search). Prefer chapter-scoped
  /// [watchNoteForChapter] for detail screens.
  Stream<List<NoteItem>> watchAllNotes() {
    return _notesRef.snapshots().map(
          (snap) => snap.docs
              .map((d) => NoteItem.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  Stream<List<NoteItem>> watchPublishedNotes() {
    return _watchStudentVisibleNotes((all) => all);
  }

  Stream<List<NoteItem>> _watchStudentVisibleNotes(
    List<NoteItem> Function(List<NoteItem> visible) then,
  ) {
    return Stream.multi((controller) {
      StreamSubscription<List<NoteItem>>? sub;
      var usingFallback = false;

      List<NoteItem> visible(List<NoteItem> all) =>
          then(all.where((n) => n.isStudentVisible).toList());

      void listenPublished({required bool requirePublishedStatus}) {
        Query<Map<String, dynamic>> query =
            _notesRef.where('published', isEqualTo: true);
        if (requirePublishedStatus) {
          query = query.where('status', isEqualTo: 'published');
        }
        sub = query
            .snapshots()
            .map(
              (snap) => visible(
                snap.docs.map((d) => NoteItem.fromMap(d.data(), d.id)).toList(),
              ),
            )
            .listen(
              controller.add,
              onError: (Object error, StackTrace stackTrace) {
                if (!usingFallback &&
                    !requirePublishedStatus &&
                    _isPermissionDenied(error)) {
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

  Future<SubjectItem?> getSubject(String subjectId) async {
    final snap = await _subjectsRef.doc(subjectId).get();
    if (!snap.exists || snap.data() == null) return null;
    return SubjectItem.fromMap(snap.data()!, snap.id);
  }

  Future<ChapterItem?> getChapter(String chapterId) async {
    final snap = await _chaptersRef.doc(chapterId).get();
    if (!snap.exists || snap.data() == null) return null;
    return ChapterItem.fromMap(snap.data()!, snap.id);
  }

  Stream<NoteItem?> watchNoteForChapter(String chapterId) {
    return watchAllNotes().map((all) => _pickNoteForNode(all, chapterId));
  }

  /// Student-facing note stream — hides unpublished / draft notes.
  Stream<NoteItem?> watchPublishedNoteForChapter(String chapterId) {
    return _watchStudentVisibleNotes((visible) {
      final note = _pickNoteForNode(visible, chapterId);
      return note == null ? const <NoteItem>[] : [note];
    }).map((list) => list.isEmpty ? null : list.first);
  }

  Future<NoteItem?> getNoteForChapter(String chapterId) async {
    try {
      final all = await _notesRef.get();
      final notes = all.docs
          .map((d) => NoteItem.fromMap(d.data(), d.id))
          .toList();
      return _pickNoteForNode(notes, chapterId);
    } catch (error) {
      if (!_isPermissionDenied(error)) rethrow;
      return _pickNoteForNode(await _studentPublishedNotesOnce(), chapterId);
    }
  }

  Future<NoteItem?> getNote(String noteId) async {
    if (noteId.isEmpty) return null;
    final snap = await _notesRef.doc(noteId).get();
    if (!snap.exists || snap.data() == null) return null;
    return NoteItem.fromMap(snap.data()!, snap.id);
  }

  Future<List<NoteItem>> getNotesForTopicOnce(String topicId) async {
    if (topicId.isEmpty) return const [];
    try {
      final all = await _notesRef.get();
      return [
        for (final d in all.docs)
          if (_noteMatchesNode(NoteItem.fromMap(d.data(), d.id), topicId))
            NoteItem.fromMap(d.data(), d.id),
      ];
    } catch (error) {
      if (!_isPermissionDenied(error)) rethrow;
      return [
        for (final n in await _studentPublishedNotesOnce())
          if (_noteMatchesNode(n, topicId)) n,
      ];
    }
  }

  Future<List<NoteItem>> _studentPublishedNotesOnce() async {
    try {
      final snap = await _notesRef.where('published', isEqualTo: true).get();
      return snap.docs
          .map((d) => NoteItem.fromMap(d.data(), d.id))
          .where((n) => n.isStudentVisible)
          .toList();
    } catch (error) {
      if (!_isPermissionDenied(error)) rethrow;
      final snap = await _notesRef
          .where('published', isEqualTo: true)
          .where('status', isEqualTo: 'published')
          .get();
      return snap.docs
          .map((d) => NoteItem.fromMap(d.data(), d.id))
          .where((n) => n.isStudentVisible)
          .toList();
    }
  }

  NoteItem? _pickNoteForNode(List<NoteItem> all, String nodeId) {
    if (nodeId.isEmpty) return null;
    NoteItem? byTopic;
    NoteItem? byChapterLeaf;
    NoteItem? byChapter;
    for (final n in all) {
      if (n.topicId == nodeId) {
        byTopic ??= n;
      } else if (n.chapterId == nodeId && n.topicId.isEmpty) {
        byChapterLeaf ??= n;
      } else if (n.chapterId == nodeId) {
        byChapter ??= n;
      }
    }
    return byTopic ?? byChapterLeaf ?? byChapter;
  }

  bool _noteMatchesNode(NoteItem note, String nodeId) {
    return note.topicId == nodeId ||
        note.chapterId == nodeId ||
        note.subTopicId == nodeId;
  }

  bool _isPermissionDenied(Object error) {
    if (error is FirebaseException) {
      return error.code == 'permission-denied';
    }
    return error.toString().contains('permission-denied');
  }

  /// Creates or updates the note document for [chapterId].
  ///
  /// Returns the note document id.
  ///
  /// **Partial updates**: any field left `null` is omitted from the write so
  /// one Admin screen cannot wipe fields owned by another (e.g. chapter form
  /// must not clear `importantPoints` authored on the dedicated notes form).
  /// On create, omitted fields default to empty values and `published: true`
  /// so students see the note immediately under current/legacy rules.
  Future<String> saveNote({
    String? noteId,
    required String subjectId,
    required String chapterId,
    String? examId,
    String? topicId,
    String? subTopicId,
    String? title,
    String? description,
    String? language,
    String? difficulty,
    String? source,
    List<String>? importantPoints,
    List<String>? revisionSummary,
    String? contentMarkdown,
    List<NoteAttachment>? attachments,
    List<PdfContentBlock>? pdfStructuredBlocks,
    String? pdfStoragePath,
    String? pdfFileName,
    int? pdfFileSize,
    int? pdfPageCount,
    String? videoUrl,
    List<String>? keywords,
    List<NoteMcq>? mcqs,
    bool? published,
    NoteWorkflowStatus? status,
    NoteRagStatus? ragStatus,
    String? ragSourceId,
    String? ragError,
    String? aiSummary,
    List<String>? tags,
  }) async {
    final isCreate = noteId == null || noteId.isEmpty;
    final data = <String, dynamic>{
      'subjectId': subjectId,
      'chapterId': chapterId,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (examId != null) {
      data['examId'] = resolvedContentExamId(
        examId: examId,
        subjectId: subjectId,
      );
    } else if (isCreate) {
      data['examId'] = resolvedContentExamId(
        examId: '',
        subjectId: subjectId,
      );
    }
    if (topicId != null) {
      data['topicId'] = topicId;
    } else if (isCreate) {
      data['topicId'] = '';
    }
    if (subTopicId != null) {
      data['subTopicId'] = subTopicId;
    } else if (isCreate) {
      data['subTopicId'] = '';
    }

    void putList(String key, List<String>? value, {required List<String> createDefault}) {
      if (value != null) {
        data[key] = value;
      } else if (isCreate) {
        data[key] = createDefault;
      }
    }

    void putString(String key, String? value, {required String createDefault}) {
      if (value != null) {
        data[key] = value;
      } else if (isCreate) {
        data[key] = createDefault;
      }
    }

    putString('title', title, createDefault: '');
    putString('description', description, createDefault: '');
    putString('language', language, createDefault: '');
    putString('difficulty', difficulty, createDefault: '');
    putString('source', source, createDefault: '');
    putList('importantPoints', importantPoints, createDefault: const []);
    putList('revisionSummary', revisionSummary, createDefault: const []);
    putString('contentMarkdown', contentMarkdown, createDefault: '');
    putString('videoUrl', videoUrl, createDefault: '');
    putList('keywords', keywords, createDefault: const []);
    putString('aiSummary', aiSummary, createDefault: '');
    putList('tags', tags, createDefault: const []);

    if (attachments != null) {
      data['attachments'] = attachments.map((a) => a.toMap()).toList();
      data['pdfUrl'] = _firstAttachmentUrl(attachments, 'pdf');
      data['docxUrl'] = _firstAttachmentUrl(attachments, 'docx');
      data['imageUrls'] = [
        for (final a in attachments)
          if (a.type == 'image' && a.url.trim().isNotEmpty) a.url.trim(),
      ];
    } else if (isCreate) {
      data['attachments'] = <Map<String, dynamic>>[];
      data['pdfUrl'] = '';
      data['docxUrl'] = '';
      data['imageUrls'] = <String>[];
    }
    putString('pdfStoragePath', pdfStoragePath, createDefault: '');
    putString('pdfFileName', pdfFileName, createDefault: '');
    if (pdfFileSize != null) {
      data['pdfFileSize'] = pdfFileSize;
    } else if (isCreate) {
      data['pdfFileSize'] = 0;
    }
    if (pdfPageCount != null) {
      data['pdfPageCount'] = pdfPageCount;
    } else if (isCreate) {
      data['pdfPageCount'] = 0;
    }

    if (pdfStructuredBlocks != null) {
      data['pdfStructuredBlocks'] =
          pdfStructuredBlocks.map((b) => b.toMap()).toList();
    } else if (isCreate) {
      data['pdfStructuredBlocks'] = <Map<String, dynamic>>[];
    }

    if (mcqs != null) {
      data['mcqs'] = [
        for (final m in mcqs)
          <String, dynamic>{
            'question': m.question,
            'options': asStringList(m.options),
            'correctIndex': m.correctIndex,
            'explanation': m.explanation,
          },
      ];
    } else if (isCreate) {
      data['mcqs'] = <Map<String, dynamic>>[];
    }

    if (status != null) {
      data['status'] = noteWorkflowStatusToString(status);
      data['published'] = noteWorkflowPublishedFlag(status);
    } else if (published != null) {
      data['published'] = published;
      data['status'] = noteWorkflowStatusToString(
        published ? NoteWorkflowStatus.published : NoteWorkflowStatus.draft,
      );
    } else if (isCreate) {
      // Explicit so student reads work even if deployed rules still gate on
      // `published == true` (legacy harden-rules commit).
      data['published'] = true;
      data['status'] = noteWorkflowStatusToString(NoteWorkflowStatus.published);
    }

    if (ragStatus != null) {
      data['ragStatus'] = noteRagStatusToString(ragStatus);
    } else if (isCreate) {
      data['ragStatus'] = noteRagStatusToString(NoteRagStatus.notIndexed);
    }
    putString('ragSourceId', ragSourceId, createDefault: '');
    putString('ragError', ragError, createDefault: '');

    final payload = prepareFirestoreNotePayload(data);

    if (isCreate) {
      final doc = await _notesRef.add(payload);
      return doc.id;
    }

    await _notesRef.doc(noteId).set(payload, SetOptions(merge: true));
    return noteId;
  }

  /// Deletes a single note document by id.
  Future<void> deleteNote(String noteId) async {
    if (noteId.isEmpty) {
      throw ArgumentError('noteId is required to delete a note');
    }
    await _notesRef.doc(noteId).delete();
  }

  Future<void> patchNote(String noteId, Map<String, dynamic> fields) async {
    if (noteId.isEmpty) {
      throw ArgumentError('noteId is required');
    }
    await _notesRef.doc(noteId).set(
      {
        ...fields,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      SetOptions(merge: true),
    );
  }
}

String _firstAttachmentUrl(List<NoteAttachment> attachments, String type) {
  for (final a in attachments) {
    if (a.type == type && a.url.trim().isNotEmpty) return a.url.trim();
  }
  return '';
}

/// Shared instance used by both student Notes screens and the Admin Panel.
final NotesRepository notesRepository = NotesRepository();
