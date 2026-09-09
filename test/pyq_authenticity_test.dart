import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/models/rag_study_pack.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/utils/pyq_authenticity.dart';
import 'package:mpsc_combine_ai/widgets/rag_study_tool_sheets.dart';

void main() {
  test('genuine PYQ screen still reads published pyqs collection', () {
    final src = File('lib/screens/pyq_screen.dart').readAsStringSync();
    expect(src, contains('pyqRepository.watchPublished()'));
    expect(src, contains('Previous Year Questions'));
    expect(src, isNot(contains('pyqConnections')));
    expect(src, isNot(contains('RagVerifiedPyq')));
  });

  test('published PYQ visibility stays on the pyqs collection workflow', () {
    const published = PyqItem(
      id: 'real',
      title: 'Article 14',
      subtitle: '',
      fileUrl: '',
      order: 0,
      year: 2019,
      examName: 'MPSC Combine Group B',
      question: 'समतेचा अधिकार कोणत्या कलमात आहे?',
      published: true,
    );
    const draft = PyqItem(
      id: 'draft',
      title: 'Draft',
      subtitle: '',
      fileUrl: '',
      order: 1,
      question: 'AI invented?',
      published: false,
    );
    expect(published.isStudentVisible, isTrue);
    expect(draft.isStudentVisible, isFalse);

    final fake = FakeFirebaseFirestore();
    final repo = PyqRepository(firestore: fake);
    expect(repo, isNotNull);
  });

  test('Study Content and AI Teacher do not label RAG connections as PYQs', () {
    expect(
      File('lib/screens/study_content/study_content_screen.dart')
          .readAsStringSync(),
      contains('kAiPyqConnectionLabel'),
    );
    expect(
      File('lib/screens/study_content/study_content_screen.dart')
          .readAsStringSync()
          .contains("return 'PYQs'"),
      isFalse,
    );
    expect(
      File('lib/screens/ai_teacher_screen.dart').readAsStringSync(),
      contains('kAiPyqConnectionLabel'),
    );
    expect(
      File('lib/screens/ai_teacher_screen.dart')
          .readAsStringSync()
          .contains("title = 'PYQ'"),
      isFalse,
    );
    expect(
      File('lib/screens/ai_teacher_classroom/widgets/ai_lesson_studio.dart')
          .readAsStringSync(),
      contains('kAiPyqConnectionLabel'),
    );
    expect(
      File('lib/screens/ai_teacher_classroom/widgets/ai_lesson_studio.dart')
          .readAsStringSync()
          .contains("'PYQs'"),
      isFalse,
    );
    expect(kAiPyqConnectionLabel.toLowerCase(), isNot(equals('pyq')));
    expect(kAiPyqConnectionLabel.toLowerCase(), isNot(equals('pyqs')));
    expect(kAiPyqConnectionLabel, contains('AI-based PYQ Connections'));
    expect(kAiPyqConnectionDisclaimer, 'हे अधिकृत/मूळ PYQ नाहीत.');
  });

  testWidgets('RAG connections show the non-official disclaimer, not a PYQ year header',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RagPyqView(
            items: [
              RagVerifiedPyq(
                question: 'Syllabus connection text',
                answer: 'from notes',
                year: 2019,
                examName: 'Fake Official Paper',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text(kAiPyqConnectionDisclaimer), findsOneWidget);
    expect(find.text('Syllabus connection text'), findsOneWidget);
    expect(find.textContaining('2019'), findsNothing);
    expect(find.text('Fake Official Paper'), findsNothing);
    expect(find.text('PYQs'), findsNothing);
    expect(find.text('Previous Year Questions'), findsNothing);
  });
}
