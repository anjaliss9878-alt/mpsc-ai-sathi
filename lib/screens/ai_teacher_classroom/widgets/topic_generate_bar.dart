import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Topic-only entry: student types a topic and presses Generate AI Lesson.
class TopicGenerateBar extends StatefulWidget {
  const TopicGenerateBar({
    super.key,
    required this.onGenerate,
    this.isBusy = false,
    this.initialTopic = '',
  });

  final ValueChanged<String> onGenerate;
  final bool isBusy;
  final String initialTopic;

  @override
  State<TopicGenerateBar> createState() => _TopicGenerateBarState();
}

class _TopicGenerateBarState extends State<TopicGenerateBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTopic);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit({String? topic}) {
    if (widget.isBusy) return;
    final text = (topic ?? _controller.text).trim();
    if (text.isEmpty) return;
    _controller.text = text;
    widget.onGenerate(text);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'विषय लिहा',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !widget.isBusy,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'उदा. मूलभूत अधिकार, राज्यघटना, गोदावरी नदी',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      prefixIcon: const Icon(Icons.topic_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: widget.isBusy ? null : () => _submit(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    disabledBackgroundColor:
                        AppColors.orange.withValues(alpha: 0.45),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: widget.isBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.school_rounded, size: 18),
                  label: Text(widget.isBusy ? 'Generating…' : 'Generate AI Lesson'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
