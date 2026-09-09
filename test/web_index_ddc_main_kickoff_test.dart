import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web/index.html retries DDC main until a Flutter view exists', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html.contains(r'$dartRunMain'), isTrue);
    expect(html.contains('flutter-view'), isTrue);
    expect(html.contains(r'$dartMainTearOffs'), isTrue);
    expect(
      html.contains('one-shot 2s call is not enough'),
      isTrue,
      reason: r'Must document why a single $dartRunMain call is insufficient',
    );
    expect(html.contains('<title>MPSC AI SATHI</title>'), isTrue);
    expect(html.contains('icons/Icon-512.png'), isTrue);
  });
}
