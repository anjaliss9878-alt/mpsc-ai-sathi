import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/pyq_item.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/link_launcher.dart';
import 'package:mpsc_combine_ai/services/pyq_repository.dart';
import 'package:mpsc_combine_ai/services/student_progress_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/async_state_widgets.dart';

class PyqScreen extends StatefulWidget {
  const PyqScreen({super.key});

  @override
  State<PyqScreen> createState() => _PyqScreenState();
}

class _PyqScreenState extends State<PyqScreen> {
  int? _year;
  String? _exam;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Previous Year Questions')),
      body: StreamBuilder<List<PyqItem>>(
        stream: pyqRepository.watchPublished(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorState(
              message: 'Could not load PYQs.\n${snapshot.error}',
            );
          }
          if (!snapshot.hasData) return const LoadingState();

          final all = snapshot.data!;
          final years = all
              .map((e) => e.year)
              .whereType<int>()
              .toSet()
              .toList()
            ..sort((a, b) => b.compareTo(a));
          final exams = all
              .map((e) => e.examName.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

          var items = all;
          if (_year != null) {
            items = items.where((e) => e.year == _year).toList();
          }
          if (_exam != null && _exam!.isNotEmpty) {
            items = items.where((e) => e.examName == _exam).toList();
          }
          if (_query.trim().isNotEmpty) {
            final q = _query.trim().toLowerCase();
            items = items
                .where(
                  (e) =>
                      e.title.toLowerCase().contains(q) ||
                      e.subtitle.toLowerCase().contains(q) ||
                      e.question.toLowerCase().contains(q) ||
                      e.examName.toLowerCase().contains(q),
                )
                .toList();
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search PYQ…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('All years'),
                      selected: _year == null,
                      onSelected: (_) => setState(() => _year = null),
                    ),
                    const SizedBox(width: 8),
                    ...years.map(
                      (y) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text('$y'),
                          selected: _year == y,
                          onSelected: (_) => setState(() => _year = y),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (exams.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All exams'),
                        selected: _exam == null,
                        onSelected: (_) => setState(() => _exam = null),
                      ),
                      const SizedBox(width: 8),
                      ...exams.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(e),
                            selected: _exam == e,
                            onSelected: (_) => setState(() => _exam = e),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: items.isEmpty
                    ? const EmptyState(
                        message: 'No PYQs match these filters.',
                        icon: Icons.history_edu_outlined,
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
                                Icons.description_rounded,
                                color: AppColors.navy,
                              ),
                              title: Text(
                                item.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (item.year != null) '${item.year}',
                                  if (item.examName.isNotEmpty) item.examName,
                                  if (item.subtitle.isNotEmpty) item.subtitle,
                                ].join(' · '),
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _openItem(context, item),
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

  Future<void> _openItem(BuildContext context, PyqItem item) async {
    if (item.isStructuredQuestion) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.question,
                      style: const TextStyle(height: 1.45),
                    ),
                    if (item.options.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ...List.generate(item.options.length, (i) {
                        final letter = String.fromCharCode(65 + i);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('$letter. ${item.options[i]}'),
                        );
                      }),
                    ],
                    if (item.answer.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Answer',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(item.answer),
                    ],
                    if (item.explanation.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Explanation',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(item.explanation),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final uid = authService.currentUser?.uid;
                              if (uid == null) return;
                              await studentProgressRepository.toggleBookmark(
                                uid: uid,
                                id: 'pyq_${item.id}',
                                type: 'pyq',
                                title: item.title,
                                subtitle: item.subtitle,
                                refId: item.id,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.bookmark_border_rounded),
                            label: const Text('Bookmark'),
                          ),
                        ),
                        if (item.fileUrl.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  openExternalLink(context, item.fileUrl),
                              child: const Text('Open PDF'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      return;
    }
    if (item.fileUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file linked for this PYQ yet.')),
      );
      return;
    }
    await openExternalLink(context, item.fileUrl);
  }
}
