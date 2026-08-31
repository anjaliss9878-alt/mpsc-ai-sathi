import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:mpsc_combine_ai/models/ai_lesson.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';

class AiLessonRepository {
  AiLessonRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('ai_lessons');

  String docIdFor({required String uid, required String topic}) {
    final material = '${uid.trim()}|${topic.trim().toLowerCase()}';
    final hash = sha256.convert(utf8.encode(material)).toString().substring(0, 20);
    final prefix = uid.length >= 8 ? uid.substring(0, 8) : uid;
    return '${prefix}_$hash';
  }

  DocumentReference<Map<String, dynamic>> doc(String id) => _col.doc(id);

  Stream<List<AiLesson>> watchMine(String uid, {int limit = 12}) {
    return _col.where('uid', isEqualTo: uid).limit(limit).snapshots().map((snap) {
      final items = snap.docs
          .map((d) => AiLesson.fromMap(d.data(), d.id))
          .toList();
      items.sort((a, b) {
        final at = a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return items;
    });
  }

  Stream<AiLesson?> watch(String id) {
    return doc(id).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return AiLesson.fromMap(snap.data()!, snap.id);
    });
  }

  Stream<List<AiLesson>> watchAll({int limit = 80}) {
    return _col.limit(limit).snapshots().map((snap) {
      final items = snap.docs
          .map((d) => AiLesson.fromMap(d.data(), d.id))
          .toList();
      items.sort((a, b) {
        final at = a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return items;
    });
  }

  Future<AiLesson?> get(String id) async {
    final snap = await doc(id).get();
    if (!snap.exists || snap.data() == null) return null;
    return AiLesson.fromMap(snap.data()!, snap.id);
  }

  Future<String> enqueue({
    required String uid,
    required String topic,
    String chapterId = '',
    String subjectId = '',
    String subjectTitle = '',
    String examId = '',
    String targetGroup = '',
    String topicId = '',
    bool forceRegenerate = false,
  }) async {
    final id = docIdFor(uid: uid, topic: topic);
    final existing = await get(id);
    if (!forceRegenerate && existing != null && existing.isReady) {
      return id;
    }
    final now = DateTime.now();
    await doc(id).set({
      'uid': uid,
      'topic': topic.trim(),
      'chapterId': chapterId,
      'subjectId': subjectId,
      'subjectTitle': subjectTitle,
      if (examId.isNotEmpty) 'examId': examId,
      if (targetGroup.isNotEmpty) 'targetGroup': targetGroup,
      if (topicId.isNotEmpty) 'topicId': topicId,
      'status': AiLessonStatus.queued.wire,
      'stage': AiLessonStage.preparing.wire,
      'progress': 0,
      'script': existing?.script ?? <String>[],
      'pdfPath': existing?.pdfPath ?? '',
      'audioUrl': forceRegenerate ? '' : (existing?.audioUrl ?? ''),
      'videoUrl': forceRegenerate ? '' : (existing?.videoUrl ?? ''),
      'finalVideoUrl': forceRegenerate ? '' : (existing?.finalVideoUrl ?? ''),
      'thumbnailUrl': forceRegenerate ? '' : (existing?.thumbnailUrl ?? ''),
      'duration': existing?.duration ?? 0,
      'errorMessage': '',
      'friendlyMessage': 'धडा तयार होत आहे…',
      'playbackMode': AiLessonPlayback.educational.wire,
      'logs': <Map<String, dynamic>>[
        AiLessonLog(
          at: now,
          stage: AiLessonStage.preparing.wire,
          message: forceRegenerate ? 'Regenerate queued' : 'Queued',
        ).toMap(),
      ],
      'etaSeconds': AiLessonStage.preparing.etaSeconds,
      'createdAt': existing?.createdAt != null
          ? Timestamp.fromDate(existing!.createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return id;
  }

  Future<void> setPdfPath({required String id, required String pdfPath}) async {
    await doc(id).set({
      'pdfPath': pdfPath.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateProgress({
    required String id,
    required AiLessonStatus status,
    required AiLessonStage stage,
    required int progress,
    String friendlyMessage = '',
    String errorMessage = '',
    String logMessage = '',
  }) async {
    final patch = <String, dynamic>{
      'status': status.wire,
      'stage': stage.wire,
      'progress': progress.clamp(0, 100),
      'etaSeconds': stage.etaSeconds,
      'updatedAt': FieldValue.serverTimestamp(),
      if (friendlyMessage.isNotEmpty) 'friendlyMessage': friendlyMessage,
      if (errorMessage.isNotEmpty) 'errorMessage': errorMessage,
    };
    await doc(id).set(patch, SetOptions(merge: true));
    if (logMessage.trim().isNotEmpty) {
      await _appendLog(id, stage: stage.wire, message: logMessage.trim());
    }
  }

  Future<void> markReady({
    required String id,
    required GeneratedLesson lesson,
    required String audioUrl,
    required String videoUrl,
    required String thumbnailUrl,
    required double duration,
    required AiLessonPlayback playbackMode,
    String finalVideoUrl = '',
  }) async {
    final audio = audioUrl.trim();
    final video = videoUrl.trim();
    final finalUrl = finalVideoUrl.trim().isNotEmpty ? finalVideoUrl.trim() : video;
    if (audio.isEmpty || video.isEmpty) {
      throw StateError(
        'Cannot mark lesson ready without slides audio and final video',
      );
    }
    await doc(id).set({
      'status': AiLessonStatus.ready.wire,
      'stage': AiLessonStage.ready.wire,
      'progress': 100,
      'etaSeconds': 0,
      'script': lesson.script,
      'lesson': lesson.toMap(),
      'audioUrl': audio,
      'videoUrl': video,
      'finalVideoUrl': finalUrl,
      'thumbnailUrl': thumbnailUrl,
      'duration': duration,
      'playbackMode': playbackMode.wire,
      'friendlyMessage': 'Ready to play',
      'errorMessage': '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _appendLog(id, stage: 'ready', message: 'Lesson ready');
  }

  /// Attach a finished MP4 without interrupting a lesson that is already playing.
  Future<void> attachVideo({
    required String id,
    required String videoUrl,
    String finalVideoUrl = '',
  }) async {
    if (videoUrl.trim().isEmpty) return;
    await doc(id).set({
      'videoUrl': videoUrl.trim(),
      if (finalVideoUrl.trim().isNotEmpty) 'finalVideoUrl': finalVideoUrl.trim(),
      'playbackMode': AiLessonPlayback.video.wire,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _appendLog(id, stage: 'ready', message: 'MP4 attached');
  }

  Future<void> markFailed({
    required String id,
    required String technicalError,
  }) async {
    await doc(id).set({
      'status': AiLessonStatus.failed.wire,
      'progress': 0,
      'errorMessage': technicalError,
      'friendlyMessage': studentFacingLessonMessage(technicalError),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _appendLog(
      id,
      stage: 'failed',
      message: technicalError.length > 400
          ? technicalError.substring(0, 400)
          : technicalError,
    );
  }

  Future<void> _appendLog(
    String id, {
    required String stage,
    required String message,
  }) async {
    try {
      final snap = await doc(id).get();
      final current = (snap.data()?['logs'] as List?) ?? const [];
      final next = [
        ...current.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        AiLessonLog(at: DateTime.now(), stage: stage, message: message).toMap(),
      ];
      final trimmed = next.length > 24 ? next.sublist(next.length - 24) : next;
      await doc(id).set({'logs': trimmed}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> delete(String id) async {
    await doc(id).delete();
  }
}

final AiLessonRepository aiLessonRepository = AiLessonRepository();
