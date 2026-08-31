import 'package:mpsc_combine_ai/models/rag_citation.dart';
import 'package:mpsc_combine_ai/models/rag_study_pack.dart';

/// Retrieval / answer confidence for grounded student responses.
enum RagConfidenceBand { high, medium, low }

const double kRagHighConfidenceMin = 0.70;
const double kRagMediumConfidenceMin = 0.40;

const String kRagMediumConfidencePrefix =
    'खालील उत्तर उपलब्ध स्रोतांवर आधारित आहे (मध्यम विश्वास).\n'
    '(Based on the retrieved sources — medium confidence.)';

RagConfidenceBand ragConfidenceBand(double score) {
  if (score >= kRagHighConfidenceMin) return RagConfidenceBand.high;
  if (score >= kRagMediumConfidenceMin) return RagConfidenceBand.medium;
  return RagConfidenceBand.low;
}

String ragConfidenceBandToString(RagConfidenceBand band) {
  switch (band) {
    case RagConfidenceBand.high:
      return 'high';
    case RagConfidenceBand.medium:
      return 'medium';
    case RagConfidenceBand.low:
      return 'low';
  }
}

/// High → unchanged. Medium → keep answer and mark sources. Low → refuse.
RagTeacherAnswer applyRagConfidence({
  required RagTeacherAnswer answer,
  required double confidence,
}) {
  final band = ragConfidenceBand(confidence);
  if (answer.insufficient || band == RagConfidenceBand.low) {
    return RagTeacherAnswer(
      markdown: kRagInsufficientEvidence,
      citations: const [],
      insufficient: true,
      confidence: confidence,
    );
  }
  if (band == RagConfidenceBand.medium) {
    final body = answer.markdown.trim();
    final prefixed = body.startsWith(kRagMediumConfidencePrefix)
        ? body
        : '$kRagMediumConfidencePrefix\n\n$body';
    return RagTeacherAnswer(
      markdown: prefixed,
      citations: answer.citations,
      insufficient: false,
      confidence: confidence,
    );
  }
  return RagTeacherAnswer(
    markdown: answer.markdown,
    citations: answer.citations,
    insufficient: false,
    confidence: confidence,
  );
}
