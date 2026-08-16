import 'dart:async';
import 'dart:convert';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

/// Thrown by [HeyGenAvatarProvider]/[DIdAvatarProvider] on a non-2xx REST
/// response. Kept local (rather than `dart:io`'s `HttpException`) so this
/// file stays fully compatible with Flutter Web.
class AvatarHttpException implements Exception {
  const AvatarHttpException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Playback state of the AI Avatar — drives the Play/Pause button and the
/// animated avatar's motion in `AiAvatarHeader`.
enum AvatarPlaybackState { idle, loading, speaking, paused, error }

/// Abstraction over "turn this AI answer into a talking avatar" so the
/// concrete backend can be swapped later without touching any UI.
///
/// Today, [AnimatedTtsAvatarProvider] is the only backend wired in by
/// default: it speaks the text with on-device Text-to-Speech and drives a
/// simple animated avatar shape locally — no network call, no API key.
///
/// [HeyGenAvatarProvider] and [DIdAvatarProvider] implement the exact same
/// interface against the HeyGen / D-ID "talking avatar video" REST APIs, so
/// connecting either one later is just flipping the single configuration
/// point at the bottom of this file — no change to [AiAvatarHeader] or the
/// AI Teacher screen required.
abstract class AiAvatarProvider {
  /// Starts speaking/playing [text]. Emits state changes on [stateStream].
  ///
  /// [rateMultiplier] scales the base speech rate (1.0 = normal).
  /// [volume] is 0.0–1.0 (Lesson Player mute uses 0).
  Future<void> speak(String text, {double rateMultiplier = 1.0, double volume = 1.0});

  Future<void> pause();
  Future<void> resume();
  Future<void> stop();

  Stream<AvatarPlaybackState> get stateStream;

  /// Non-null only once a real video-avatar backend (HeyGen/D-ID) has
  /// generated a playable clip for the current [speak] call and it has
  /// finished initializing. `AiAvatarHeader` renders this video surface
  /// instead of the local animated avatar shape whenever it is non-null.
  VideoPlayerController? get videoController;

  void dispose();
}

/// Default [AiAvatarProvider]: speaks [text] using on-device Text-to-Speech
/// (via `flutter_tts`) and never produces a video — `AiAvatarHeader` always
/// falls back to its locally-drawn animated avatar shape for this provider.
///
/// Requires no configuration, no API key, and no network access, so the
/// Avatar module works fully out of the box.
class AnimatedTtsAvatarProvider implements AiAvatarProvider {
  AnimatedTtsAvatarProvider() {
    _tts.setStartHandler(() => _emit(AvatarPlaybackState.speaking));
    _tts.setCompletionHandler(() => _emit(AvatarPlaybackState.idle));
    _tts.setCancelHandler(() => _emit(AvatarPlaybackState.idle));
    _tts.setPauseHandler(() => _emit(AvatarPlaybackState.paused));
    _tts.setContinueHandler(() => _emit(AvatarPlaybackState.speaking));
    _tts.setErrorHandler((_) => _emit(AvatarPlaybackState.error));
  }

  final FlutterTts _tts = FlutterTts();
  final StreamController<AvatarPlaybackState> _stateController =
      StreamController<AvatarPlaybackState>.broadcast();
  String? _lastSpokenText;

  void _emit(AvatarPlaybackState state) {
    if (!_stateController.isClosed) _stateController.add(state);
  }

  @override
  Stream<AvatarPlaybackState> get stateStream => _stateController.stream;

  @override
  VideoPlayerController? get videoController => null;

  @override
  Future<void> speak(String text, {double rateMultiplier = 1.0, double volume = 1.0}) async {
    _emit(AvatarPlaybackState.loading);
    final plain = _stripForSpeech(text);
    _lastSpokenText = plain;
    final isMarathi = RegExp(r'[\u0900-\u097F]').hasMatch(plain);
    try {
      await _tts.setLanguage(isMarathi ? 'mr-IN' : 'en-IN');
      final rate = (0.48 * rateMultiplier).clamp(0.25, 0.85);
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(1.0);
      await _tts.setVolume(volume.clamp(0.0, 1.0));
      final result = await _tts.speak(plain);
      if (result != 1) _emit(AvatarPlaybackState.error);
    } catch (_) {
      _emit(AvatarPlaybackState.error);
    }
  }

  @override
  Future<void> pause() async {
    await _tts.pause();
  }

  @override
  Future<void> resume() async {
    // flutter_tts has no dedicated "resume" call — re-invoking speak() while
    // the engine is in a paused state continues from where it left off on
    // platforms with native pause support (Web, iOS); elsewhere it restarts
    // the utterance, which is an acceptable graceful fallback.
    final text = _lastSpokenText;
    if (text == null) return;
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _emit(AvatarPlaybackState.idle);
  }

  @override
  void dispose() {
    _tts.stop();
    _stateController.close();
  }

