import 'package:flutter/material.dart';

class SubjectNotesData {
  const SubjectNotesData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.topics,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> topics;
}

const subjectNotesCatalog = <SubjectNotesData>[
  SubjectNotesData(
    id: 'polity',
    title: 'भारतीय राज्यव्यवस्था',
    subtitle: '13 अध्याय — Polity & Governance',
    icon: Icons.account_balance_rounded,
    topics: [
      'भारतीय राज्यघटना : ऐतिहासिक पार्श्वभूमी',
      'संविधान सभा',
      'संविधानाची वैशिष्ट्ये',
      'उद्देशिका',
      'मूलभूत हक्क',
      'राज्याच्या धोरणाची मार्गदर्शक तत्त्वे',
      'मूलभूत कर्तव्ये',
      'संसद',
      'राष्ट्रपती आणि उपराष्ट्रपती',
      'पंतप्रधान आणि मंत्रिमंडळ',
      'सर्वोच्च न्यायालय',
      'राज्य शासन',
      'स्थानिक स्वराज्य संस्था',
    ],
  ),
  SubjectNotesData(
    id: 'economy',
    title: 'भारतीय अर्थव्यवस्था',
    subtitle: '12 अध्याय — Economy & Development',
    icon: Icons.trending_up_rounded,
    topics: [
      'अर्थव्यवस्थेची मूलभूत संकल्पना',
      'राष्ट्रीय उत्पन्न',
      'आर्थिक नियोजन',
      'चलन आणि महागाई',
      'भारतीय रिझर्व्ह बँक',
      'बँकिंग व्यवस्था',
      'सार्वजनिक वित्त',
      'केंद्रीय अर्थसंकल्प',
      'करप्रणाली',
      'शेती आणि ग्रामीण अर्थव्यवस्था',
      'उद्योग आणि पायाभूत सुविधा',
      'बेरोजगारी आणि दारिद्र्य',
    ],
  ),
  SubjectNotesData(
    id: 'geography',
    title: 'भूगोल',
    subtitle: '12 अध्याय — Indian & World Geography',
    icon: Icons.public_rounded,
    topics: [
      'पृथ्वी आणि विश्व',
      'पृथ्वीची अंतर्गत रचना',
      'खडक आणि भूरूपे',
      'वातावरण',
      'हवामान',
      'महासागर',
      'भारताचा भौतिक भूगोल',
      'भारतातील नद्या',
      'भारताचे हवामान',
      'मृदा आणि नैसर्गिक वनस्पती',
      'महाराष्ट्राचा भूगोल',
      'लोकसंख्या आणि मानवी भूगोल',
    ],
  ),
  SubjectNotesData(
    id: 'history',
    title: 'इतिहास',
    subtitle: '14 अध्याय — Ancient, Medieval & Modern',
    icon: Icons.history_rounded,
    topics: [
      'सिंधू संस्कृती',
      'वैदिक संस्कृती',
      'बौद्ध धर्म',
      'जैन धर्म',
      'मौर्य साम्राज्य',
      'गुप्त साम्राज्य',
      'दिल्ली सल्तनत',
      'मुघल साम्राज्य',
      'मराठा साम्राज्य',
      'छत्रपती शिवाजी महाराज',
      'ब्रिटिश सत्तेचा उदय',
      '1857 चा उठाव',
      'भारतीय राष्ट्रीय चळवळ',
      'महाराष्ट्रातील समाजसुधारक',
    ],
  ),
  SubjectNotesData(
    id: 'science',
    title: 'विज्ञान आणि तंत्रज्ञान',
    subtitle: '12 अध्याय — Science & Technology',
    icon: Icons.science_rounded,
    topics: [
      'भौतिकशास्त्र',
      'रसायनशास्त्र',
      'जीवशास्त्र',
      'मानवी शरीर',
      'आरोग्य आणि रोग',
      'अनुवंशशास्त्र',
      'जैवतंत्रज्ञान',
      'अवकाश तंत्रज्ञान',
      'माहिती तंत्रज्ञान',
      'कृत्रिम बुद्धिमत्ता',
      'ऊर्जा',
      'पर्यावरण विज्ञान',
    ],
  ),
];

SubjectNotesData subjectById(String id) {
  return subjectNotesCatalog.firstWhere((subject) => subject.id == id);
}
