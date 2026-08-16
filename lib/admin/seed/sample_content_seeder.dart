import 'package:mpsc_combine_ai/admin/seed/mpsc_curriculum_seeder.dart';
import 'package:mpsc_combine_ai/data/polity_notes_data.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';
import 'package:mpsc_combine_ai/models/faculty_item.dart';
import 'package:mpsc_combine_ai/models/live_class_item.dart';
import 'package:mpsc_combine_ai/models/mcq_item.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';
import 'package:mpsc_combine_ai/models/video_item.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/faculty_repository.dart';
import 'package:mpsc_combine_ai/services/live_class_repository.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/services/notes_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/test_repository.dart';
import 'package:mpsc_combine_ai/services/video_repository.dart';

/// Seeds the full MPSC subject/topic structure (idempotent by slug), then
/// fills empty sample collections (MCQ/Test/CA/…) so a fresh project is usable.
///
/// Safe to run multiple times.
Future<String> seedSampleContent() async {
  final results = <String>[];

  // ── Full MPSC curriculum (subjects + every topic) ───────────────────
  final curriculumSummary = await seedMpscCurriculumStructure();
  results.add(curriculumSummary);

  // Seed one sample polity note under the first राज्यशास्त्र topic if empty.
  try {
    final polity = await notesRepository.findSubjectBySlug('rajyashastra');
    if (polity != null) {
      final chapters = await notesRepository.getChaptersOnce(polity.id);
      if (chapters.isNotEmpty) {
        final first = chapters.first;
        final existingNote = await notesRepository.getNoteForChapter(first.id);
        if (existingNote == null) {
          await notesRepository.saveNote(
            subjectId: polity.id,
            chapterId: first.id,
            importantPoints: chapter1PolityNotes.importantPoints,
            revisionSummary: chapter1PolityNotes.revisionSummary,
            published: true,
          );
          results.add('Sample polity note');
        }
      }
    }
  } catch (_) {
    // Non-fatal — curriculum structure still imported.
  }

  // ── MCQs ────────────────────────────────────────────────────────────
  final existingMcqs = await mcqRepository.watchAll().first;
  if (existingMcqs.isEmpty) {
    const sample = [
      McqItem(
        id: '',
        setTitle: 'Polity MCQs — Set 1',
        subject: 'राज्यशास्त्र',
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
        subject: 'राज्यशास्त्र',
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
        subject: 'अर्थव्यवस्था',
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
        title: 'महाराष्ट्र शासन — प्रमुख योजना अद्यतने',
        description:
            'राज्यातील नवीन योजना, अंमलबजावणी स्थिती आणि परीक्षा-उपयुक्त आकडेवारीचा संक्षिप्त आढावा. '
            'Admin Panel मधून दैनिक अपडेट्स व मासिक PDF लिंक जोडा.',
        category: 'Maharashtra',
        date: DateTime.now(),
        quizQuestion: 'महाराष्ट्राची राजधानी कोणती?',
        quizOptions: const ['मुंबई', 'पुणे', 'नागपूर', 'नाशिक'],
        quizCorrectIndex: 0,
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
        subject: 'राज्यशास्त्र',
        videoUrl: 'https://www.youtube.com/',
        description: 'Sample video entry — replace the link with your own lecture.',
      ),
    );
    results.add('Videos');
  }

  // ── Faculty ──────────────────────────────────────────────────────────
  final existingFaculty = await facultyRepository.watchAll().first;
  late String sampleFacultyId;
  const sampleFacultyName = 'डॉ. संदीप पाटील';
  if (existingFaculty.isEmpty) {
    sampleFacultyId = await facultyRepository.add(
      const FacultyItem(
        id: '',
        name: sampleFacultyName,
        designation: 'MPSC Combine Expert Faculty',
        subject: 'राज्यशास्त्र',
        photoUrl: '',
        bio: 'Sample faculty entry — edit or delete this from Admin Panel → Faculty.',
      ),
    );
    results.add('Faculty');
  } else {
    sampleFacultyId = existingFaculty.first.id;
  }

  // ── Live Classes ─────────────────────────────────────────────────────
  final existingLiveClasses = await liveClassRepository.watchAll().first;
  if (existingLiveClasses.isEmpty) {
    await liveClassRepository.add(
      LiveClassItem(
        id: '',
        title: 'आजचा लाइव्ह वर्ग — भारतीय राज्यव्यवस्था',
        subject: 'राज्यशास्त्र',
        meetingUrl: 'https://meet.google.com/',
        platform: 'Google Meet',
        scheduleText: 'Today, 7:00 PM',
        status: 'upcoming',
        description:
            'Sample live class entry. Edit or delete this from the Admin Panel, '
            'and schedule your own classes here.',
        facultyId: sampleFacultyId,
        facultyName: existingFaculty.isEmpty ? sampleFacultyName : existingFaculty.first.name,
        scheduledAt: DateTime.now().add(const Duration(hours: 3)),
        durationMinutes: 60,
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
        title: 'MPSC Combine Prelims 2023 — Q1',
        subtitle: 'Polity · Medium',
        fileUrl: '',
        order: 0,
        year: 2023,
        examName: 'MPSC Combine Prelims',
        question:
            'भारतीय संविधानात मूलभूत हक्क कोणत्या भागात आहेत?',
        answer: 'भाग III',
        explanation:
            'मूलभूत हक्क भारतीय संविधानाच्या भाग III (अनुच्छेद 12–35) मध्ये नमूद आहेत.',
      ),
    );
    await pyqRepository.add(
      const PyqItem(
        id: '',
        title: 'MPSC Combine Prelims 2024 — Q1',
        subtitle: 'Economy · Easy',
        fileUrl: '',
        order: 1,
        year: 2024,
        examName: 'MPSC Combine Prelims',
        question: 'GST कधी लागू झाले?',
        answer: '1 जुलै 2017',
        explanation: 'वस्तू व सेवा कर (GST) भारतभर 1 जुलै 2017 पासून लागू झाले.',
      ),
    );
    results.add('PYQs');
  }

  if (results.length == 1) {
    return '${results.first} Other collections already had sample content.';
  }
  return results.join(' · ');
}
