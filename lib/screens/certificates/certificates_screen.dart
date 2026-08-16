import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class CertificatesScreen extends StatelessWidget {
  const CertificatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = authService.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Certificates')),
      body: uid == null
          ? const Center(child: Text('Sign in to view certificates.'))
          : StreamBuilder<List<CertificateItem>>(
              stream: studentProgressRepository.watchCertificates(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorState(message: 'Could not load certificates.\n${snapshot.error}');
                }
                if (!snapshot.hasData) return const LoadingState();
                final items = snapshot.data!;
                if (items.isEmpty) {
                  return const EmptyState(
                    message:
                        'No certificates yet.\nComplete classroom chapters to earn completion certificates.',
                    icon: Icons.workspace_premium_outlined,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.workspace_premium_rounded,
                          color: AppColors.orange,
                        ),
                        title: Text(
                          c.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${c.subtitle}\nIssued ${c.issuedAt.toLocal()}'.split('.').first,
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
