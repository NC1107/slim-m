// SPDX-License-Identifier: Apache-2.0
/// The conversation: history, live arrivals, search, and the composer.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../ids.dart';
import '../providers/admin_providers.dart';
import '../providers/channel_search_controller.dart';
import '../providers/message_actions.dart';
import '../providers/message_extras.dart';
import '../providers/pins_controller.dart';
import '../providers/providers.dart';
import '../providers/sync_controller.dart';
import '../routing/breakpoints.dart';
import '../widgets/channel_header.dart';
import '../widgets/channel_search.dart';
import '../widgets/composer.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/member_pane.dart';
import '../widgets/message_context_menu.dart';
import '../widgets/message_row.dart';
import '../widgets/report_dialog.dart';

export '../ids.dart' show newMessageId;

/// One channel's messages.
class ChannelScreen extends ConsumerStatefulWidget {
  const ChannelScreen({required this.channelId, super.key});

  final String channelId;

  @override
  ConsumerState<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends ConsumerState<ChannelScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  /// The query text only; the search itself (open, hits, failure) lives in
  /// [channelSearchProvider], which the compact app bar drives too.
  final _searchController = TextEditingController();

  /// The message currently swapped into its inline edit field, if any. At
  /// most one at a time: starting a new edit implicitly cancels another.
  String? _editingId;

  /// The highest seq this state has already asked the store and server to
  /// mark read, per channel. Keyed by channel because this state outlives a
  /// channel switch: [ConversationPane] builds this widget with no key, so
  /// navigating between channels reuses the same [State] rather than a fresh
  /// one. Without the guard, every rebuild of an already-read channel (a
  /// reaction landing, a typing indicator, anything) would re-fire both
  /// calls for a seq that is already recorded as read.
  final Map<String, int> _markedReadSeq = {};

  @override
  void initState() {
    super.initState();
    // Hydrates the reaction/attachment/poll cache for the visible window,
    // which is what makes it correct after a restart: the local database
    // has no columns for any of the three (see message_extras.dart), and
    // sync only ever fetches messages newer than the cursor, so an old
    // message's enrichment would otherwise never come back. Best-effort and
    // silent: a failure here just leaves the cache as it was, and the row
    // itself still renders from the local store either way.
    unawaited(_hydrateExtras());
  }

  @override
  void didUpdateWidget(ChannelScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This State outlives a channel switch (see [_markedReadSeq]), so the
    // field would otherwise still hold the previous channel's query.
    if (oldWidget.channelId != widget.channelId) _searchController.clear();
  }

  Future<void> _hydrateExtras() async {
    try {
      final recent =
          await ref.read(apiProvider).listMessages(widget.channelId, limit: 50);
      if (!mounted) return;
      ref.read(messageExtrasProvider.notifier).applyMessages(recent);
    } on api.ApiException {
      // Nothing useful to do; a live event or the next channel open corrects it.
    }
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Sends, showing the message immediately and reconciling with the server's
  /// copy when it lands. The id is generated here and reused on retry, so a
  /// retry after an uncertain failure can never post twice. The field is
  /// cleared before the first await, so two calls in one turn cannot both
  /// read the same text: the second finds it empty and returns.
  Future<void> _send(List<String> attachmentIds) async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();

    final store = await ref.read(storeProvider.future);
    final session = ref.read(sessionProvider);
    final id = newMessageId();

    await store.addPending(
      id: id,
      channelId: widget.channelId,
      authorId: session.tokens?.userId ?? '',
      content: text,
    );
    _scrollToLatest();

    try {
      final sent = await ref.read(apiProvider).sendMessage(
            channelId: widget.channelId,
            id: id,
            content: text,
            attachmentIds: attachmentIds,
          );
      // Lands on the same row, because it carries the same id.
      await store.applyMessage(sent);
      ref.read(messageExtrasProvider.notifier).applyMessage(sent);
    } on api.ApiException {
      // Keep the text as a failed row rather than dropping it; the user can
      // retry or discard, and either way they do not lose what they wrote.
      // A retry only resends the text: the local store has nowhere to keep
      // the attachment ids for a message that has not landed yet, so a
      // retried send after a failure goes out without them.
      await store.markFailed(id);
    }
    _scrollToLatest();
  }

  Future<void> _retry(Message message) async {
    final store = await ref.read(storeProvider.future);
    await store.addPending(
      id: message.id,
      channelId: message.channelId,
      authorId: message.authorId ?? '',
      content: message.content,
    );
    try {
      final sent = await ref.read(apiProvider).sendMessage(
            channelId: message.channelId,
            id: message.id,
            content: message.content,
          );
      await store.applyMessage(sent);
      ref.read(messageExtrasProvider.notifier).applyMessage(sent);
    } on api.ApiException {
      await store.markFailed(message.id);
    }
  }

  Future<void> _pickReaction(Message message, String emoji) => setReaction(
        ref,
        message.id,
        emoji,
        wasActive: hasReacted(ref, message.id, emoji),
      );

  Future<void> _toggleReaction(Message message, api.ReactionSummary reaction) =>
      setReaction(ref, message.id, reaction.emoji, wasActive: reaction.reacted);

