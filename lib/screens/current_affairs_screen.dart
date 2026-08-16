import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/current_affair_item.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/current_affairs_repository.dart';
import 'package:mpsc_combine_ai/services/link_launcher.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/date_format.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class CurrentAffairsScreen extends StatefulWidget {
  const CurrentAffairsScreen({super.key});

  @override
  State<CurrentAffairsScreen> createState() => _CurrentAffairsScreenState();
}

class _CurrentAffairsScreenState extends State<CurrentAffairsScreen> {
  String _query = '';
  bool _monthlyOnly = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Current Affairs'),
        actions: [
          IconButton(
            tooltip: _monthlyOnly ? 'Show all' : 'Monthly PDFs',
            onPressed: () => setState(() => _monthlyOnly = !_monthlyOnly),
            icon: Icon(
              _monthlyOnly
                  ? Icons.calendar_month_rounded
                  : Icons.calendar_view_month_outlined,
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<CurrentAffairItem>>(
        stream: currentAffairsRepository.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              message: 'Could not load current affairs.\n${snapshot.error}',
            );
          }
          if (!snapshot.hasData) return const LoadingState();

          var items = snapshot.data!;
          if (_monthlyOnly) {
            items = items.where((e) => e.monthlyPdfUrl.isNotEmpty).toList();
          }
          if (_query.trim().isNotEmpty) {
            final q = _query.trim().toLowerCase();
            items = items
                .where(
                  (e) =>
                      e.title.toLowerCase().contains(q) ||
                      e.description.toLowerCase().contains(q) ||
                      e.category.toLowerCase().contains(q),
                )
                .toList();
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search current affairs…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? EmptyState(
                        message: _monthlyOnly
                            ? 'No monthly PDFs published yet.'
                            : 'No current affairs yet.',
                        icon: Icons.newspaper_outlined,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Card(
                            child: ListTile(
                              leading: const Icon(
                                Icons.today_rounded,
                                color: AppColors.navy,
                              ),
                              title: Text(
                                item.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${formatShortDate(item.date)} · ${item.category}',
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _showDetail(context, item),
                            ),
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

  void _showDetail(BuildContext context, CurrentAffairItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item.category,
                      style: const TextStyle(
                        color: AppColors.orange,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatLongDate(item.date),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    item.description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                          height: 1.5,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final uid = authService.currentUser?.uid;
                          if (uid == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Sign in to bookmark.'),
                              ),
                            );
                            return;
                          }
                          await studentProgressRepository.toggleBookmark(
                            uid: uid,
                            id: 'ca_${item.id}',
                            type: 'current_affairs',
                            title: item.title,
                            subtitle: item.category,
                            refId: item.id,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Bookmark updated.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.bookmark_border_rounded),
                        label: const Text('Bookmark'),
                      ),
                      if (item.pdfUrl.isNotEmpty)
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              openExternalLink(context, item.pdfUrl),
                          icon: const Icon(Icons.picture_as_pdf_rounded),
                          label: const Text('Daily PDF'),
                        ),
                      if (item.monthlyPdfUrl.isNotEmpty)
                        FilledButton.icon(
                          onPressed: () =>
                              openExternalLink(context, item.monthlyPdfUrl),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Monthly PDF'),
                        ),
                      if (item.hasQuiz)
                        FilledButton.icon(
                          onPressed: () => _openQuiz(context, item),
                          icon: const Icon(Icons.quiz_rounded),
                          label: const Text('Quiz'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openQuiz(BuildContext context, CurrentAffairItem item) {
    int? selected;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('CA Quiz'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.quizQuestion),
                  const SizedBox(height: 12),
                  ...List.generate(item.quizOptions.length, (i) {
                    final correct =
                        selected != null && i == item.quizCorrectIndex;
                    final wrong =
                        selected == i && i != item.quizCorrectIndex;
                    return ListTile(
                      leading: Icon(
                        selected == null
                            ? Icons.circle_outlined
                            : correct
                                ? Icons.check_circle_rounded
                                : wrong
                                    ? Icons.cancel_rounded
                                    : Icons.circle_outlined,
                        color: correct
                            ? Colors.green
                            : wrong
                                ? Colors.red
                                : AppColors.textSecondary,
                      ),
                      title: Text(
                        item.quizOptions[i],
                        style: TextStyle(
                          color: correct
                              ? Colors.green
                              : wrong
                                  ? Colors.red
                                  : null,
                        ),
                      ),
                      onTap: selected != null
                          ? null
                          : () => setLocal(() => selected = i),
                    );
                  }),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
