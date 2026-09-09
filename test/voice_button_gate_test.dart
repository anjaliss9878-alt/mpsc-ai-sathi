import 'package:flutter_test/flutter_test.dart';
import 'package:mpsc_combine_ai/services/voice_button_gate.dart';

void main() {
  test('duplicate Voice/Play clicks are ignored until release', () {
    final gate = VoiceButtonGate();
    expect(gate.tryAcquire(), isTrue);
    expect(gate.isBusy, isTrue);
    expect(gate.tryAcquire(), isFalse);
    gate.release();
    expect(gate.tryAcquire(), isTrue);
  });

  test('playback failure resets the Voice/Play gate', () {
    final gate = VoiceButtonGate();
    expect(gate.tryAcquire(), isTrue);
    gate.release();
    expect(gate.isBusy, isFalse);
    expect(gate.tryAcquire(), isTrue);
  });
}
