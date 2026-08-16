import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/models/chat_session.dart';
import 'package:mpsc_combine_ai/models/chat_subject.dart';
import 'package:mpsc_combine_ai/services/ai_avatar_service.dart';
import 'package:mpsc_combine_ai/services/ai_teacher_service.dart';
import 'package:mpsc_combine_ai/services/auth_service.dart';
import 'package:mpsc_combine_ai/services/chat_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';
import 'package:mpsc_combine_ai/utils/chat_categorizer.dart';
import 'package:mpsc_combine_ai/widgets/ai_avatar_widgets.dart';
import 'package:mpsc_combine_ai/widgets/chat_widgets.dart';
import 'package:share_plus/share_plus.dart';

class AiTeacherScreen extends StatefulWidget {
  const AiTeacherScreen({
    super.key,
    this.hideOuterChrome = false,
  });

  /// When embedded in [AiTeacherHubScreen], hide back button and outer title.
  final bool hideOuterChrome;

  @override
  State<AiTeacherScreen> createState() => _AiTeacherScreenState();
}

class _AiTeacherScreenState extends State<AiTeacherScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  String? _activeChatId;
  ChatSubject? _activeSubject;
  bool _isLoading = false;
  bool _isSwitchingChat = false;
  String? _errorMessage;
  String? _lastUserMessage;

  // AI Avatar module: only one message can be "speaking" at a time via the
  // single shared [aiAvatarProvider]. Correlated by timestamp because
  // [ChatMessage.copyWith] (used once a message's Firestore id resolves)
  // preserves the original timestamp even though it's a new object.
  StreamSubscription<AvatarPlaybackState>? _avatarSubscription;
  AvatarPlaybackState _avatarState = AvatarPlaybackState.idle;
  DateTime? _activeAvatarTimestamp;

  static const List<String> _quickSuggestions = [
    'एक शंका विचारा',
    'हा विषय सोप्या भाषेत समजावून सांगा',
    'या विषयाचा पुनरावलोकन सारांश द्या',
    'Explain this topic in English',
  ];

  String? get _uid => authService.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _messages.add(_welcomeMessage());
    _loadMostRecentChat();
    _avatarSubscription = aiAvatarProvider.stateStream.listen((state) {
      if (!mounted) return;
      setState(() => _avatarState = state);
    });
  }

  /// Resumes the student's last active chat automatically after login,
  /// instead of always starting from a blank screen. Falls back silently
  /// to the fresh welcome message already shown if there's no history yet
  /// (or it can't be reached) — this must never block the AI Teacher.
  Future<void> _loadMostRecentChat() async {
    final uid = _uid;
    if (uid == null) return;

    setState(() => _isSwitchingChat = true);
    try {
      final recent = await chatRepository.getMostRecentSession(uid);
      if (!mounted) return;
      if (recent == null) {
        setState(() => _isSwitchingChat = false);
        return;
      }

      final messages = await chatRepository.getMessages(uid, recent.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(messages.isEmpty ? [_welcomeMessage()] : messages);
        _activeChatId = recent.id;
        _activeSubject = recent.subject;
        _isSwitchingChat = false;
        _lastUserMessage = messages.isNotEmpty && messages.last.isUser
            ? messages.last.content
            : null;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSwitchingChat = false);
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _avatarSubscription?.cancel();
    aiAvatarProvider.stop();
    super.dispose();
  }

  // ─── AI Avatar (voice output) ───────────────────────────────────────────

  void _resetAvatar() {
    _activeAvatarTimestamp = null;
    aiAvatarProvider.stop();
  }

  Future<void> _toggleAvatarPlayback(ChatMessage message) async {
    final isActiveMessage = _activeAvatarTimestamp == message.timestamp;
    if (!isActiveMessage) {
      setState(() => _activeAvatarTimestamp = message.timestamp);
      await aiAvatarProvider.speak(message.content);
      return;
    }
    switch (_avatarState) {
      case AvatarPlaybackState.speaking:
        await aiAvatarProvider.pause();
      case AvatarPlaybackState.paused:
        await aiAvatarProvider.resume();
      case AvatarPlaybackState.idle:
      case AvatarPlaybackState.error:
      case AvatarPlaybackState.loading:
        await aiAvatarProvider.speak(message.content);
    }
  }

  ChatMessage _welcomeMessage() {
    return ChatMessage(
      role: ChatRole.assistant,
      content: 'नमस्कार! मी तुमचा MPSC AI शिक्षक आहे. तुम्ही मराठी किंवा '
          'इंग्रजीत कोणताही प्रश्न विचारू शकता — मी MPSC अभ्यासक्रमावर आधारित '
          'सोप्या भाषेत उत्तर देईन.',
      timestamp: DateTime.now(),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 160,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _titleFrom(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= 48) return trimmed;
    return '${trimmed.substring(0, 48).trimRight()}…';
  }

  // ─── New Chat / History ────────────────────────────────────────────────

  void _startNewChat() {
    if (_isLoading) return;
    _resetAvatar();
    setState(() {
      _messages
        ..clear()
        ..add(_welcomeMessage());
      _activeChatId = null;
      _activeSubject = null;
      _lastUserMessage = null;
      _errorMessage = null;
    });
    final state = _scaffoldKey.currentState;
    if (state != null && state.isEndDrawerOpen) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _switchToSession(ChatSession session) async {
    final uid = _uid;
    if (uid == null) return;
    Navigator.of(context).pop(); // close the drawer
    _resetAvatar();

    setState(() {
      _isSwitchingChat = true;
      _errorMessage = null;
    });

    try {
      final messages = await chatRepository.getMessages(uid, session.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(messages.isEmpty ? [_welcomeMessage()] : messages);
        _activeChatId = session.id;
        _activeSubject = session.subject;
        _isSwitchingChat = false;
        _lastUserMessage = messages.isNotEmpty && messages.last.isUser
            ? messages.last.content
            : null;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSwitchingChat = false);
      _showSnack(
        'चॅट लोड होऊ शकला नाही. कृपया पुन्हा प्रयत्न करा.\n'
        '(Could not load this chat. Please retry.)',
      );
    }
  }

  Future<void> _deleteSession(ChatSession session) async {
    final uid = _uid;
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('चॅट हटवायची आहे?'),
        content: Text('"${session.title}" ही चॅट कायमची हटवली जाईल.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('रद्द करा'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('हटवा'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await chatRepository.deleteSession(uid, session.id);
      if (session.id == _activeChatId && mounted) {
        _startNewChat();
      }
    } catch (_) {
      _showSnack(
        'चॅट हटवता आली नाही. कृपया पुन्हा प्रयत्न करा.\n(Could not delete chat.)',
      );
    }
  }

  // ─── Sending / persisting messages ─────────────────────────────────────

  Future<void> _ensureSession(String firstUserMessageText) async {
    final uid = _uid;
    if (uid == null || _activeChatId != null) return;

    final subject = ChatCategorizer.categorize(firstUserMessageText);
    final title = _titleFrom(firstUserMessageText);
    try {
      final chatId = await chatRepository.createSession(
        uid,
        title: title,
        subject: subject,
      );
      if (!mounted) return;
      setState(() {
        _activeChatId = chatId;
        _activeSubject = subject;
      });
    } catch (_) {
      // Firestore unavailable — chat continues in-memory only for this session.
    }
  }

  Future<void> _persistMessage(ChatMessage message) async {
    final uid = _uid;
    final chatId = _activeChatId;
    if (uid == null || chatId == null) return;
    try {
      final id = await chatRepository.addMessage(uid, chatId, message);
      if (!mounted) return;
      final index = _messages.indexOf(message);
      if (index != -1) {
        setState(() => _messages[index] = message.copyWith(id: id));
      }
    } catch (_) {
      // Best-effort only — losing persistence must never break the chat.
    }
  }

  Future<void> _touchSession() async {
    final uid = _uid;
    final chatId = _activeChatId;
    if (uid == null || chatId == null) return;
    try {
      await chatRepository.touchSession(uid, chatId);
    } catch (_) {
      // Ignore — recency ordering in the history drawer is a nice-to-have.
    }
  }

  Future<void> _sendUserMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;

    final isFirstMessage = _activeChatId == null;
    final userMessage = ChatMessage(
      role: ChatRole.user,
      content: trimmed,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _lastUserMessage = trimmed;
      _errorMessage = null;
      _inputController.clear();
    });
    _scrollToBottom();

    if (isFirstMessage) {
      await _ensureSession(trimmed);
    }
    await _persistMessage(userMessage);

    await _requestReplyFor(trimmed);
  }

  Future<void> _requestReplyFor(String userMessage) async {
    final history = _messages.length > 1
        ? _messages.sublist(0, _messages.length - 1)
        : const <ChatMessage>[];

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final reply = await aiTeacherService.sendMessage(
        history: history,
        userMessage: userMessage,
      );
      if (!mounted) return;
      final assistantMessage = ChatMessage(
        role: ChatRole.assistant,
        content: reply,
        timestamp: DateTime.now(),
      );
      setState(() {
        _messages.add(assistantMessage);
        _isLoading = false;
      });
      await _persistMessage(assistantMessage);
      await _touchSession();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e is AiServiceException
            ? e.message
            : 'काहीतरी चुकले. कृपया पुन्हा प्रयत्न करा.\n'
                '(Something went wrong. Please retry.)';
      });
    }
    _scrollToBottom();
  }

  void _retryLast() {
    final message = _lastUserMessage;
    if (message == null || _isLoading) return;
    _requestReplyFor(message);
  }

  Future<void> _regenerate(ChatMessage assistantMessage) async {
    if (_isLoading) return;
    final index = _messages.indexOf(assistantMessage);
    if (index <= 0) return;
    final precedingUser = _messages[index - 1];
    if (!precedingUser.isUser) return;

    final history = index - 1 > 0 ? _messages.sublist(0, index - 1) : const <ChatMessage>[];

    setState(() {
      _messages.removeAt(index);
      _lastUserMessage = precedingUser.content;
      _isLoading = true;
      _errorMessage = null;
    });
    _scrollToBottom();

    try {
      final reply = await aiTeacherService.sendMessage(
        history: history,
        userMessage: precedingUser.content,
      );
      if (!mounted) return;

      final newAssistantMessage = ChatMessage(
        role: ChatRole.assistant,
        content: reply,
        timestamp: DateTime.now(),
      );
      setState(() {
        _messages.add(newAssistantMessage);
        _isLoading = false;
      });

      final uid = _uid;
      final chatId = _activeChatId;
      if (uid != null && chatId != null) {
        try {
          if (assistantMessage.id != null) {
            await chatRepository.updateMessageContent(
              uid,
              chatId,
              assistantMessage.id!,
              reply,
            );
            if (mounted) {
              final idx = _messages.indexOf(newAssistantMessage);
              if (idx != -1) {
                setState(
                  () => _messages[idx] = newAssistantMessage.copyWith(id: assistantMessage.id),
                );
              }
            }
          } else {
            await _persistMessage(newAssistantMessage);
          }
          await _touchSession();
        } catch (_) {
          // Best-effort — the regenerated reply is already visible either way.
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        // Put the original reply back so nothing is lost on failure.
        _messages.insert(index, assistantMessage);
        _errorMessage = e is AiServiceException
            ? e.message
            : 'काहीतरी चुकले. कृपया पुन्हा प्रयत्न करा.\n'
                '(Something went wrong. Please retry.)';
      });
    }
    _scrollToBottom();
  }

  // ─── Copy / Share ───────────────────────────────────────────────────────

  void _copyMessage(ChatMessage message) {
    Clipboard.setData(ClipboardData(text: message.content));
    _showSnack('मेसेज कॉपी झाला! (Copied!)');
  }

  Future<void> _shareMessage(ChatMessage message) async {
    await SharePlus.instance.share(
      ShareParams(
        text: message.content,
        subject: 'MPSC COMBINE AI — AI Teacher',
      ),
    );
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth > 600 ? 24.0 : 16.0;
    final maxContentWidth = screenWidth > 800 ? 800.0 : double.infinity;
    final showSuggestions = _messages.length <= 1 && !_isLoading && !_isSwitchingChat;

    return Scaffold(
      key: _scaffoldKey,
      appBar: widget.hideOuterChrome
          ? AppBar(
              toolbarHeight: 48,
              automaticallyImplyLeading: false,
              title: _activeSubject != null
                  ? ChatSubjectBadge(
                      subject: _activeSubject!,
                      dense: true,
                      onDark: true,
                    )
                  : const Text(
                      'Ask Doubts',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
              actions: [
                IconButton(
                  tooltip: 'नवीन चॅट (New Chat)',
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: _isLoading ? null : _startNewChat,
                ),
                IconButton(
                  tooltip: 'चॅट इतिहास (History)',
                  icon: const Icon(Icons.history_rounded),
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                ),
              ],
            )
          : AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'AI Teacher',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (_activeSubject != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: ChatSubjectBadge(
                        subject: _activeSubject!,
                        dense: true,
                        onDark: true,
                      ),
                    ),
                ],
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: [
                IconButton(
                  tooltip: 'नवीन चॅट (New Chat)',
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: _isLoading ? null : _startNewChat,
                ),
                IconButton(
                  tooltip: 'चॅट इतिहास (History)',
                  icon: const Icon(Icons.history_rounded),
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                ),
              ],
            ),
      endDrawer: ChatHistoryDrawer(
        uid: _uid,
        activeChatId: _activeChatId,
        onNewChat: _startNewChat,
        onSelectSession: _switchToSession,
        onDeleteSession: _deleteSession,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: Column(
              children: [
                Expanded(
                  child: _isSwitchingChat
                      ? const Center(
                          child: CircularProgressIndicator(color: AppColors.orange),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            16,
                            horizontalPadding,
                            12,
                          ),
                          itemCount:
                              _messages.length + (_isLoading || _errorMessage != null ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index < _messages.length) {
                              final message = _messages[index];
                              final isLastAssistant = !message.isUser &&
                                  index == _messages.length - 1 &&
                                  index > 0 &&
                                  !_isLoading;
                              final bubble = ChatBubble(
                                message: message,
                                onCopy: () => _copyMessage(message),
                                onShare: () => _shareMessage(message),
                                onRegenerate:
                                    isLastAssistant ? () => _regenerate(message) : null,
                              );
                              if (message.isUser) return bubble;
                              // AI Avatar module: a voice/animated-avatar header
                              // above each AI answer. The chat bubble itself
                              // (Markdown, copy/share/regenerate) is untouched.
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AiAvatarHeader(
                                    isActive: _activeAvatarTimestamp == message.timestamp,
                                    state: _avatarState,
                                    onTogglePlay: () => _toggleAvatarPlayback(message),
                                  ),
                                  bubble,
                                ],
                              );
                            }
                            if (_isLoading) {
                              return const TypingIndicatorBubble();
                            }
                            return ChatErrorBubble(
                              message: _errorMessage!,
                              onRetry: _retryLast,
                            );
                          },
                        ),
                ),
                if (showSuggestions)
                  ChatQuickSuggestions(
                    suggestions: _quickSuggestions,
                    onSelected: (text) {
                      _inputController.text = text;
                      _inputController.selection = TextSelection.collapsed(
                        offset: text.length,
                      );
                    },
                    horizontalPadding: horizontalPadding,
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding,
                    6,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.mic_none_rounded, size: 18),
                        label: const Text('Voice doubt'),
                        onPressed: _isLoading
                            ? null
                            : () async {
                                final text = await showDialog<String>(
                                  context: context,
                                  builder: (ctx) {
                                    final c = TextEditingController();
                                    return AlertDialog(
                                      title: const Text('Voice / dictate doubt'),
                                      content: TextField(
                                        controller: c,
                                        autofocus: true,
                                        maxLines: 3,
                                        decoration: const InputDecoration(
                                          hintText: 'Type or paste dictated question',
                                          prefixIcon: Icon(Icons.mic_rounded),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, c.text),
                                          child: const Text('Ask'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                                if (text != null && text.trim().isNotEmpty) {
                                  await _sendUserMessage(text.trim());
                                }
                              },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.border_color_rounded, size: 18),
                        label: const Text('Whiteboard'),
                        onPressed: _isLoading
                            ? null
                            : () {
                                showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (ctx) => const _SimpleWhiteboardSheet(),
                                );
                              },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: const Text('Diagram'),
                        onPressed: _isLoading
                            ? null
                            : () => _sendUserMessage(
                                  'Generate a clear exam-oriented diagram description '
                                  'or ASCII/Markdown diagram for the current topic, '
                                  'with labeled parts I can revise from.',
                                ),
                      ),
                    ],
                  ),
                ),
                ChatMessageInputBar(
                  controller: _inputController,
                  enabled: !_isLoading && !_isSwitchingChat,
                  onSend: _sendUserMessage,
                  horizontalPadding: horizontalPadding,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lightweight scratch whiteboard — freehand notes while chatting with AI Teacher.
class _SimpleWhiteboardSheet extends StatefulWidget {
  const _SimpleWhiteboardSheet();

  @override
  State<_SimpleWhiteboardSheet> createState() => _SimpleWhiteboardSheetState();
}

class _SimpleWhiteboardSheetState extends State<_SimpleWhiteboardSheet> {
  final List<Offset?> _points = [];

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.55;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Whiteboard',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(_points.clear),
                    child: const Text('Clear'),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.navy.withValues(alpha: 0.12)),
                ),
                child: GestureDetector(
                  onPanUpdate: (d) => setState(() => _points.add(d.localPosition)),
                  onPanEnd: (_) => setState(() => _points.add(null)),
                  child: CustomPaint(
                    painter: _BoardPainter(_points),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.points);

  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.navy
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a != null && b != null) {
        canvas.drawLine(a, b, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) => true;
}
