import 'package:flutter/material.dart';

/// Shows a Delete confirmation dialog; resolves to `true` only if the admin
/// confirms. Used before every destructive delete in the Admin Panel.
Future<bool> confirmDelete(BuildContext context, String itemLabel) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this item?'),
      content: Text('"$itemLabel" will be permanently deleted. This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shows an error SnackBar with a consistent style, used across the Admin
/// Panel whenever a Firestore call fails.
void showAdminError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('Error: $error')));
}

void showAdminMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
