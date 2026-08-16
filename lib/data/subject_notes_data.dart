import 'package:flutter/material.dart';

/// Canonical MPSC Combine curriculum entry (subject + topics).
///
/// [id] / [slug] are stable English keys used for idempotent Firestore seeding.
/// [title] is the Marathi display name shown in Admin + Student apps.
class SubjectNotesData {
  const SubjectNotesData({
    required this.id,
    required this.title,
    required this.titleEn,
    required this.subtitle,
    required this.icon,
    required this.topics,
  });

  final String id;
  final String title;
  final String titleEn;
  final String subtitle;
  final IconData icon;
  final List<String> topics;

  String get slug => id;
}

/// Full production curriculum: 10 subjects, every listed topic.
const subjectNotesCatalog = <SubjectNotesData>[
  SubjectNotesData(
    id: 'rajyashastra',
    title: 'राज्यशास्त्र',
    titleEn: 'Polity',
    subtitle: '२७ टॉपिक — भारतीय राज्यघटना व शासन',
    icon: Icons.account_balance_rounded,
    topics: [
      'भारतीय राज्यघटना',
      'राज्यघटनेची निर्मिती',
      'प्रस्तावना',
      'नागरिकत्व',
      'मूलभूत हक्क',
      'राज्याच्या मार्गदर्शक तत्त्वे',
      'मूलभूत कर्तव्ये',
      'राष्ट्रपती',
      'उपराष्ट्रपती',
      'पंतप्रधान',
      'मंत्रिमंडळ',
      'संसद',
      'सर्वोच्च न्यायालय',
      'उच्च न्यायालय',
      'राज्यपाल',
      'मुख्यमंत्री',
      'राज्य विधिमंडळ',
      'निवडणूक आयोग',
      'वित्त आयोग',
      'CAG',
      'आणीबाणी',
      'केंद्र-राज्य संबंध',
      'पंचायत राज',
      'महानगरपालिका',
      'माहितीचा अधिकार',
      'महाराष्ट्र लोकसेवा हमी अधिनियम',
      'महत्त्वाच्या घटनादुरुस्त्या',
    ],
  ),
  SubjectNotesData(
    id: 'bhugol',
    title: 'भूगोल',
    titleEn: 'Geography',
    subtitle: '२५ टॉपिक — भौतिक, भारत व महाराष्ट्र',
    icon: Icons.public_rounded,
    topics: [
      'पृथ्वी',
      'अक्षांश-रेखांश',
      'अंतर्गत रचना',
      'खडक',
      'ज्वालामुखी',
      'भूकंप',
      'हवामान',
      'मान्सून',
      'वातावरण',
      'नद्या',
      'पर्वत',
      'पठार',
      'मृदा',
      'खनिजे',
      'नैसर्गिक वनस्पती',
      'शेती',
      'उद्योग',
      'वाहतूक',
      'भारताचा भूगोल',
      'महाराष्ट्राचा भूगोल',
      'लोकसंख्या',
      'पर्यावरण',
      'आपत्ती व्यवस्थापन',
      'GIS',
      'Remote Sensing',
    ],
  ),
  SubjectNotesData(
    id: 'arthavyavastha',
    title: 'अर्थव्यवस्था',
    titleEn: 'Economy',
    subtitle: '१८ टॉपिक — अर्थव्यवस्था व विकास',
    icon: Icons.trending_up_rounded,
    topics: [
      'अर्थशास्त्राची मूलतत्त्वे',
      'राष्ट्रीय उत्पन्न',
      'GDP',
      'महागाई',
      'बँकिंग',
      'RBI',
      'बजेट',
      'करप्रणाली',
      'वित्तीय धोरण',
      'चलनविषयक धोरण',
      'शेती अर्थव्यवस्था',
      'उद्योग',
      'सेवा क्षेत्र',
      'गरिबी',
      'बेरोजगारी',
      'सार्वजनिक वित्त',
      'भारतीय अर्थव्यवस्था',
      'महाराष्ट्राची अर्थव्यवस्था',
    ],
  ),
  SubjectNotesData(
    id: 'itihas',
    title: 'इतिहास',
    titleEn: 'History',
    subtitle: '१७ टॉपिक — प्राचीन ते आधुनिक',
    icon: Icons.history_rounded,
    topics: [
      'प्राचीन भारत',
      'सिंधू संस्कृती',
      'वैदिक काळ',
      'महाजनपदे',
      'मौर्य साम्राज्य',
      'गुप्त साम्राज्य',
      'मध्ययुगीन भारत',
      'दिल्ली सल्तनत',
      'मुघल साम्राज्य',
      'मराठा साम्राज्य',
      'आधुनिक भारत',
      '१८५७ चा उठाव',
      'भारतीय राष्ट्रीय काँग्रेस',
      'स्वातंत्र्य चळवळ',
      'क्रांतिकारी चळवळ',
      'समाजसुधारक',
      'महाराष्ट्राचा इतिहास',
    ],
  ),
  SubjectNotesData(
    id: 'chalu_ghadamodi',
    title: 'चालू घडामोडी',
    titleEn: 'Current Affairs',
    subtitle: '११ टॉपिक — दैनिक / साप्ताहिक चौकट',
    icon: Icons.newspaper_rounded,
    topics: [
      'भारत',
      'महाराष्ट्र',
      'आंतरराष्ट्रीय',
      'अर्थव्यवस्था',
      'विज्ञान व तंत्रज्ञान',
      'पर्यावरण',
      'क्रीडा',
      'पुरस्कार',
      'नियुक्त्या',
      'शासकीय योजना',
      'अहवाल व निर्देशांक',
    ],
  ),
  SubjectNotesData(
    id: 'ankganit',
    title: 'अंकगणित',
    titleEn: 'Arithmetic',
    subtitle: '१० टॉपिक — संख्यात्मक क्षमता',
    icon: Icons.calculate_rounded,
    topics: [
      'संख्या पद्धती',
      'टक्केवारी',
      'गुणोत्तर',
      'सरासरी',
      'नफा-तोटा',
      'वेळ व काम',
      'वेळ-वेग-अंतर',
      'साधे व्याज',
      'चक्रवाढ व्याज',
      'Data Interpretation',
    ],
  ),
  SubjectNotesData(
    id: 'buddhibatta',
    title: 'बुद्धिमत्ता',
    titleEn: 'Reasoning',
    subtitle: '१० टॉपिक — तार्किक क्षमता',
    icon: Icons.psychology_rounded,
    topics: [
      'साम्य',
      'वर्गीकरण',
      'Coding-Decoding',
      'मालिका',
      'दिशा',
      'क्रमवारी',
      'रक्तसंबंध',
      'Syllogism',
      'Puzzle',
      'Statement & Conclusion',
    ],
  ),
  SubjectNotesData(
    id: 'samanya_vigyan',
    title: 'सामान्य विज्ञान',
    titleEn: 'General Science',
    subtitle: '११ टॉपिक — विज्ञान व तंत्रज्ञान',
    icon: Icons.science_rounded,
    topics: [
      'भौतिकशास्त्र',
      'रसायनशास्त्र',
      'जीवशास्त्र',
      'मानवी शरीर',
      'आरोग्य',
      'पोषण',
      'रोग',
      'पर्यावरण',
      'ICT',
      'आधुनिक तंत्रज्ञान',
      'अंतराळ विज्ञान',
    ],
  ),
  SubjectNotesData(
    id: 'marathi',
    title: 'मराठी',
    titleEn: 'Marathi',
    subtitle: '८ टॉपिक — भाषा व व्याकरण',
    icon: Icons.translate_rounded,
    topics: [
      'व्याकरण',
      'शब्दसंग्रह',
      'समानार्थी शब्द',
      'विरुद्धार्थी शब्द',
      'म्हणी',
      'वाक्प्रचार',
      'उतारा',
      'लेखन कौशल्य',
    ],
  ),
  SubjectNotesData(
    id: 'english',
    title: 'इंग्रजी',
    titleEn: 'English',
    subtitle: '७ टॉपिक — Grammar & comprehension',
    icon: Icons.menu_book_rounded,
    topics: [
      'Grammar',
      'Vocabulary',
      'Synonyms',
      'Antonyms',
      'Idioms',
      'Comprehension',
      'Sentence Correction',
    ],
  ),
];

