import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Storage rules keep notes/RAG admin-write and students signed-in read', () {
    final rules = File('storage.rules').readAsStringSync();
    expect(rules, contains("match /{allPaths=**}"));
    expect(rules, contains('allow read, write: if false'));
    expect(rules, contains('match /notes/{fileName}'));
    expect(rules, contains('match /ragSources/{allPaths=**}'));
    expect(rules.contains('allow write: if isAdmin()'), isTrue);
    expect(rules, contains('match /ai_lessons/{lessonId}/{fileName}'));
    expect(rules, contains('match /videos/ai_lessons/{fileName}'));
    expect(rules, isNot(contains('allow read, write: if true')));
    expect(rules, contains('request.auth != null'));
  });
}
