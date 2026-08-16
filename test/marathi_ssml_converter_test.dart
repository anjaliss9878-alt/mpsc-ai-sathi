import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/marathi_ssml_converter.dart';
import 'package:mpsc_combine_ai/services/ai_video_render/marathi_pronunciation_dictionary.dart';

void main() {
  test('SSML wraps speak + prosody and injects sentence breaks', () {
    final ssml = marathiSsmlConverter.toSsml(
      'लोकसभा जनतेची सभागृह आहे। राज्यसभा स्थायी आहे.',
    );
    expect(ssml.startsWith('<speak>'), isTrue);
    expect(ssml.contains('<prosody'), isTrue);
    expect(ssml.contains('<break time='), isTrue);
    expect(ssml.contains('</speak>'), isTrue);
  });

  test('pronunciation dictionary aliases MPSC abbreviations', () {
    final dict = MarathiPronunciationDictionary();
    final out = dict.applyAliases('MPSC Combine मध्ये GDP महत्त्वाचा आहे.');
    expect(out, contains('एम पी एस सी'));
    expect(out, contains('जी डी पी'));
  });

  test('definition kind uses slower prosody rate', () {
    final ssml = marathiSsmlConverter.toSsml(
      'व्याख्या: मूलभूत हक्क म्हणजे संवैधानिक हक्क.',
      kind: SsmlSegmentKind.definition,
    );
    expect(ssml, contains('rate="92%"'));
  });

  test('toChunks splits long text safely', () {
    final long = List.filled(40, 'ही एक मराठी वाक्य आहे।').join(' ');
    final chunks = marathiSsmlConverter.toChunks(long, maxChars: 120);
    expect(chunks.length, greaterThan(1));
    for (final c in chunks) {
      expect(c.ssml, contains('<speak>'));
      expect(c.plainText.length, lessThanOrEqualTo(120 + 40));
    }
  });

  test('inferKind detects definition and revision generically', () {
    expect(
      MarathiSsmlConverter.inferKind(text: 'ही व्याख्या आहे', title: 'व्याख्या'),
      SsmlSegmentKind.definition,
    );
    expect(
      MarathiSsmlConverter.inferKind(text: 'थोडक्यात सारांश', title: 'पुनरावलोकन'),
      SsmlSegmentKind.revision,
    );
  });
}