  Future<void> _vote(Message message, int option) =>
      castVote(ref, message.id, option);

  void _startEdit(Message message) => setState(() => _editingId = message.id);

  void _cancelEdit() => setState(() => _editingId = null);

  Future<void> _submitEdit(Message message, String content) async {
    setState(() => _editingId = null);
    if (content == message.content) return;
    try {
      await editMessageAction(ref, message, content);
    } on api.ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the edit. ${e.message}')));
    }
  }

  Future<void> _deleteMessage(Message message) async {
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Delete message?',
      message: 'This removes it for everyone in the channel. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;
    try {
      await deleteMessageAction(ref, message);
    } on api.ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not delete the message. ${e.message}')));
    }
  }

  Future<void> _togglePin(Message message, bool pinned) async {
    final controller =
        ref.read(pinsControllerProvider(widget.channelId).notifier);
    try {
      if (pinned) {
        await controller.unpin(message.id);
      } else {
        await controller.pin(message.id);
      }
    } on api.ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update the pin. ${e.message}')));
    }
  }

  Future<void> _reportMessage(Message message) async {
    final reason =
        await promptReportReason(context, subjectLabel: 'this message');
    if (reason == null || !mounted) return;
    try {
      await ref.read(apiProvider).report(
            subject: api.ReportSubject.message,
            subjectId: message.id,
            reason: reason,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Report filed. A moderator will review it.')));
    } on api.ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not file the report. ${e.message}')));
    }
  }

  Future<void> _blockAuthor(Message message) async {
    final authorId = message.authorId;
    if (authorId == null) return;
    try {
      await ref.read(apiProvider).blockUser(authorId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Blocked. Their messages are hidden for you.')));
    } on api.ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not block that user. ${e.message}')));
    }
  }

  /// Both the flag and the query live in [channelSearchProvider] so the
  /// compact layout's app bar, built above this screen, can drive them too.
  void _search(String query) =>
      ref.read(channelSearchProvider(widget.channelId).notifier).run(query);

  void _toggleSearch() =>
      ref.read(channelSearchProvider(widget.channelId).notifier).toggle();

  /// Advances the read marker to the newest message actually rendered.
  ///
  /// Pending sends are skipped: they carry seq 0 until the server
  /// acknowledges them, so treating one as "read" would either no-op or,
  /// once the real send lands with its assigned seq, immediately look
  /// unread again for a message the user already sees on screen.
  ///
  /// The local write and the network call are both monotonic and idempotent
  /// (`MessageStore.setReadMarker`, the server's `PUT .../read`), so a
  /// redundant call is harmless; [_markedReadSeq] exists only to keep a busy
  /// channel from re-sending the same seq on every unrelated rebuild.
  void _markReadUpToLatest(List<Message> messages, int lastReadSeq) {
    Message? newest;
    for (final message in messages.reversed) {
      if (!message.pending) {
        newest = message;
        break;
      }
    }
    if (newest == null) return;
    final seq = newest.seq;
    if (seq <= lastReadSeq) return;
    if ((_markedReadSeq[widget.channelId] ?? 0) >= seq) return;
    _markedReadSeq[widget.channelId] = seq;
    unawaited(_markRead(widget.channelId, seq));
  }

  Future<void> _markRead(String channelId, int seq) async {
    final store = await ref.read(storeProvider.future);
    await store.setReadMarker(channelId, seq);
    try {
      await ref.read(apiProvider).markRead(channelId: channelId, seq: seq);
    } on api.ApiException {
      // Best-effort: the local marker already advanced, so the UI is
      // already correct, and the next message or reconnect gives the
      // server another chance to hear it.
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        // The list is reversed, so the latest message sits at offset zero.
        _scroll.position.minScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(storeProvider);
    final layout = LayoutClass.of(context);
    final search = ref.watch(channelSearchProvider(widget.channelId));
    // Search can now be closed from the app bar as well as from the header,
    // and either way the field it typed into has to empty with it.
    ref.listen(channelSearchProvider(widget.channelId).select((s) => s.open),
        (_, open) {
      if (!open) _searchController.clear();
    });
    final knownUsernames = ref.watch(membersProvider).maybeWhen(
          data: (members) =>
              members.map((m) => m.username.toLowerCase()).toSet(),
          orElse: () => const <String>{},
        );
    final extrasById = ref.watch(messageExtrasProvider);
    final myId = ref.watch(meProvider).valueOrNull?.id;
    final myPermissions = ref.watch(myPermissionsProvider);
    final pinnedIds = {
      for (final p
          in ref.watch(pinsControllerProvider(widget.channelId)).pinned ??
              const [])
        p.message.id,
    };

    return storeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('Could not open the local store: $e')),
      data: (store) => StreamBuilder<List<Channel>>(
        stream: store.watchChannels(),
        builder: (context, channelsSnapshot) {
          final channel = channelsSnapshot.data
              ?.where((c) => c.id == widget.channelId)
              .cast<Channel?>()
              .firstOrNull;
          final channelName = channel?.name ?? '';

          return Column(
            children: [
              if (layout.showsBothPanes)
                ChannelHeader(
                  channelId: widget.channelId,
                  name: channelName,
                  topic: channel?.topic,
                  isVoice: false,
                  searchOpen: search.open,
                  onToggleSearch: _toggleSearch,
                ),
              if (search.open)
                ChannelSearchBar(
                    controller: _searchController, onChanged: _search),
              Expanded(
                child: search.query != null
                    ? ChannelSearchResults(
                        results: search.results,
                        knownUsernames: knownUsernames,
                        loading: search.loading,
                        failed: search.failed,
                        forbidden: search.forbidden,
                        onRetry: () => _search(search.query!),
                      )
                    : StreamBuilder<List<Message>>(
                        stream: store.watchChannel(widget.channelId),
                        builder: (context, snapshot) {
                          final messages = snapshot.data ?? const <Message>[];
                          if (messages.isEmpty) {
                            return _EmptyMessages(
                                syncStatus: ref.watch(syncControllerProvider));
                          }
                          final lastReadSeq = channel?.lastReadSeq ?? 0;
                          _markReadUpToLatest(messages, lastReadSeq);
                          // The design fills the column from the bottom, so a
                          // short conversation sits against the composer
                          // rather than stranding it below empty space.
                          return ListView.builder(
                            controller: _scroll,
                            reverse: true,
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.s8),
                            itemCount: messages.length,
                            itemBuilder: (context, i) {
                              // Index 0 is the newest, at the bottom.
                              // `previous` stays the row visually above, which
                              // is the older message, so grouping and the
                              // unread divider read the same as before.
                              final index = messages.length - 1 - i;
                              final message = messages[index];
                              final previous =
                                  index == 0 ? null : messages[index - 1];
                              final extras =
                                  extrasById[message.id] ?? MessageExtras.empty;
                              final pinned = pinnedIds.contains(message.id);
                              return MessageRow(
                                message: message,
                                grouped: _isGrouped(message, previous),
                                showNewDivider: _startsUnread(
                                    message, previous, lastReadSeq),
                                knownUsernames: knownUsernames,
                                onRetry: () => _retry(message),
                                onDiscard: () async =>
                                    (await ref.read(storeProvider.future))
                                        .discard(message.id),
                                onPickReaction: (emoji) =>
                                    _pickReaction(message, emoji),
                                onReactionTap: (reaction) =>
                                    _toggleReaction(message, reaction),
                                onVote: (option) => _vote(message, option),
                                reactions: extras.reactions,
                                attachments: extras.attachments,
                                poll: extras.poll,
                                editing: message.id == _editingId,
                                onSubmitEdit: (content) =>
                                    unawaited(_submitEdit(message, content)),
                                onCancelEdit: _cancelEdit,
                                actions: MessageActions(
                                  canEdit: canEditMessage(message, myId),
                                  onEdit: () => _startEdit(message),
                                  canDelete: canDeleteMessage(
                                      message, myId, myPermissions),
                                  onDelete: () =>
                                      unawaited(_deleteMessage(message)),
                                  canManagePins: canManageMessagePin(
                                      message, myPermissions),
                                  pinned: pinned,
                                  onTogglePin: () =>
                                      unawaited(_togglePin(message, pinned)),
                                  canReport: canReportMessage(message, myId),
                                  onReport: () =>
                                      unawaited(_reportMessage(message)),
                                  canBlockAuthor:
                                      canBlockMessageAuthor(message, myId),
                                  onBlockAuthor: () =>
                                      unawaited(_blockAuthor(message)),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
              Composer(
                  controller: _composer,
                  channelId: widget.channelId,
                  channelName: channelName,
                  onSend: _send),
            ],
          );
        },
      ),
    );
  }
}

/// What an empty message list means depends on whether catch-up has actually
/// run: a channel can look empty because it is, or because sync has not
/// reached it yet, and those read as opposite things to the person waiting.
class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages({required this.syncStatus});

  final SyncStatus syncStatus;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return switch (syncStatus) {
      SyncStatus.connecting => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: AppSpacing.s12),
              Text('Catching up on messages...',
                  style: TextStyle(color: tokens.textSecondary)),
            ],
          ),
        ),
      SyncStatus.offline => Center(
          child: Text('Offline. Messages will appear once reconnected.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary)),
        ),
      SyncStatus.live => Center(
          child: Text('No messages yet.',
              style: TextStyle(color: tokens.textSecondary)),
        ),
    };
  }
}

/// A continuation of the same author's previous message inside the density's
/// grouping window drops its avatar and header.
bool _isGrouped(Message message, Message? previous) =>
    previous != null &&
    previous.authorId == message.authorId &&
    (message.createdAt - previous.createdAt).abs() <
        AppDensity.normal.groupWindow.inMilliseconds;

/// True for the first message past the read marker, so the "New" divider
/// lands exactly once, directly above it.
bool _startsUnread(Message message, Message? previous, int lastReadSeq) =>
    message.seq > lastReadSeq &&
    (previous == null || previous.seq <= lastReadSeq);
