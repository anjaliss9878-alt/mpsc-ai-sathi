import 'package:mpsc_combine_ai/models/live_class_item.dart';

/// How the Join screen should render/act once [LiveClassVideoProvider.
/// prepareJoin] resolves.
enum LiveClassJoinMode {
  /// Open [LiveClassJoinResult.url] externally (Zoom/Meet/YouTube Live) —
  /// today's only mode, handled via `link_launcher.dart`.
  externalLink,

  /// Render an embedded, in-app video call widget using [roomToken]. No
  /// provider implements this yet; reserved for a future 100ms integration.
  embeddedRoom,

  /// Nothing to join yet (e.g. no meeting link/room configured).
  notReady,
}

class LiveClassJoinResult {
  const LiveClassJoinResult.externalLink(this.url)
      : mode = LiveClassJoinMode.externalLink,
        roomToken = null;

  const LiveClassJoinResult.embeddedRoom(this.roomToken)
      : mode = LiveClassJoinMode.embeddedRoom,
        url = null;

  const LiveClassJoinResult.notReady()
      : mode = LiveClassJoinMode.notReady,
        url = null,
        roomToken = null;

  final LiveClassJoinMode mode;
  final String? url;
  final String? roomToken;
}

/// Abstraction over "join this live class's video room" so a real video SDK
/// (100ms) can be plugged in later without changing the Join Screen, the
/// Live Now screen, or any other UI.
///
/// [LocalLinkVideoProvider] (the only implementation wired in today) never
/// starts a video call itself — it just hands back the class's plain
/// [LiveClassItem.meetingUrl] for the UI to open externally.
///
/// A future `HmsVideoProvider` would instead: call your backend to mint a
/// 100ms auth token for [LiveClassItem.roomId], return it via
/// [LiveClassJoinResult.embeddedRoom], and the Join Screen would render the
/// 100ms Flutter SDK's call widget instead of opening a link — swapped in
/// purely by changing [liveClassVideoProvider] below.
abstract class LiveClassVideoProvider {
  Future<LiveClassJoinResult> prepareJoin(LiveClassItem liveClass);
}

/// Default provider: no SDK, no token, no network call — just resolves
/// whether there's an external meeting link to open.
class LocalLinkVideoProvider implements LiveClassVideoProvider {
  @override
  Future<LiveClassJoinResult> prepareJoin(LiveClassItem liveClass) async {
    final url = liveClass.meetingUrl.trim();
    if (url.isEmpty) return const LiveClassJoinResult.notReady();
    return LiveClassJoinResult.externalLink(url);
  }
}

/// Shared instance used by the Join Screen. Swap this single line for a
/// 100ms-backed provider once that SDK is integrated — no other file needs
/// to change.
final LiveClassVideoProvider liveClassVideoProvider = LocalLinkVideoProvider();