  String _stripForSpeech(String markdown) {
    return markdown
        .replaceAll(RegExp(r'[*_`#>]'), '')
        .replaceAll(RegExp(r'\|'), ' ')
        .replaceAll(RegExp(r'\n{2,}'), '. ')
        .replaceAll('\n', ' ')
        .trim();
  }
}

/// Shared scaffold for talking-head video providers (HeyGen, D-ID): submit
/// a text-to-video generation job, poll until it's ready, then play the
/// resulting clip through a [VideoPlayerController].
///
/// Subclasses only need to supply the provider-specific HTTP request/
/// response shape via [createJob] and [pollJob] — everything else (state
/// machine, polling loop, video playback, Play/Pause wiring) is shared.
///
/// NOTE: the exact HeyGen/D-ID request/response fields below follow each
/// provider's publicly documented "generate video from text" flow as of
/// today, but third-party APIs change — re-verify field names/endpoints
/// against the current HeyGen/D-ID docs once a real key is available, and
/// test end-to-end before shipping to production.
abstract class VideoAvatarProvider implements AiAvatarProvider {
  VideoAvatarProvider({required this.apiKey, this.avatarId, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final String? avatarId;
  final http.Client _client;

  final StreamController<AvatarPlaybackState> _stateController =
      StreamController<AvatarPlaybackState>.broadcast();

  VideoPlayerController? _videoController;
  Timer? _pollTimer;

  @override
  Stream<AvatarPlaybackState> get stateStream => _stateController.stream;

  @override
  VideoPlayerController? get videoController => _videoController;

  void _emit(AvatarPlaybackState state) {
    if (!_stateController.isClosed) _stateController.add(state);
  }

  /// Submits the generation job for [text] and returns the provider's job
  /// id, to be polled via [pollJob].
  Future<String> createJob(http.Client client, String text);

  /// Polls the job's status once. Returns the finished video URL, or `null`
  /// if the job is still processing. Should throw on a job failure.
  Future<String?> pollJob(http.Client client, String jobId);

  @override
  Future<void> speak(String text, {double rateMultiplier = 1.0, double volume = 1.0}) async {
    await stop();
    _emit(AvatarPlaybackState.loading);
    try {
      final jobId = await createJob(_client, text);
      final videoUrl = await _waitForVideo(jobId);
      await _playVideo(videoUrl);
    } catch (_) {
      _emit(AvatarPlaybackState.error);
    }
  }

  Future<String> _waitForVideo(String jobId) async {
    const timeout = Duration(minutes: 2);
    const pollInterval = Duration(seconds: 3);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final url = await pollJob(_client, jobId);
      if (url != null) return url;
      await Future.delayed(pollInterval);
    }
    throw TimeoutException('Video avatar generation timed out for job $jobId');
  }

  Future<void> _playVideo(String videoUrl) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    _videoController = controller;
    await controller.initialize();
    controller.addListener(() {
      if (controller.value.position >= controller.value.duration &&
          !controller.value.isPlaying) {
        _emit(AvatarPlaybackState.idle);
      }
    });
    await controller.play();
    _emit(AvatarPlaybackState.speaking);
  }

  @override
  Future<void> pause() async {
    await _videoController?.pause();
    _emit(AvatarPlaybackState.paused);
  }

  @override
  Future<void> resume() async {
    await _videoController?.play();
    _emit(AvatarPlaybackState.speaking);
  }

  @override
  Future<void> stop() async {
    _pollTimer?.cancel();
    await _videoController?.pause();
    await _videoController?.dispose();
    _videoController = null;
    _emit(AvatarPlaybackState.idle);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _videoController?.dispose();
    _stateController.close();
  }
}

/// [AiAvatarProvider] backed by the HeyGen "generate video" REST API.
///
/// Configure with `--dart-define=AVATAR_PROVIDER=heygen
/// --dart-define=AVATAR_API_KEY=your_heygen_key
/// --dart-define=AVATAR_ID=your_heygen_avatar_id` (see the bottom of this
/// file). [avatarId] should be a HeyGen `avatar_id` (from the HeyGen
/// dashboard/API) to render.
class HeyGenAvatarProvider extends VideoAvatarProvider {
  HeyGenAvatarProvider({required super.apiKey, super.avatarId, super.client});

  static const String _createUrl = 'https://api.heygen.com/v2/video/generate';
  static const String _statusUrl = 'https://api.heygen.com/v1/video_status.get';

