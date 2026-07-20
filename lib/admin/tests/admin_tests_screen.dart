import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/tests/admin_test_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/test_item.dart';
import 'package:mpsc_combine_ai/services/test_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminTestsScreen extends StatelessWidget {
  const AdminTestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Mock Tests',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminTestFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<TestItem>>(
        stream: testRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load tests: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final tests = snapshot.data!;
          if (tests.isEmpty) {
            return const EmptyState(
              message: 'No tests yet. Tap + to create the first mock test.',
              icon: Icons.assignment_outlined,
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tests.length,
            itemBuilder: (context, index) {
              final test = tests[index];
              return AdminListTile(
                title: test.title,
                subtitle:
                    '${test.questions.length} questions · ${test.durationSeconds ~/ 60} min · '
                    '+${test.correctMarks}/-${test.negativeMarks}',
                icon: Icons.assignment_turned_in_rounded,
                onEdit: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminTestFormScreen(existing: test),
                  ),
                ),
                onDelete: () async {
                  final confirmed = await confirmDelete(context, test.title);
                  if (!confirmed) return;
                  try {
                    await testRepository.delete(test.id);
                    if (context.mounted) showAdminMessage(context, 'Test deleted.');
                  } catch (e) {
                    if (context.mounted) showAdminError(context, e);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
