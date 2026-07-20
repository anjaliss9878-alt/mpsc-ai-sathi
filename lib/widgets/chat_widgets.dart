import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:mpsc_combine_ai/models/chat_message.dart';
import 'package:mpsc_combine_ai/models/chat_session.dart';
import 'package:mpsc_combine_ai/models/chat_subject.dart';
import 'package:mpsc_combine_ai/services/chat_repository.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Small colored chip showing a chat's auto-detected MPSC subject.
class ChatSubjectBadge extends StatelessWidget {
  const ChatSubjectBadge({
    super.key,
    required this.subject,
    this.dense = false,
    this.onDark = false,
  });

  final ChatSubject subject;
  final bool dense;

  /// Use a light-on-dark palette when placed over the navy AppBar.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final foreground = onDark ? Colors.white : subject.color;
    final background =
        onDark ? Colors.white.withValues(alpha: 0.16) : subject.color.withValues(alpha: 0.12);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(subject.icon, size: dense ? 11 : 13, color: foreground),
          const SizedBox(width: 4),
          Text(
            subject.label,
            style: TextStyle(
              fontSize: dense ? 10 : 11,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// One chat bubble. Assistant replies render as Markdown (bold, bullet
/// lists, tables, headings, ...); user messages render as plain text.
/// Copy/Share are always available; Regenerate only when [onRegenerate] is
/// provided (i.e. this is the latest assistant reply).
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.onCopy,
    required this.onShare,
    this.onRegenerate,
  });

  final ChatMessage message;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: isUser ? 10 : 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.82,
            ),
            decoration: BoxDecoration(
              color: isUser ? AppColors.navy : AppColors.cardWhite,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isUser ? 14 : 2),
                bottomRight: Radius.circular(isUser ? 2 : 14),
              ),
              boxShadow: isUser
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: isUser
                ? Text(
                    message.content,
                    style: const TextStyle(color: Colors.white, height: 1.4),
                  )
                : MarkdownBody(
                    data: message.content,
                    selectable: true,
                    styleSheet: _markdownStyleSheet(),
                  ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: 10, left: isUser ? 0 : 4, right: isUser ? 4 : 0),
            child: _MessageActionsRow(
              onCopy: onCopy,
              onShare: onShare,
              onRegenerate: onRegenerate,
            ),
          ),
        ],
      ),
    );
  }

  MarkdownStyleSheet _markdownStyleSheet() {
    return MarkdownStyleSheet(
      p: const TextStyle(color: AppColors.textPrimary, height: 1.45, fontSize: 14.5),
      strong: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800),
      em: const TextStyle(color: AppColors.textPrimary, fontStyle: FontStyle.italic),
      listBullet: const TextStyle(color: AppColors.textPrimary, height: 1.45),
      h1: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 19),
      h2: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 17),
      h3: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 15.5),
      code: TextStyle(
        backgroundColor: AppColors.navy.withValues(alpha: 0.06),
        color: AppColors.navy,
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      blockquoteDecoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: AppColors.orange, width: 3)),
      ),
      tableBorder: TableBorder.all(color: AppColors.navy.withValues(alpha: 0.15)),
      tableHead: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy),
      tableBody: const TextStyle(color: AppColors.textPrimary),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.navy.withValues(alpha: 0.15))),
      ),
    );
  }
}