  @override
  Future<String> createJob(http.Client client, String text) async {
    final response = await client.post(
      Uri.parse(_createUrl),
      headers: {'Content-Type': 'application/json', 'X-Api-Key': apiKey},
      body: jsonEncode({
        'video_inputs': [
          {
            'character': {
              'type': 'avatar',
              'avatar_id': avatarId ?? '',
              'avatar_style': 'normal',
            },
            'voice': {'type': 'text', 'input_text': text},
          },
        ],
        'dimension': {'width': 720, 'height': 1280},
      }),
    );
    if (response.statusCode != 200) {
      throw AvatarHttpException('HeyGen video.generate failed (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final videoId = (decoded['data'] as Map<String, dynamic>?)?['video_id'] as String?;
    if (videoId == null) throw const FormatException('HeyGen response missing video_id');
    return videoId;
  }

  @override
  Future<String?> pollJob(http.Client client, String jobId) async {
    final response = await client.get(
      Uri.parse('$_statusUrl?video_id=$jobId'),
      headers: {'X-Api-Key': apiKey},
    );
    if (response.statusCode != 200) {
      throw AvatarHttpException('HeyGen video_status.get failed (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as Map<String, dynamic>?;
    final status = data?['status'] as String?;
    if (status == 'completed') return data?['video_url'] as String?;
    if (status == 'failed') throw Exception('HeyGen video generation failed: ${data?['error']}');
    return null;
  }
}

/// [AiAvatarProvider] backed by the D-ID "talks" (text-to-video) REST API.
///
/// Configure with `--dart-define=AVATAR_PROVIDER=did
/// --dart-define=AVATAR_API_KEY=your_did_api_key
/// --dart-define=AVATAR_ID=https://your-avatar-image-url.jpg` (see the
/// bottom of this file). [avatarId] should be a publicly reachable image
/// URL of the avatar face D-ID should animate.
class DIdAvatarProvider extends VideoAvatarProvider {
  DIdAvatarProvider({required super.apiKey, super.avatarId, super.client});

  static const String _talksUrl = 'https://api.d-id.com/talks';

  @override
  Future<String> createJob(http.Client client, String text) async {
    final response = await client.post(
      Uri.parse(_talksUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Basic $apiKey',
      },
      body: jsonEncode({
        'source_url': avatarId ?? '',
        'script': {'type': 'text', 'input': text},
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw AvatarHttpException('D-ID talks create failed (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final id = decoded['id'] as String?;
    if (id == null) throw const FormatException('D-ID response missing talk id');
    return id;
  }

  @override
  Future<String?> pollJob(http.Client client, String jobId) async {
    final response = await client.get(
      Uri.parse('$_talksUrl/$jobId'),
      headers: {'Authorization': 'Basic $apiKey'},
    );
    if (response.statusCode != 200) {
      throw AvatarHttpException('D-ID talks poll failed (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final status = decoded['status'] as String?;
    if (status == 'done') return decoded['result_url'] as String?;
    if (status == 'error' || status == 'rejected') {
      throw Exception('D-ID talk generation failed: ${decoded['error']}');
    }
    return null;
  }
}

// --- Single configuration point ------------------------------------------
//
// AVATAR_PROVIDER: "none" (default) | "heygen" | "did"
// AVATAR_API_KEY : the HeyGen/D-ID API key — only needed when AVATAR_PROVIDER
//                   is "heygen" or "did".
// AVATAR_ID      : HeyGen avatar_id, or a D-ID source image URL.
//
// Example (HeyGen):
//   flutter run -d chrome --dart-define=AVATAR_PROVIDER=heygen \
//     --dart-define=AVATAR_API_KEY=your_heygen_key \
//     --dart-define=AVATAR_ID=your_heygen_avatar_id
//
// Example (D-ID):
//   flutter run -d chrome --dart-define=AVATAR_PROVIDER=did \
//     --dart-define=AVATAR_API_KEY=your_did_api_key \
//     --dart-define=AVATAR_ID=https://your-avatar-image-url.jpg
//
// Leave AVATAR_PROVIDER unset (the default "none") to keep using the local
// AnimatedTtsAvatarProvider — no key, no network call, works out of the box.
// Nothing else needs to change either way: `AiAvatarHeader` only ever
// depends on the [AiAvatarProvider] interface above.
const String _avatarProviderName = String.fromEnvironment(
  'AVATAR_PROVIDER',
  defaultValue: 'none',
);
const String _avatarApiKey = String.fromEnvironment('AVATAR_API_KEY');
const String _avatarId = String.fromEnvironment('AVATAR_ID');

AiAvatarProvider _createAvatarProvider() {
  if (_avatarApiKey.isNotEmpty) {
    switch (_avatarProviderName.toLowerCase()) {
      case 'heygen':
        return HeyGenAvatarProvider(apiKey: _avatarApiKey, avatarId: _avatarId);
      case 'did':
        return DIdAvatarProvider(apiKey: _avatarApiKey, avatarId: _avatarId);
    }
  }
  return AnimatedTtsAvatarProvider();
}

/// Shared instance used by `AiAvatarHeader`. Automatically resolves to a
/// real video-avatar backend once `AVATAR_PROVIDER`/`AVATAR_API_KEY` are
/// supplied at build/run time, otherwise falls back to the local animated
/// avatar driven by on-device Text-to-Speech.
final AiAvatarProvider aiAvatarProvider = _createAvatarProvider();
