import 'package:flutter/material.dart';

/// A "one item per line" multiline text field, used to edit `List<String>`
/// fields (bullet points, MCQ options) without a fiddly add/remove chip UI.
/// Keeps the Admin Panel simple and reliable — blank lines are dropped
/// automatically when reading [lines].
class LineListField extends StatefulWidget {
  const LineListField({
    super.key,
    required this.label,
    required this.initialLines,
    required this.hintText,
    this.minLines = 3,
    this.controller,
  });

  final String label;
  final List<String> initialLines;
  final String hintText;
  final int minLines;

  /// When provided, the parent owns the controller (preferred for Save-ready
  /// forms). Otherwise this widget creates and disposes its own.
  final TextEditingController? controller;

  @override
  State<LineListField> createState() => LineListFieldState();
}

class LineListFieldState extends State<LineListField> {
  late final TextEditingController controller;
  late final bool _ownsController;

  List<String> get lines => linesFromController(controller);

  static List<String> linesFromController(TextEditingController c) => c.text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  @override
  void initState() {
    super.initState();
    final external = widget.controller;
    if (external != null) {
      controller = external;
      _ownsController = false;
      if (controller.text.isEmpty && widget.initialLines.isNotEmpty) {
        controller.text = widget.initialLines.join('\n');
      }
    } else {
      controller = TextEditingController(text: widget.initialLines.join('\n'));
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: widget.minLines,
      maxLines: widget.minLines + 5,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        alignLabelWithHint: true,
      ),
    );
  }
}
