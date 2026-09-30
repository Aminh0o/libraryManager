import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/chat_message.dart';
import '../providers/library_provider.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_states.dart';

/// Phase 19: the LAN staff-chat view. A live transcript of the host-held chat
/// buffer plus a compose box. It is reached only from a rail destination gated
/// on `flags.isEnabled('lanChat') && provider.canWrite`, so it never renders for
/// a viewer (who can neither read nor post over the staff-only `/chat` route).
///
/// The transcript is refreshed on a fixed poll rather than a push channel: the
/// embedded server speaks request/response HTTP, and a 2s poll keeps this a
/// genuinely working feature across the host<->client seam without introducing
/// a WebSocket whose lifecycle we could not also verify end to end. Every
/// message shown is one the host actually stored -- nothing is simulated.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _poll;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Prime once on the first frame, then poll on a fixed cadence while open.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    // The Send button previously stayed enabled on an empty input and
    // silently returned from `_send`, giving the operator no feedback that
    // nothing went out. Listening to the controller lets the button disable
    // itself the moment the field becomes whitespace-only.
    _input.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    try {
      await context.read<LibraryProvider>().refreshChat();
    } catch (_) {
      // A transient read failure simply leaves the last good transcript; the
      // next poll retries. No per-tick error toast (that would spam).
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<LibraryProvider>();
    setState(() => _sending = true);
    try {
      await provider.sendChatMessage(text);
      if (!mounted) return;
      _input.clear();
    } catch (_) {
      // The provider only returns here on a real send failure (server down /
      // host refused), so surface it honestly rather than pretend delivery.
      messenger.showSnackBar(SnackBar(content: Text(l10n.chatUnavailable)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<LibraryProvider>();
    final messages = provider.chatMessages;
    final me = provider.sessionUsername;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? AppEmptyState(
                  icon: Icons.forum_outlined,
                  title: l10n.chatEmpty,
                  compact: true,
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: AppSpacing.allLg,
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _Bubble(
                    message: messages[i],
                    isMe: me != null && messages[i].sender == me,
                  ),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: l10n.chatInputHint,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: (_sending || _input.text.trim().isEmpty)
                      ? null
                      : _send,
                  icon: const Icon(Icons.send),
                  label: Text(l10n.chatSend),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.isMe});

  final ChatMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    // Own messages use the primary surface; others a neutral container --
    // both brightness-correct in dark mode (the old orange/grey.shade200/
    // black87 triple was unreadable on dark).
    final bg = isMe ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = isMe ? scheme.onPrimary : scheme.onSurface;
    return Align(
      alignment: isMe
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(AppRadius.lg),
            topEnd: const Radius.circular(AppRadius.lg),
            bottomStart: Radius.circular(isMe ? AppRadius.lg : AppRadius.sm),
            bottomEnd: Radius.circular(isMe ? AppRadius.sm : AppRadius.lg),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              '${message.sender} · ${_fmt(message.sentAt)}',
              style: txt.labelSmall?.copyWith(color: fg.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: AppSpacing.xs / 2),
            Text(message.text, style: txt.bodyMedium?.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
