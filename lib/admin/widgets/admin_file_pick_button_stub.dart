import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_file_pick_support.dart';

/// IO / tests: [FilePicker] from the existing Admin upload dependency.
class AdminFilePickButton extends StatelessWidget {
  const AdminFilePickButton({
    super.key,
    required this.label,
    required this.icon,
    required this.allowedExtensions,
    required this.onPicked,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final List<String> allowedExtensions;
  final ValueChanged<AdminPickedLocalFile> onPicked;
  final bool enabled;

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return;
    if (!adminFileNameMatchesExtensions(file.name, allowedExtensions)) return;
    onPicked(AdminPickedLocalFile(name: file.name, bytes: bytes));
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? _pick : null,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
