import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import '../tts_io_stub.dart' if (dart.library.io) '../tts_io_impl.dart' as tts_io;

/// Local + Firestore cache for generated classroom lessons.
/// Miss simply regenerates. Never blocks teaching on cache errors.
class LessonCacheService {
  LessonCacheService._();

  static final LessonCacheService instance = LessonCacheService._();

  final Map<String, GeneratedLesson> _memory = {};

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('ai_cache');

  String keyFor({
    required String question,
    String chapterId = '',
    String subjectId = '',
  }) {
    final material =
        '${chapterId.trim()}|${subjectId.trim()}|${question.trim().toLowerCase()}';
    return sha256.convert(utf8.encode(material)).toString().substring(0, 32);
  }

  Future<GeneratedLesson?> read(String cacheKey) async {
    final hit = _memory[cacheKey];
    if (hit != null) return hit;
    try {
      final snap = await _col.doc(cacheKey).get();
      final data = snap.data();
      if (snap.exists && data != null) {
        final lesson = GeneratedLesson.fromMap(
          data,
          data['id'] as String? ?? cacheKey,
        );
        if (lesson.slides.length >= 6) {
          _memory[cacheKey] = lesson;
          return lesson;
        }
      }
    } catch (e) {
      debugPrint('[LessonCache] firestore read skip: $e');
    }
    if (kIsWeb) return null;
    try {
      final file = await tts_io.readTtsCacheFile('lesson_$cacheKey', ext: 'json');
      if (file == null) {
        final legacy = await tts_io.readTtsCacheFile('lesson_$cacheKey');
        if (legacy == null) return null;
        final text = utf8.decode(legacy.bytes);
        final map = jsonDecode(text) as Map<String, dynamic>;
        final lesson =
            GeneratedLesson.fromMap(map, map['id'] as String? ?? cacheKey);
        _memory[cacheKey] = lesson;
        return lesson;
      }
      final text = utf8.decode(file.bytes);
      final map = jsonDecode(text) as Map<String, dynamic>;
      final lesson =
          GeneratedLesson.fromMap(map, map['id'] as String? ?? cacheKey);
      _memory[cacheKey] = lesson;
      return lesson;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String cacheKey, GeneratedLesson lesson) async {
    _memory[cacheKey] = lesson;
    final payload = {
      ...lesson.toMap(),
      'id': lesson.id.isNotEmpty ? lesson.id : cacheKey,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      await _col.doc(cacheKey).set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[LessonCache] firestore write skip: $e');
    }
    if (kIsWeb) return;
    try {
      await tts_io.writeTtsCacheFile(
        'lesson_$cacheKey',
        utf8.encode(jsonEncode({
          ...lesson.toMap(),
          'id': lesson.id.isNotEmpty ? lesson.id : cacheKey,
        })),
        ext: 'json',
      );
    } catch (_) {}
  }
}

final LessonCacheService lessonCacheService = LessonCacheService.instance;
