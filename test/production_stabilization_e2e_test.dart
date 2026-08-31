import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/ai_lesson.dart';
import 'package:mpsc_combine_ai/models/exam_item.dart';
import 'package:mpsc_combine_ai/models/multi_rag_result.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_domain.dart';
import 'package:mpsc_combine_ai/services/google_cloud_tts_service.dart';
import 'package:mpsc_combine_ai/services/multi_rag_retrieval.dart';
import 'package:mpsc_combine_ai/services/rag_backend_client.dart';
import 'package:mpsc_combine_ai/services/rag_chunk_repository.dart';
import 'package:mpsc_combine_ai/services/rag_retrieval_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';
import 'package:mpsc_combine_ai/services/student_rag_context.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/utils/student_media.dart';

/// Local authenticated-path E2E for production stabilization contracts.
/// Does not call live Firebase/Netlify; those require deployed secrets.
void main() {
  test('Admin→Student RAG: unpublished is excluded; Student A ≠ Student B',
      () async {
    await expectLater(
      StudentRagContextService().load(uid: 'student-b', requesterUid: 'student-a'),
      throwsA(isA<StudentRagAccessException>()),
    );

    final backend = _HitsBackend(
      hits: [
        {
          'score': 0.9,
          'vectorScore': 0.9,
          'keywordScore': 0.4,
          'domain': 'notes_rag',
          'chunk': {
            'id': 'ok',
            'sourceId': 's1',
            'sourceTitle': 'Article 14',
            'subject': 'Polity',
            'subjectId': 'pol',
            'chapter': 'FR',
            'chapterId': 'fr',
            'topicId': 'a14',
            'contentType': 'notes_pdf',
            'examId': kDefaultExamId,
            'ragDomain': 'notes_rag',
            'text': 'Article 14 equality',
            'published': true,
            'language': 'en',
            'sourceType': 'pdf',
          },
        },
        {
          'score': 0.99,
          'vectorScore': 0.99,
          'keywordScore': 0.1,
          'domain': 'student_performance_rag',
          'chunk': {
            'id': 'b-secret',
            'sourceId': 'student_performance',
            'sourceTitle': 'Student B',
            'subject': '',
            'text': 'Student B secret weakness 12%',
            'published': true,
            'ragDomain': 'student_performance_rag',
            'contentType': 'student_performance',
            'sourceType': 'student_performance',
          },
        },
      ],
    );
    final retrieval = RagRetrievalService(
      sources: RagSourceRepository(firestore: FakeFirebaseFirestore()),
      chunks: RagChunkRepository(firestore: FakeFirebaseFirestore()),
      backend: backend,
    );
    final multi = MultiRagRetrievalService(retrieval: retrieval);
    final result = await multi.retrieve(
      const MultiRagQuery(
        query: 'Article 14',
        domains: [RagDomain.notes, RagDomain.studentPerformance],
        performance: [
          StudentPerformanceRecord(
            label: 'Student A weakness',
            topicId: 'a14',
            scorePercent: 20,
          ),
        ],
      ),
    );
    expect(result.hits.any((h) => h.chunk.text.contains('Student B')), isFalse);
    expect(
      result.hits.any((h) => h.chunk.text.contains('Student A weakness')),
      isTrue,
    );
  });

  test('Vertex/vector failure falls back without leaking URLs', () {
    final msg = studentFacingLessonMessage(
      'Gemini TTS failed HTTP 429 firebasestorage.googleapis.com/v0/b/x',
    );
    expect(msg.toLowerCase(), isNot(contains('http')));
    expect(msg.toLowerCase(), isNot(contains('firebase')));
    expect(msg, 'Retrying automatically');
    expect(
      studentFacingMediaError(
        'TypeError: Failed to fetch https://firebasestorage.googleapis.com/v0/b/x',
      ).toLowerCase(),
      isNot(contains('http')),
    );
  });

  test('TTS + welcome lesson + muxed-audio contract stay aligned', () {
    expect(GoogleCloudTtsService.defaultSpeakingRate, closeTo(0.9, 0.001));
    expect(GoogleCloudTtsService.defaultMarathiVoice, 'mr-IN-Wavenet-A');
    expect(welcomeLesson.slides.length, 8);
    expect(welcomeLesson.mcqs.length, 5);
    expect(welcomeLesson.premium.hasContent, isTrue);
    expect(RagSourceStatus.ready, isNot(RagSourceStatus.failed));
  });
}

class _HitsBackend extends RagBackendClient {
  _HitsBackend({required this.hits}) : super(baseUrl: 'http://rag.test');

  final List<Map<String, dynamic>> hits;

  @override
  Future<RagServerRetrieveResult?> retrieveChunks({
    required String query,
    String examId = '',
    String subjectId = '',
    String chapterId = '',
    String topicId = '',
    List<String> domains = const [],
    List<String> sourceIds = const [],
    int topK = 8,
    double similarityThreshold = 0.05,
    bool hybrid = true,
  }) async {
    return RagServerRetrieveResult(hits: hits);
  }
}
