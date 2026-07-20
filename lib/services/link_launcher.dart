import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the system browser/app (YouTube, Zoom, Google Meet, PDF
/// links, etc.). Shows a SnackBar instead of throwing if it can't be
/// opened, since a bad/missing link entered in the Admin Panel must never
/// crash the student app.
Future<void> openExternalLink(BuildContext context, String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    _showSnack(context, 'No link is available yet.');
    return;
  }
  final uri = Uri.tryParse(
    trimmed.contains('://') ? trimmed : 'https://$trimmed',
  );
  if (uri == null) {
    _showSnack(context, 'This link looks invalid.');
    return;
  }
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      _showSnack(context, 'Could not open the link.');
    }
  } catch (_) {
    if (context.mounted) _showSnack(context, 'Could not open the link.');
  }
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