SubjectNotesData subjectById(String id) {
  return subjectNotesCatalog.firstWhere((subject) => subject.id == id);
}

/// ASCII-ish slug fragment from a display title (empty when non-Latin only).
String slugFragment(String title) {
  return title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9\-]+'), '')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

/// Stable slug for a subject title (Admin create / seed fallback).
String subjectSlugFromTitle(String title) {
  final ascii = slugFragment(title);
  if (ascii.isNotEmpty) return ascii;
  final hash =
      title.codeUnits.fold<int>(0, (a, b) => ((a * 31) + b) & 0x7fffffff);
  return 'subject-$hash';
}

/// Stable slug for a topic title within a subject (unique per subject).
String topicSlug(String subjectSlug, String topicTitle, int order) {
  final ascii = slugFragment(topicTitle);
  if (ascii.isNotEmpty) {
    return '$subjectSlug-$ascii';
  }
  // Marathi / Devanagari titles: stable hash from title (order-independent).
  final hash =
      topicTitle.codeUnits.fold<int>(0, (a, b) => ((a * 31) + b) & 0x7fffffff);
  return '$subjectSlug-t$hash';
}

int get mpscCurriculumSubjectCount => subjectNotesCatalog.length;

int get mpscCurriculumTopicCount =>
    subjectNotesCatalog.fold<int>(0, (sum, s) => sum + s.topics.length);
