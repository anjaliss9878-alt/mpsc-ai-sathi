import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/faculty_narration.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/speakable_marathi.dart';

void main() {
  test('never leaves plus minus slash or percent for TTS to read', () {
    final spoken = speakableMarathi(
      'GDP + 8% growth / decline — see Page 12 • Fig. 3',
    );
    expect(spoken.contains('+'), isFalse);
    expect(spoken.contains('%'), isFalse);
    expect(spoken.contains('/'), isFalse);
    expect(spoken.toLowerCase().contains('page'), isFalse);
    expect(spoken, contains('जी डी पी'));
    expect(spoken, contains('टक्के'));
    expect(spoken, contains('आकृती'));
  });

  test('number ranges become ते and percents become टक्के', () {
    expect(speakableMarathi('5-7%'), contains('ते'));
    expect(speakableMarathi('5-7%'), contains('टक्के'));
    expect(speakableMarathi('2+2'), contains('अधिक'));
  });

  test('facultyNarration expands UPSC and strips bullets', () {
    final t = facultyNarration('• UPSC / MPSC prelims');
    expect(t.contains('•'), isFalse);
    expect(t, contains('यू पी एस सी'));
    expect(t, contains('एम पी एस सी'));
    expect(t.contains('/'), isFalse);
  });

  test('never leaves English plus/percent or leftover symbols', () {
    final spoken = speakableMarathi('plus 5 percent = GDP');
    expect(spoken.toLowerCase().contains('plus'), isFalse);
    expect(spoken.toLowerCase().contains('percent'), isFalse);
    expect(spoken.contains('+'), isFalse);
    expect(spoken.contains('%'), isFalse);
    expect(spoken.contains('='), isFalse);
    expect(spoken, contains('अधिक'));
    expect(spoken, contains('टक्के'));
    expect(spoken, contains('जी डी पी'));
  });

  test('board cleaner keeps teaching words but drops page chrome', () {
    expect(cleanBoardText('Page 4  लोकसभा'), isNot(contains('Page')));
    expect(cleanBoardText('• लोकसभा'), equals('लोकसभा'));
  });
}
