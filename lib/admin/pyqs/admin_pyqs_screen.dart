import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/admin/pyqs/admin_pyq_form_screen.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_list_tile.dart';
import 'package:mpsc_combine_ai/admin/widgets/admin_scaffold.dart';
import 'package:mpsc_combine_ai/admin/widgets/confirm_delete_dialog.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/services/audit_log_repository.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class AdminPyqsScreen extends StatefulWidget {
  const AdminPyqsScreen({super.key});

  @override
  State<AdminPyqsScreen> createState() => _AdminPyqsScreenState();
}

class _AdminPyqsScreenState extends State<AdminPyqsScreen> {
  int? _yearFilter;

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Previous Year Questions',
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const AdminPyqFormScreen()),
        ),
        child: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<PyqItem>>(
        stream: pyqRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(message: 'Could not load PYQs: ${snapshot.error}');
          }
          if (!snapshot.hasData) return const LoadingState();
          final allItems = snapshot.data!;
          final years = allItems
              .map((i) => i.year)
              .whereType<int>()
              .toSet()
              .toList()
            ..sort((a, b) => b.compareTo(a));
          final items = _yearFilter == null
              ? allItems
              : allItems.where((i) => i.year == _yearFilter).toList();
          return Column(
            children: [
              if (years.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      const Text('Filter by year:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ChoiceChip(
                                label: const Text('All'),
                                selected: _yearFilter == null,
                                onSelected: (_) => setState(() => _yearFilter = null),
                              ),
                              const SizedBox(width: 6),
                              ...years.map(
                                (y) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text('$y'),
                                    selected: _yearFilter == y,
                                    onSelected: (_) => setState(() => _yearFilter = y),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? const EmptyState(
                        message: 'No question papers yet. Tap + to add the first one.',
                        icon: Icons.history_edu_outlined,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final subtitle = item.isStructuredQuestion
                              ? [
                                  if (item.year != null) '${item.year}',
                                  item.examName,
                                  item.question,
                                ].where((s) => s.isNotEmpty).join(' · ')
                              : item.subtitle;
                          return AdminListTile(
                            title: item.title,
                            subtitle: subtitle,
                            icon: item.isStructuredQuestion
                                ? Icons.quiz_outlined
                                : Icons.description_rounded,
                            onEdit: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AdminPyqFormScreen(existing: item),
                              ),
                            ),
                            onDelete: () async {
                              final confirmed = await confirmDelete(context, item.title);
                              if (!confirmed) return;
                              try {
                                await pyqRepository.delete(item.id);
                                await auditLogRepository.log(
                                  action: 'delete',
                                  module: 'PYQs',
                                  targetLabel: item.title,
                                );
                                if (context.mounted) showAdminMessage(context, 'Entry deleted.');
                              } catch (e) {
                                if (context.mounted) showAdminError(context, e);
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
