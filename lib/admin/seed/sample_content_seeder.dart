import 'package:mpsc_combine_ai/data/polity_notes_data.dart';
import 'package:mpsc_combine_ai/data/subject_notes_data.dart';
import 'package:mpsc_combine_ai/models/chapter_item.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';
import 'package:mpsc_combine_ai/models/live_class_item.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/models/subject_item.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';
import 'package:mpsc_combine_ai/models/video_item.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/live_class_repository.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/test_repository.dart';
import 'package:mpsc_combine_ai/services/video_repository.dart';

/// One-time helper, triggered from the Admin Dashboard, that seeds a
/// starter example into every empty content collection so neither the
/// student app nor this dashboard looks empty on a fresh Firebase project.
///
/// Safe to run multiple times: each collection is skipped if it already
/// has at least one document.
Future<String> seedSampleContent() async {
  final results = <String>[];

  // ── Subjects, chapters & one full note (from the original hardcoded
  // catalog, so the seeded content matches what the app used to ship
  // with before it moved to Firestore). ──────────────────────────────
  final existingSubjects = await notesRepository.watchSubjects().first;
  if (existingSubjects.isEmpty) {
    for (var i = 0; i < subjectNotesCatalog.length; i++) {
      final subject = subjectNotesCatalog[i];
      final subjectId = await notesRepository.addSubject(
        SubjectItem(
          id: '',
          title: subject.title,
          subtitle: subject.subtitle,
          iconName: _iconNameFor(subject.title),
          order: i,
        ),
      );
      for (var j = 0; j < subject.topics.length; j++) {
        final chapterId = await notesRepository.addChapter(
          ChapterItem(id: '', subjectId: subjectId, title: subject.topics[j], order: j),
        );
        if (subject.id == 'polity' && j == 0) {
          await notesRepository.saveNote(
            subjectId: subjectId,
            chapterId: chapterId,
            importantPoints: chapter1PolityNotes.importantPoints,
            revisionSummary: chapter1PolityNotes.revisionSummary,
          );
        }
      }
    }
    results.add('Subjects/Chapters/Notes');
  }

  // ── MCQs ────────────────────────────────────────────────────────────
  final existingMcqs = await mcqRepository.watchAll().first;
  if (existingMcqs.isEmpty) {
    const sample = [
      McqItem(
        id: '',
        setTitle: 'Polity MCQs — Set 1',
        subject: 'Polity',
        difficulty: 'Medium',
        question: 'भारतीय संविधान कधी अंमलात आले?',
        options: ['15 ऑगस्ट 1947', '26 नोव्हेंबर 1949', '26 जानेवारी 1950', '2 ऑक्टोबर 1950'],
        correctIndex: 2,
        explanation: 'भारतीय संविधान 26 जानेवारी 1950 रोजी अंमलात आले.',
        order: 0,
      ),
      McqItem(
        id: '',
        setTitle: 'Polity MCQs — Set 1',
        subject: 'Polity',
        difficulty: 'Easy',
        question: 'भारतीय संविधानाचे शिल्पकार कोण?',
        options: ['महात्मा गांधी', 'डॉ. बाबासाहेब आंबेडकर', 'जवाहरलाल नेहरू', 'राजेंद्र प्रसाद'],
        correctIndex: 1,
        explanation: 'डॉ. बाबासाहेब आंबेडकर मसुदा समितीचे अध्यक्ष होते.',
        order: 1,
      ),
      McqItem(
        id: '',
        setTitle: 'Economy MCQs — Set 1',
        subject: 'Economy',
        difficulty: 'Medium',
        question: 'भारतीय रिझर्व्ह बँकेची स्थापना कोणत्या वर्षी झाली?',
        options: ['1935', '1947', '1950', '1969'],
        correctIndex: 0,
        explanation: 'RBI ची स्थापना 1 एप्रिल 1935 रोजी झाली.',
        order: 0,
      ),
    ];
    for (final mcq in sample) {
      await mcqRepository.add(mcq);
    }
    results.add('MCQs');
  }

  // ── Tests (Mock Tests / CBT) ────────────────────────────────────────
  final existingTests = await testRepository.watchAll().first;
  if (existingTests.isEmpty) {
    await testRepository.add(
      TestItem(
        id: '',
        title: 'Full Mock Test #1',
        subtitle: '5 Q • 10 min • All Subjects',
        durationSeconds: 600,
        correctMarks: 2.0,
        negativeMarks: 0.5,
        order: 0,
        questions: const [
          TestQuestion(
            question: 'भारतीय संविधान कधी स्वीकारण्यात आले?',
            options: ['15 ऑगस्ट 1947', '26 नोव्हेंबर 1949', '26 जानेवारी 1950', '9 डिसेंबर 1946'],
            correctIndex: 1,
            explanation: 'भारतीय संविधान सभेने 26 नोव्हेंबर 1949 रोजी संविधान स्वीकारले.',
          ),
          TestQuestion(
            question: 'भारतीय संविधानाचे शिल्पकार कोण?',
            options: ['महात्मा गांधी', 'डॉ. बाबासाहेब आंबेडकर', 'जवाहरलाल नेहरू', 'राजेंद्र प्रसाद'],
            correctIndex: 1,
            explanation: 'डॉ. बाबासाहेब आंबेडकर हे मसुदा समितीचे अध्यक्ष होते.',
          ),
          TestQuestion(
            question: 'भारतीय संविधान किती भागांमध्ये विभागले आहे?',
            options: ['18', '22', '25', '28'],
            correctIndex: 1,
            explanation: 'मूळ भारतीय संविधान 22 भागांमध्ये विभागले आहे.',
          ),
          TestQuestion(
            question: 'भारतीय संविधानाची प्रस्तावना कोणत्या शब्दांनी सुरू होते?',
            options: ['भारत माझा देश आहे', 'आम्ही भारताचे लोक', 'सत्यमेव जयते', 'जय हिंद'],
            correctIndex: 1,
            explanation: "प्रस्तावना 'आम्ही भारताचे लोक' या शब्दांनी सुरू होते.",
          ),
          TestQuestion(
            question: 'भारतीय संविधान अंमलात कधी आले?',
            options: ['15 ऑगस्ट 1947', '26 जानेवारी 1950', '26 नोव्हेंबर 1949', '2 ऑक्टोबर 1950'],
            correctIndex: 1,
            explanation: 'भारतीय संविधान 26 जानेवारी 1950 रोजी अंमलात आले — प्रजासत्ताक दिन.',
          ),
        ],
      ),
    );
    results.add('Tests');
  }

  // ── Current Affairs ─────────────────────────────────────────────────
  final existingCurrentAffairs = await currentAffairsRepository.watchAll().first;
  if (existingCurrentAffairs.isEmpty) {
    await currentAffairsRepository.add(
      CurrentAffairItem(
        id: '',
        title: "Today's Affairs — National & International",
        description:
            'Sample current affairs entry. Edit or delete this from the Admin Panel, '
            'and add your own daily updates here.',
        category: 'National',
        date: DateTime.now(),
      ),
    );
    results.add('Current Affairs');
  }

  // ── Videos ───────────────────────────────────────────────────────────
  final existingVideos = await videoRepository.watchAll().first;
  if (existingVideos.isEmpty) {
    await videoRepository.add(
      const VideoItem(
        id: '',
        title: 'Introduction to Indian Polity',
        subject: 'Polity',
        videoUrl: 'https://www.youtube.com/',
        description: 'Sample video entry — replace the link with your own lecture.',
      ),
    );
    results.add('Videos');
  }

  // ── Live Classes ─────────────────────────────────────────────────────
  final existingLiveClasses = await liveClassRepository.watchAll().first;
  if (existingLiveClasses.isEmpty) {
    await liveClassRepository.add(
      const LiveClassItem(
        id: '',
        title: 'आजचा लाइव्ह वर्ग — भारतीय राज्यव्यवस्था',
        subject: 'Polity',
        meetingUrl: 'https://meet.google.com/',
        platform: 'Google Meet',
        scheduleText: 'Today, 7:00 PM',
        status: 'upcoming',
      ),
    );
    results.add('Live Classes');
  }

  // ── PYQs ─────────────────────────────────────────────────────────────
  final existingPyqs = await pyqRepository.watchAll().first;
  if (existingPyqs.isEmpty) {
    await pyqRepository.add(
      const PyqItem(
        id: '',
        title: 'MPSC Combine 2025',
        subtitle: 'Prelims Paper — 100 questions',
        fileUrl: '',
        order: 0,
      ),
    );
    results.add('PYQs');
  }

  if (results.isEmpty) {
    return 'Every collection already has content — nothing to import.';
  }
  return 'Imported sample content for: ${results.join(', ')}.';
}

String _iconNameFor(String subjectTitle) {
  if (subjectTitle.contains('राज्यव्यवस्था')) return 'account_balance';
  if (subjectTitle.contains('अर्थव्यवस्था')) return 'trending_up';
  if (subjectTitle.contains('भूगोल')) return 'public';
  if (subjectTitle.contains('इतिहास')) return 'history';
  if (subjectTitle.contains('विज्ञान')) return 'science';
  return 'menu_book';
}
