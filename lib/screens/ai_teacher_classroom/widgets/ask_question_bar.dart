import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Bottom "Ask Question" bar — text field + microphone toggle + Ask button.
///
/// No speech-to-text or AI call happens here: the mic button only flips a
/// local "listening" flag (owned by the parent screen) so the avatar's
/// listening animation has something to react to, and Ask just hands the
/// typed text up via [onAsk].
class AskQuestionBar extends StatefulWidget {
  const AskQuestionBar({
    super.key,
    required this.isListening,
    required this.onToggleListening,
    required this.onAsk,
  });

  final bool isListening;
  final VoidCallback onToggleListening;
  final ValueChanged<String> onAsk;

  @override
  State<AskQuestionBar> createState() => _AskQuestionBarState();
}

class _AskQuestionBarState extends State<AskQuestionBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onAsk(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Ask your AI Teacher a question…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _MicButton(active: widget.isListening, onPressed: widget.onToggleListening),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Ask'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: const CircleBorder(),
      color: active ? AppColors.orange : AppColors.background,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            active ? Icons.mic_rounded : Icons.mic_none_rounded,
            color: active ? Colors.white : AppColors.navy,
            size: 22,
          ),
        ),
      ),
    );
  }
}
