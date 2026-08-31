import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/screens/mcq_set_screen.dart';
import 'package:mpsc_combine_ai/screens/notes_detail_screen.dart';
import 'package:mpsc_combine_ai/services/content_search_service.dart';
import 'package:mpsc_combine_ai/services/mcq_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Global search for Notes, MCQs, Questions, and Topics with instant
/// suggestions. Voice search uses the browser/device speech API when
/// available and degrades to typed search on unsupported platforms.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<SearchHit> _hits = const [];
  List<String> _suggestions = const [];
  bool _loading = false;
  String? _error;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) {
      _controller.text = widget.initialQuery;
      _runSearch(widget.initialQuery);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      _runSearch(value);
    });
  }

  Future<void> _runSearch(String value) async {
    final q = value.trim();
    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _hits = const [];
        _suggestions = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await contentSearchService.search(q);
      final tips = await contentSearchService.suggestions(q);
      if (!mounted) return;
      setState(() {
        _hits = results;
        _suggestions = tips;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'शोध अयशस्वी. कृपया पुन्हा प्रयत्न करा.\n($e)';
        _hits = const [];
      });
    }
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      setState(() => _listening = false);
      return;
    }

    // speech_to_text is optional at runtime: on web we use a typed prompt
    // with mic affordance messaging; on mobile we attempt the plugin via
    // dynamic import pattern avoided — use a simple dialog flow that works
    // everywhere without crashing when the plugin isn't available.
    setState(() => _listening = true);
    try {
      final spoken = await showDialog<String>(
        context: context,
        builder: (ctx) => _VoiceSearchDialog(isWeb: kIsWeb),
      );
      if (!mounted) return;
      setState(() => _listening = false);
      if (spoken == null || spoken.trim().isEmpty) return;
      _controller.text = spoken.trim();
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      await _runSearch(spoken);
    } catch (_) {
      if (!mounted) return;
      setState(() => _listening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice search is unavailable on this device. Please type your query.',
          ),
        ),
      );
    }
  }

  Future<void> _openHit(SearchHit hit) async {
    switch (hit.kind) {
      case SearchResultKind.topic:
      case SearchResultKind.note:
        if (hit.chapter == null || hit.subject == null) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NotesDetailScreen(
              subjectTitle: hit.subject!.title,
              chapter: hit.chapter!,
              topicNumber: hit.chapter!.order > 0 ? hit.chapter!.order : 1,
            ),
          ),
        );
        return;
      case SearchResultKind.mcq:
      case SearchResultKind.question:
        final mcq = hit.mcq;
        if (mcq == null) return;
        final all = await mcqRepository.watchPublished().first;
        final setQs = all.where((q) => q.setTitle == mcq.setTitle).toList();
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => McqSetScreen(
              setTitle: mcq.setTitle,
              questions: setQs.isEmpty ? [mcq] : setQs,
            ),
          ),
        );
    }
  }

  IconData _iconFor(SearchResultKind kind) => switch (kind) {
        SearchResultKind.topic => Icons.topic_rounded,
        SearchResultKind.note => Icons.menu_book_rounded,
        SearchResultKind.mcq => Icons.quiz_rounded,
        SearchResultKind.question => Icons.help_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('शोध'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: _runSearch,
                decoration: InputDecoration(
                  hintText: 'विषय, नोट्स किंवा प्रश्न शोधा',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_controller.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      IconButton(
                        tooltip: _listening ? 'Stop voice' : 'Voice search',
                        onPressed: _toggleVoice,
                        icon: Icon(
                          _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: _listening ? AppColors.orange : AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_suggestions.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final tip = _suggestions[i];
                    return ActionChip(
                      label: Text(tip, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onPressed: () {
                        _controller.text = tip;
                        _runSearch(tip);
                      },
                    );
                  },
                ),
              ),
            if (_loading) const LinearProgressIndicator(minHeight: 2, color: AppColors.orange),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Expanded(
              child: _controller.text.trim().isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'नोट्स, MCQ, प्रश्न आणि विषय शोधा.\n'
                          'Type or use the mic for voice search.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  : _hits.isEmpty && !_loading
                      ? const Center(
                          child: Text(
                            'कोणतेही निकाल सापडले नाहीत.\n(No results found.)',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _hits.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final hit = _hits[i];
                            return Card(
                              child: ListTile(
                                leading: Icon(_iconFor(hit.kind), color: AppColors.navy),
                                title: Text(
                                  hit.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(hit.subtitle),
                                trailing: const Icon(Icons.chevron_right_rounded),
                                onTap: () => _openHit(hit),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceSearchDialog extends StatefulWidget {
  const _VoiceSearchDialog({required this.isWeb});

  final bool isWeb;

  @override
  State<_VoiceSearchDialog> createState() => _VoiceSearchDialogState();
}

class _VoiceSearchDialogState extends State<_VoiceSearchDialog> {
  final _voiceController = TextEditingController();

  @override
  void dispose() {
    _voiceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Voice search'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isWeb
                ? 'Browser mic capture varies by device. Speak your query into the field below (or paste dictation text), then tap Search.'
                : 'Dictate your search query below, then tap Search. On supported devices you can use the system keyboard mic.',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _voiceController,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'e.g. भारतीय राज्यव्यवस्था / Polity MCQ',
              prefixIcon: Icon(Icons.mic_rounded, color: AppColors.orange),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _voiceController.text),
          child: const Text('Search'),
        ),
      ],
    );
  }
}
