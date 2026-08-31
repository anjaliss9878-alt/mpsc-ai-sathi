// Live smoke: Gemini embed + cosine retrieval (no Firestore).
//   dart run tool/rag_live_smoke.dart
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
  final model = '${map is Map ? map['AI_MODEL'] ?? 'gemini-flash-lite-latest' : ''}';
  if (apiKey.isEmpty) {
    stderr.writeln('SKIP: AI_API_KEY missing');
    exit(0);
  }

  final ops = RagWorkerOps(apiKey: apiKey, model: model);
  const docs = [
    'भारतीय संसद द्विसदनी आहे. लोकसभा आणि राज्यसभा.',
    'मान्सून हा भारताच्या हवामानाचा मुख्य आधार आहे.',
  ];
  stdout.writeln('Embedding 2 documents + 1 query via Gemini gemini-embedding-001…');
  final docVecs = (await ops.embed(texts: docs, task: 'document'))['embeddings']
      as List<List<double>>;
  final queryVecs = (await ops.embed(
    texts: const ['संसद लोकसभा रचना'],
    task: 'query',
  ))['embeddings'] as List<List<double>>;
  final q = queryVecs.first;
  final s0 = cosineSimilarity(q, docVecs[0]);
  final s1 = cosineSimilarity(q, docVecs[1]);
  stdout.writeln('cosine(संसद query, संसद chunk)=$s0');
  stdout.writeln('cosine(संसद query, मान्सून chunk)=$s1');
  if (s0 <= s1) {
    stderr.writeln('FAIL: parliament query should rank parliament chunk higher');
    exit(1);
  }
  stdout.writeln('PASS: live Gemini embedding retrieval ranking is correct');
}
