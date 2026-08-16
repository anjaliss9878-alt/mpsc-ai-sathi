import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/services/ai_avatar_service.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:video_player/video_player.dart';

/// Avatar + Play/Pause control shown above an AI Teacher answer.
///
/// Renders one of two ways, purely based on whether [aiAvatarProvider]
/// currently exposes a [AiAvatarProvider.videoController] for this message:
/// - Default (no video provider configured): a locally-drawn animated
///   avatar that gently pulses while [state] is [AvatarPlaybackState.speaking].
/// - Once a HeyGen/D-ID provider is configured: the generated talking-head
///   video clip, played inline.
///
/// This widget never talks to Firestore, Gemini, or any AI backend itself —
/// it only reflects [isActive]/[state] and forwards taps to [onTogglePlay],
/// so the surrounding chat UI and message logic stay completely unchanged.
class AiAvatarHeader extends StatefulWidget {
  const AiAvatarHeader({
    super.key,
    required this.isActive,
    required this.state,
    required this.onTogglePlay,
  });

  /// Whether this specific message is the one currently loaded into the
  /// (single, shared) [aiAvatarProvider] — only one message can "speak" at
  /// a time.
  final bool isActive;

  /// Only meaningful when [isActive] is true; otherwise treated as idle.
  final AvatarPlaybackState state;

  final VoidCallback onTogglePlay;

  @override
  State<AiAvatarHeader> createState() => _AiAvatarHeaderState();
}

class _AiAvatarHeaderState extends State<AiAvatarHeader> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  AvatarPlaybackState get _effectiveState => widget.isActive ? widget.state : AvatarPlaybackState.idle;

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videoController = widget.isActive ? aiAvatarProvider.videoController : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          if (videoController != null && videoController.value.isInitialized)
            _buildVideoAvatar(videoController)
          else
            _buildAnimatedAvatar(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'AI Teacher',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusLabel(_effectiveState),
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          _buildPlayPauseButton(),
        ],
      ),
    );
  }

  Widget _buildVideoAvatar(VideoPlayerController controller) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 44,
        height: 44,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedAvatar() {
    final speaking = _effectiveState == AvatarPlaybackState.speaking;
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final scale = speaking ? 1.0 + (_pulseController.value * 0.12) : 1.0;
        return Stack(
          alignment: Alignment.center,
          children: [
            if (speaking)
              Transform.scale(
                scale: scale + 0.25,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.orange.withValues(alpha: 0.18 * (1 - _pulseController.value)),
                  ),
                ),
              ),
            Transform.scale(
              scale: scale,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.navy, AppColors.navyLight],
                  ),
                ),
                child: Icon(
                  _effectiveState == AvatarPlaybackState.error
                      ? Icons.priority_high_rounded
                      : Icons.psychology_alt_rounded,
                  color: AppColors.orange,
                  size: 20,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlayPauseButton() {
    final state = _effectiveState;
    if (state == AvatarPlaybackState.loading) {
      return const Padding(
        padding: EdgeInsets.all(10),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange),
        ),
      );
    }
    final icon = state == AvatarPlaybackState.speaking
        ? Icons.pause_circle_filled_rounded
        : Icons.play_circle_fill_rounded;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: widget.onTogglePlay,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 34, color: AppColors.orange),
        ),
      ),
    );
  }

  String _statusLabel(AvatarPlaybackState state) {
    switch (state) {
      case AvatarPlaybackState.loading:
        return 'तयार होत आहे... (Preparing...)';
      case AvatarPlaybackState.speaking:
        return 'बोलत आहे... (Speaking...)';
      case AvatarPlaybackState.paused:
        return 'थांबवले (Paused)';
      case AvatarPlaybackState.error:
        return 'आवाज ऐकवता आला नाही (Voice failed)';
      case AvatarPlaybackState.idle:
        return 'ऐकण्यासाठी दाबा (Tap to listen)';
    }
  }
}
