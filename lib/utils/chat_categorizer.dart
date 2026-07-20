import 'package:mpsc_combine_ai/models/chat_subject.dart';

/// Lightweight keyword-based classifier that auto-categorizes an AI Teacher
/// chat by MPSC syllabus subject, purely from the student's own text — no
/// extra AI call, no network round-trip, works instantly and offline-safe.
class ChatCategorizer {
  const ChatCategorizer._();

  static const Map<ChatSubject, List<String>> _keywords = {
    ChatSubject.polity: [
      'राज्यघटना', 'संविधान', 'संसद', 'राष्ट्रपती', 'उपराष्ट्रपती',
      'पंतप्रधान', 'मंत्रिमंडळ', 'न्यायालय', 'सर्वोच्च न्यायालय', 'मूलभूत हक्क',
      'मूलभूत कर्तव्ये', 'स्थानिक स्वराज्य', 'पंचायत', 'राज्यव्यवस्था',
      'constitution', 'parliament', 'president', 'governor', 'judiciary',
      'polity', 'panchayat', 'fundamental rights', 'directive principles',
      'supreme court', 'cabinet', 'legislature', 'governance',
    ],
    ChatSubject.economy: [
      'अर्थव्यवस्था', 'अर्थसंकल्प', 'चलन', 'महागाई', 'रिझर्व्ह बँक', 'बँकिंग',
      'सार्वजनिक वित्त', 'करप्रणाली', 'राष्ट्रीय उत्पन्न', 'बेरोजगारी', 'जीडीपी',
      'economy', 'budget', 'inflation', 'gdp', 'fiscal', 'taxation', 'rbi',
      'banking', 'monetary policy', 'poverty', 'unemployment', 'economic',
    ],
    ChatSubject.geography: [
      'भूगोल', 'नदी', 'पर्वत', 'हवामान', 'महासागर', 'मृदा', 'वातावरण',
      'भूरूप', 'खडक', 'लोकसंख्या', 'मानवी भूगोल',
      'geography', 'river', 'climate', 'monsoon', 'mountain', 'soil',
      'ocean', 'rainfall', 'population', 'physical features', 'terrain',
    ],
    ChatSubject.history: [
      'इतिहास', 'शिवाजी', 'मुघल', 'मराठा', 'स्वातंत्र्य', 'ब्रिटिश', 'साम्राज्य',
      'सिंधू संस्कृती', 'वैदिक', 'बौद्ध', 'जैन', 'मौर्य', 'गुप्त', 'उठाव',
      'history', 'independence', 'mughal', 'maratha', 'shivaji', 'british',
      'empire', 'freedom movement', 'revolt', 'ancient india', 'medieval',
    ],
    ChatSubject.science: [
      'विज्ञान', 'तंत्रज्ञान', 'संगणक', 'अवकाश', 'जीवशास्त्र', 'भौतिकशास्त्र',
      'रसायनशास्त्र', 'अनुवंश', 'जैवतंत्रज्ञान', 'कृत्रिम बुद्धिमत्ता', 'ऊर्जा',
      'science', 'technology', 'biology', 'physics', 'chemistry', 'computer',
      'space', 'isro', 'artificial intelligence', 'genetics', 'energy',
    ],
    ChatSubject.currentAffairs: [
      'चालू घडामोडी', 'बातम्या', 'योजना', 'सरकार', 'अलीकडील', 'शिखर परिषद',
      'current affairs', 'news', 'scheme', 'summit', 'recent', 'government',
      'appointment', 'award', 'report released', 'index',
    ],
    ChatSubject.csat: [
      'तर्कशक्ती', 'बुद्धिमत्ता', 'उतारा', 'आकलन', 'गणित', 'सी.सॅट',
      'csat', 'reasoning', 'aptitude', 'comprehension', 'data interpretation',
      'logical', 'quantitative', 'decision making', 'mental ability',
    ],
  };

  /// Returns the best-matching [ChatSubject] for [text], or
  /// [ChatSubject.general] when nothing matches confidently.
  static ChatSubject categorize(String text) {
    final normalized = text.toLowerCase();
    ChatSubject? best;
    var bestScore = 0;

    for (final entry in _keywords.entries) {
      var score = 0;
      for (final keyword in entry.value) {
        if (normalized.contains(keyword.toLowerCase())) {
          score++;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = entry.key;
      }
    }

    return best ?? ChatSubject.general;
  }
}
