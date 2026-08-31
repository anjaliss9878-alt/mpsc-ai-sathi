import 'package:mpsc_combine_ai/rag/rag_domain.dart';

/// Optional hints from the calling surface (never required).
///
/// [fromAiTeacher] is set by the existing AI Teacher classroom / chat so
/// topic queries search [RagDomain.aiTeacher] without changing that UI.
class RagRouteContext {
  const RagRouteContext({
    this.fromAiTeacher = false,
    this.examId = '',
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
    this.topicTitle = '',
  });

  final bool fromAiTeacher;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final String topicTitle;
}

/// Router output: which existing RAG domains to search, plus confidence.
class RagRoutePlan {
  const RagRoutePlan({
    required this.domains,
    required this.confidence,
    this.reason = '',
    this.examId = '',
    this.subjectId = '',
    this.chapterId = '',
    this.topicId = '',
  });

  final List<RagDomain> domains;
  final double confidence;
  final String reason;
  final String examId;
  final String subjectId;
  final String chapterId;
  final String topicId;

  bool get isEmpty => domains.isEmpty;
}

/// Deterministic intent router. Does not call a model and does not write
/// documents — it only chooses metadata filters for the existing corpus.
class RagRouter {
  const RagRouter();

  RagRoutePlan route(String query, {RagRouteContext context = const RagRouteContext()}) {
    final q = query.trim();
    if (q.isEmpty && !context.fromAiTeacher) {
      return const RagRoutePlan(
        domains: [],
        confidence: 0,
        reason: 'empty_query',
      );
    }

    final lower = q.toLowerCase();
    final intents = <_Intent>[];

    if (_isWeakness(lower)) {
      intents.add(
        const _Intent(
          domains: [RagDomain.studentPerformance, RagDomain.notes],
          confidence: 0.93,
          reason: 'weak_topics',
        ),
      );
    }
    if (_isCurrentAffairs(lower)) {
      intents.add(
        const _Intent(
          domains: [RagDomain.currentAffairs],
          confidence: 0.92,
          reason: 'current_affairs',
        ),
      );
    }
    if (_isPyq(lower)) {
      intents.add(
        const _Intent(
          domains: [RagDomain.pyq, RagDomain.notes],
          confidence: 0.91,
          reason: 'pyq',
        ),
      );
    }
    if (context.fromAiTeacher || _isAiTeacher(lower)) {
      intents.add(
        _Intent(
          domains: const [RagDomain.aiTeacher, RagDomain.notes],
          confidence: context.fromAiTeacher ? 0.94 : 0.86,
          reason: 'ai_teacher',
        ),
      );
    }
    if (_isExplainOrSyllabus(lower) &&
        !_isPyq(lower) &&
        !_isCurrentAffairs(lower) &&
        !_isWeakness(lower) &&
        !context.fromAiTeacher &&
        !_isAiTeacher(lower)) {
      intents.add(
        const _Intent(
          domains: [RagDomain.notes, RagDomain.syllabus],
          confidence: 0.88,
          reason: 'explain_notes_syllabus',
        ),
      );
    }

    if (intents.isEmpty) {
      if (context.fromAiTeacher) {
        return RagRoutePlan(
          domains: const [RagDomain.aiTeacher, RagDomain.notes],
          confidence: 0.9,
          reason: 'ai_teacher_context',
          examId: context.examId,
          subjectId: context.subjectId,
          chapterId: context.chapterId,
          topicId: context.topicId,
        );
      }
      return RagRoutePlan(
        domains: const [RagDomain.notes, RagDomain.syllabus],
        confidence: 0.52,
        reason: 'default_study',
        examId: context.examId,
        subjectId: context.subjectId,
        chapterId: context.chapterId,
        topicId: context.topicId,
      );
    }

    final seen = <RagDomain>{};
    final domains = <RagDomain>[];
    var confidence = 0.0;
    final reasons = <String>[];
    for (final intent in intents) {
      for (final d in intent.domains) {
        if (seen.add(d)) domains.add(d);
      }
      if (intent.confidence > confidence) confidence = intent.confidence;
      reasons.add(intent.reason);
    }
    if (intents.length > 1) {
      confidence = (confidence + 0.04).clamp(0.0, 0.98);
    }

    return RagRoutePlan(
      domains: domains,
      confidence: confidence,
      reason: reasons.join('+'),
      examId: context.examId,
      subjectId: context.subjectId,
      chapterId: context.chapterId,
      topicId: context.topicId,
    );
  }

  static bool _isWeakness(String q) {
    return _any(q, const [
      'weak topic',
      'weak topics',
      'my weak',
      'weakness',
      'kacha',
      'कमकुवत',
      'कच्चे',
      'कच्चा',
      'माझे कच्चे',
      'माझे कमकुवत',
      'weak area',
    ]);
  }

  static bool _isCurrentAffairs(String q) {
    return _any(q, const [
      'current affairs',
      'current affair',
      'currentaffairs',
      'चालू घडामोडी',
      'चालूघडामोडी',
      'करंट अफेयर्स',
      'करंट अफेअर्स',
      'चालू घटना',
    ]);
  }

  static bool _isPyq(String q) {
    return _any(q, const [
      'pyq',
      'pyqs',
      'previous year',
      'previous years',
      'past paper',
      'past papers',
      'मागील वर्ष',
      'मागील प्रश्न',
      'प्रश्नपत्रिका',
      'पूर्व प्रश्न',
    ]);
  }

  static bool _isAiTeacher(String q) {
    return _any(q, const [
      'ai teacher',
      'ai-teacher',
      'classroom lesson',
      'this lesson',
      'व्याख्यान',
      'एआय टीचर',
    ]);
  }

  static bool _isExplainOrSyllabus(String q) {
    return _any(q, const [
      'explain',
      'explanation',
      'what is',
      'what are',
      'notes',
      'syllabus',
      'meaning',
      'define',
      'स्पष्ट',
      'समजाव',
      'अभ्यासक्रम',
      'नोंदी',
      'नोट्स',
    ]);
  }

  static bool _any(String q, List<String> needles) {
    for (final n in needles) {
      if (q.contains(n.toLowerCase())) return true;
    }
    return false;
  }
}

class _Intent {
  const _Intent({
    required this.domains,
    required this.confidence,
    required this.reason,
  });

  final List<RagDomain> domains;
  final double confidence;
  final String reason;
}

const RagRouter ragRouter = RagRouter();

/// True when the student is asking about their own weak topics / performance.
bool ragQueryIsWeakness(String query) =>
    RagRouter._isWeakness(query.trim().toLowerCase());
