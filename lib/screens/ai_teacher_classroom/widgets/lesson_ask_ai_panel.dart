import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/models/rag_source.dart';
import 'package:mpsc_combine_ai/rag/rag_exceptions.dart';
import 'package:mpsc_combine_ai/rag/rag_source_filter.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_system/generated_lesson.dart';
import 'package:mpsc_combine_ai/services/personalized_multi_rag_service.dart';
import 'package:mpsc_combine_ai/services/rag_source_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/widgets/rag_citation_block.dart';
import 'package:mpsc_combine_ai/widgets/rag_source_picker.dart';

/// Follow-up doubts for the current AI lesson. Uses the same RAG pipeline as
/// AI Teacher: retrieve published chunks → Gemini → grounded answer + citations.
class LessonAskAiPanel extends StatefulWidget {
  const LessonAskAiPanel({super.key, required this.lesson});

  final GeneratedLesson lesson;

  @override
  State<LessonAskAiPanel> createState() => _LessonAskAiPanelState();
}

class _LessonAskAiPanelState extends State<LessonAskAiPanel> {
  final _controller = TextEditingController();
  final _messages = <ChatMessage>[];
  bool _busy = false;
  RagSourceFilter _filter = RagSourceFilter.allPublished;
  List<RagSource> _sources = const [];
  StreamSubscription<List<RagSource>>? _sourcesSub;

  @override
  void initState() {
    super.initState();
    _filter = RagSourceFilter.forSubject(subject: widget.lesson.subjectName);
    _sourcesSub = ragSourceRepository.watchPublishedReady().listen((sources) {
      if (!mounted) return;
      setState(() => _sources = sources);
    });
    _messages.add(
      ChatMessage(
        role: ChatRole.assistant,
        content:
            'या धड्याबाबत शंका विचारा — ${widget.lesson.topicName}. '
            'मी ${widget.lesson.subjectName} शिक्षक आहे. उत्तरे प्रकाशित MPSC '
            'स्रोतांवर आधारित असतील.',
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _sourcesSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    _controller.clear();
    setState(() {
      _busy = true;
      _messages.add(
        ChatMessage(
          role: ChatRole.user,
          content: text,
          timestamp: DateTime.now(),
        ),
      );
    });
    try {
      final history = _messages.length > 1
          ? _messages.sublist(0, _messages.length - 1)
          : const <ChatMessage>[];
      final reply = await answerWithStudentRag(
        question: '${widget.lesson.topicName}. $text',
        history: history,
        filter: _filter,
        subjectHint: widget.lesson.subjectName,
        fromAiTeacher: true,
        chapterId: widget.lesson.chapterId,
        subjectId: widget.lesson.subjectId,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            content: reply.markdown,
            timestamp: DateTime.now(),
            citations: reply.citations,
          ),
        );
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            role: ChatRole.assistant,
            content: e is RagException
                ? e.message
                : 'उत्तर मिळाले नाही. कृपया पुन्हा प्रयत्न करा.',
            timestamp: DateTime.now(),
          ),
        );
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ExpansionTile(
          title: const Text(
            '📚 Sources',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: RagSourcePicker(
                sources: _sources,
                filter: _filter,
                onChanged: (next) => setState(() => _filter = next),
              ),
            ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final m = _messages[index];
              final mine = m.isUser;
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: mine ? AppColors.navy : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: mine
                        ? null
                        : Border.all(color: AppColors.navy.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.content,
                        style: TextStyle(
                          color: mine ? Colors.white : AppColors.textPrimary,
                          height: 1.45,
                        ),
                      ),
                      if (!mine && m.citations.isNotEmpty)
                        RagCitationBlock(citations: m.citations),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_busy,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'शंका लिहा…',
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _busy ? null : _send,
                style: IconButton.styleFrom(backgroundColor: AppColors.navy),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
