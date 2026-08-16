import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:share_plus/share_plus.dart';

/// Builds exam-ready notes text and shares it (Save / Print-to-PDF on device).
String verifiedNotesExportText(GeneratedLesson lesson) {
  final p = lesson.premium;
  final buf = StringBuffer()
    ..writeln('MPSC COMBINE AI — परीक्षा नोट्स')
    ..writeln(lesson.topicName)
    ..writeln(lesson.subjectName)
    ..writeln('');
  void section(String title, String body) {
    if (body.trim().isEmpty) return;
    buf
      ..writeln('== $title ==')
      ..writeln(body.trim())
      ..writeln('');
  }

  void bullets(String title, List<String> items) {
    if (items.isEmpty) return;
    buf.writeln('== $title ==');
    for (final i in items) {
      buf.writeln('• ${i.trim()}');
    }
    buf.writeln('');
  }

  section('परिचय', p.introduction.isNotEmpty ? p.introduction : lesson.summary);
  bullets('मुख्य संकल्पना', p.mainConcepts);
  bullets('महत्त्वाची तथ्ये', p.importantFacts);
  section('MPSC फॅक्ट बॉक्स', p.factBox);
  section('मागील वर्षांचा संबंध', p.pyqConnection);
  bullets('पुनरावृत्ती मुद्दे', lesson.notes);
  bullets('स्मरण युक्त्या', p.memoryTricks);
  bullets('परीक्षा सापळे', p.examTraps);
  section('एक-पृष्ठ सारांश', p.onePageSummary);
  return buf.toString().trim();
}

Future<void> exportVerifiedNotes(GeneratedLesson lesson) {
  return SharePlus.instance.share(
    ShareParams(
      text: verifiedNotesExportText(lesson),
      subject: '${lesson.topicName} — MPSC नोट्स',
    ),
  );
}
