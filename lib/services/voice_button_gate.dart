/// Prevents overlapping Voice/Play taps while TTS/audio is starting.
class VoiceButtonGate {
  bool _busy = false;

  bool get isBusy => _busy;

  bool tryAcquire() {
    if (_busy) return false;
    _busy = true;
    return true;
  }

  void release() => _busy = false;
}
