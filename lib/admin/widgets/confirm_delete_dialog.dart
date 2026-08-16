import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
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

/// Human-readable Firebase / generic error for Admin SnackBars and dialogs.
String formatAdminError(Object error) {
  if (error is FirebaseException) {
    final code = error.code;
    final message = (error.message ?? '').trim();
    final plugin = error.plugin;
    final hint = switch (code) {
      'permission-denied' =>
        'Permission denied. Confirm you are signed in as an admin '
            '(`admin/{uid}` or `admins/{uid}` in Firestore) and that '
            'firestore.rules / storage.rules are deployed '
            '(`firebase deploy --only firestore:rules,storage`).',
      'unauthenticated' =>
        'Not signed in. Sign out and sign back in to the Admin Panel.',
      'not-found' => 'Document or resource was not found.',
      'unavailable' => 'Firebase is temporarily unavailable. Check network and retry.',
      _ => '',
    };
    final parts = <String>[
      if (plugin.isNotEmpty) '[$plugin]',
      'code=$code',
      if (message.isNotEmpty) message,
      if (hint.isNotEmpty) hint,
    ];
    return parts.join(' — ');
  }
  if (error is FirebaseAuthException) {
    return 'Auth code=${error.code} — ${error.message ?? error.toString()}';
  }
  return error.toString();
}

/// Shows an error SnackBar **and** a dialog with the real Firebase error
/// code/message so failures are never silent (SnackBars alone are easy to miss
/// behind the bottom Save bar).
void showAdminError(BuildContext context, Object error, {String title = 'Action failed'}) {
  final text = formatAdminError(error);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade800,
        duration: const Duration(seconds: 8),
        content: Text('Error: $text'),
      ),
    );
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(text)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

void showAdminMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
