// Live smoke: retrieve-rank + Gemini grounded answer + citation metadata.
//   dart run tool/rag_learn_live_smoke.dart
import 'dart:convert';
import 'dart:io';

import 'package:mpsc_combine_ai/rag/rag_vector.dart';
import 'rag_worker_ops.dart';

Future<void> main() async {
  final file = File('dart_defines.json');
  if (!file.existsSync()) {
    stderr.writeln('SKIP: dart_defines.json missing');
    exit(0);
  }
  final map = jsonDecode(file.readAsStringSync());
  final apiKey = '${map is Map ? map['AI_API_KEY'] ?? '' : ''}'.trim();
  final model =
      '${map is Map ? map['AI_MODEL'] ?? 'gemini-flash-lite-latest' : ''}';
  if (apiKey.isEmpty) {
    stderr.writeln('SKIP: AI_API_KEY missing');
    exit(0);
  }

  final ops = RagWorkerOps(apiKey: apiKey, model: model);
  const chunks = [
    {
      'index': 0,
      'subject': 'Polity',
      'chapter': 'Fundamental Rights',
      'topic': 'Article 32',
      'pageNumber': 24,
      'text':
          'भारतीय संविधानातील मूलभूत अधिकार न्याय्य आहेत. कलम ३२ संवैधानिक उपाय देते.',
    },
    {
      'index': 1,
      'subject': 'Geography',
      'chapter': 'मान्सून',
      'topic': 'Indian Climate',
      'pageNumber': 8,
      'text': 'मान्सून हा भारताच्या हवामानाचा मुख्य आधार आहे.',
    },
  ];

  stdout.writeln('1) Embedding ranking (retrieval)…');
  final docs = [
    '${chunks[0]['text']}',
    '${chunks[1]['text']}',
  ];
  final docVecs =
      (await ops.embed(texts: docs, task: 'document'))['embeddings']
          as List<List<double>>;
  final qVecs = (await ops.embed(
    texts: const ['मूलभूत अधिकार'],
    task: 'query',
  ))['embeddings'] as List<List<double>>;
  final s0 = cosineSimilarity(qVecs.first, docVecs[0]);
  final s1 = cosineSimilarity(qVecs.first, docVecs[1]);
  stdout.writeln('cosine(rights)=$s0 cosine(monsoon)=$s1');
  if (s0 <= s1) {
    stderr.writeln('FAIL: RAG retrieval ranking');
    exit(1);
  }

  stdout.writeln('2) Gemini grounded answer…');
  final learned = await ops.learn(
    mode: 'answer',
    question: 'मूलभूत अधिकार सोप्या भाषेत समजावून सांग.',
    chunks: chunks,
    teachingStyle:
        'POLITY: Constitution, Articles, institutions, and comparisons.',
  );
  final insufficient = learned['insufficient'] == true;
  final answer = '${learned['answer'] ?? ''}'.trim();
  stdout.writeln('insufficient=$insufficient answerChars=${answer.length}');
  if (insufficient || answer.isEmpty) {
    stderr.writeln('FAIL: Gemini produced no grounded answer');
    exit(1);
  }

  stdout.writeln('3) Citations from chunk metadata (never Gemini pages)…');
  final indexes = <int>[];
  final raw = learned['chunkIndexes'];
  if (raw is List) {
    for (final e in raw) {
      if (e is num) indexes.add(e.toInt());
    }
  }
  final used = indexes.isEmpty ? <int>[0] : indexes;
  if (used.any((i) => i < 0 || i >= chunks.length)) {
    stderr.writeln('FAIL: invalid chunkIndexes $used');
    exit(1);
  }
  final citation = chunks[used.first];
  if (citation['pageNumber'] != 24 || citation['subject'] != 'Polity') {
    stderr.writeln('FAIL: citation metadata mismatch $citation');
    exit(1);
  }
  stdout.writeln(
    '📚 ${citation['subject']} → ${citation['chapter']} → ${citation['topic']} → Page ${citation['pageNumber']}',
  );

  stdout.writeln('4) Insufficient evidence when chunks are empty…');
  final empty = await ops.learn(
    mode: 'answer',
    question: 'मूलभूत अधिकार',
    chunks: const [],
  );
  if (empty['insufficient'] != true) {
    stderr.writeln('FAIL: empty chunks should be insufficient');
    exit(1);
  }

  stdout.writeln('5) Topic ranking: History / Geography / Economics…');
  const extraDocs = [
    '१८५७ चा उठाव हा भारतातील पहिला स्वातंत्र्यसंग्राम मानला जातो. कारणे, घटना आणि परिणाम.',
    'मान्सून हा भारताच्या हवामानाचा मुख्य आधार आहे. नैऋत्य मान्सून.',
    'महागाई म्हणजे वस्तू आणि सेवांच्या सामान्य किंमत पातळीत सतत वाढ.',
  ];
  const extraQueries = ['1857 चा उठाव', 'मान्सून', 'महागाई'];
  final extraVecs =
      (await ops.embed(texts: extraDocs, task: 'document'))['embeddings']
          as List<List<double>>;
  for (var i = 0; i < extraQueries.length; i++) {
    final qv = (await ops.embed(
      texts: [extraQueries[i]],
      task: 'query',
    ))['embeddings'] as List<List<double>>;
    var best = 0;
    var bestScore = -2.0;
    for (var j = 0; j < extraVecs.length; j++) {
      final s = cosineSimilarity(qv.first, extraVecs[j]);
      if (s > bestScore) {
        bestScore = s;
        best = j;
      }
    }
    stdout.writeln('  ${extraQueries[i]} → doc[$best] score=$bestScore');
    if (best != i) {
      stderr.writeln('FAIL: ${extraQueries[i]} ranked doc $best');
      exit(1);
    }
  }

  stdout.writeln('6) Grounded MCQ from polity chunk…');
  final mcq = await ops.learn(
    mode: 'mcq',
    question: 'मूलभूत अधिकार',
    chunks: [chunks[0]],
  );
  final questions = mcq['questions'];
  if (mcq['insufficient'] == true || questions is! List || questions.isEmpty) {
    stderr.writeln('FAIL: MCQ generator');
    exit(1);
  }

  stdout.writeln('PASS: retrieve → Gemini → answer → citation');
}
