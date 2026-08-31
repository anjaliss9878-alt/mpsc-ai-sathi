import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/admin_bulk_upload_screen.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/admin_flashcard_bulk_upload_screen.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/admin_pyq_bulk_upload_screen.dart';
import 'package:mpsc_combine_ai/admin/bulk_upload/admin_smart_trick_bulk_upload_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

class AdminBulkUploadHubScreen extends StatelessWidget {
  const AdminBulkUploadHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Bulk Upload',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Imported rows are always saved as DRAFT. Never auto-published.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          _HubTile(
            icon: Icons.quiz_rounded,
            title: 'MCQs',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminBulkUploadScreen(),
              ),
            ),
          ),
          _HubTile(
            icon: Icons.history_edu_rounded,
            title: 'PYQs',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminPyqBulkUploadScreen(),
              ),
            ),
          ),
          _HubTile(
            icon: Icons.style_rounded,
            title: 'Flashcards',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminFlashcardBulkUploadScreen(),
              ),
            ),
          ),
          _HubTile(
            icon: Icons.psychology_alt_rounded,
            title: 'Smart Tricks',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminSmartTrickBulkUploadScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppColors.navy),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('CSV / Excel · DRAFT'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
