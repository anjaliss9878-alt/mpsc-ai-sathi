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
  });

  final String label;
  final List<String> initialLines;
  final String hintText;
  final int minLines;

  @override
  State<LineListField> createState() => LineListFieldState();
}

class LineListFieldState extends State<LineListField> {
  late final TextEditingController controller =
      TextEditingController(text: widget.initialLines.join('\n'));

  List<String> get lines => controller.text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  @override
  void dispose() {
    controller.dispose();
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