class _MessageActionsRow extends StatelessWidget {
  const _MessageActionsRow({
    required this.onCopy,
    required this.onShare,
    this.onRegenerate,
  });

  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionIcon(icon: Icons.copy_rounded, tooltip: 'कॉपी करा (Copy)', onTap: onCopy),
        _ActionIcon(icon: Icons.ios_share_rounded, tooltip: 'शेअर करा (Share)', onTap: onShare),
        if (onRegenerate != null)
          _ActionIcon(
            icon: Icons.refresh_rounded,
            tooltip: 'पुन्हा तयार करा (Regenerate)',
            onTap: onRegenerate!,
          ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 15, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// Animated "AI is typing" bubble — three softly bouncing dots.
class TypingIndicatorBubble extends StatefulWidget {
  const TypingIndicatorBubble({super.key});

  @override
  State<TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<TypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = (_controller.value - i * 0.2) % 1.0;
                final bounce = 1 - (2 * t - 1).abs();
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Transform.translate(
                    offset: Offset(0, -4 * bounce),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class ChatErrorBubble extends StatelessWidget {
  const ChatErrorBubble({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Text(
                  'त्रुटी',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.red,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(color: AppColors.textPrimary, height: 1.4),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('पुन्हा प्रयत्न करा'),
                style: TextButton.styleFrom(foregroundColor: AppColors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatQuickSuggestions extends StatelessWidget {
  const ChatQuickSuggestions({
    super.key,
    required this.suggestions,
    required this.onSelected,
    required this.horizontalPadding,
  });

  final List<String> suggestions;
  final ValueChanged<String> onSelected;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return ActionChip(
            label: Text(suggestion),
            backgroundColor: AppColors.navy.withValues(alpha: 0.06),
            labelStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            onPressed: () => onSelected(suggestion),
          );
        },
      ),
    );
  }
}

class ChatMessageInputBar extends StatelessWidget {
  const ChatMessageInputBar({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.horizontalPadding,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSend;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.navy.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: onSend,
              decoration: InputDecoration(
                hintText: 'मराठी किंवा इंग्रजीत प्रश्न टाइप करा…',
                filled: true,
                fillColor: AppColors.cardWhite,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: enabled ? AppColors.orange : AppColors.orange.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: enabled ? () => onSend(controller.text) : null,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ChatGPT-like history side panel: lists all saved sessions for [uid],
/// newest first, grouped visually by subject badge, with New Chat and
/// per-session delete actions.
class ChatHistoryDrawer extends StatelessWidget {
  const ChatHistoryDrawer({
    super.key,
    required this.uid,
    required this.activeChatId,
    required this.onNewChat,
    required this.onSelectSession,
    required this.onDeleteSession,
  });

  final String? uid;
  final String? activeChatId;
  final VoidCallback onNewChat;
  final ValueChanged<ChatSession> onSelectSession;
  final ValueChanged<ChatSession> onDeleteSession;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.navyDark, AppColors.navy, AppColors.navyLight],
                ),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'चॅट इतिहास',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onNewChat,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
                  icon: const Icon(Icons.add_comment_rounded),
                  label: const Text('नवीन चॅट (New Chat)'),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildSessionList(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionList(BuildContext context) {
    final currentUid = uid;
    if (currentUid == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'चॅट इतिहास पाहण्यासाठी लॉगिन आवश्यक आहे.\n'
            '(Login is required to view chat history.)',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return StreamBuilder<List<ChatSession>>(
      stream: chatRepository.watchSessions(currentUid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.orange),
          );
        }
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'चॅट इतिहास लोड होऊ शकला नाही.\n(Could not load chat history.)',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }

        final sessions = snapshot.data ?? const <ChatSession>[];
        if (sessions.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'अजून कोणतीही चॅट सेव्ह झालेली नाही.\nप्रश्न विचारून सुरुवात करा!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: sessions.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
          itemBuilder: (context, index) {
            final session = sessions[index];
            final isActive = session.id == activeChatId;
            return ListTile(
              selected: isActive,
              selectedTileColor: AppColors.orange.withValues(alpha: 0.08),
              leading: CircleAvatar(
                backgroundColor: session.subject.color.withValues(alpha: 0.15),
                child: Icon(session.subject.icon, color: session.subject.color, size: 18),
              ),
              title: Text(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              subtitle: Text(
                session.subject.label,
                style: TextStyle(
                  color: session.subject.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: IconButton(
                tooltip: 'हटवा (Delete)',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => onDeleteSession(session),
              ),
              onTap: () => onSelectSession(session),
            );
          },
        );
      },
    );
  }
}
