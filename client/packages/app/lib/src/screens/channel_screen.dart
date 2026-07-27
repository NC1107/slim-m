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
  final _searchController = TextEditingController();
  bool _searchOpen = false;

  /// Search hits straight from the server, not the local store: `api.Message`
  /// here, never the local `Message` row the rest of this screen otherwise
  /// uses, since a search result was never necessarily written locally.
  List<api.Message>? _searchResults;

  /// The last query actually submitted, null once cleared. Distinct from
  /// [_searchResults] being null: that also happens mid-request and on a
  /// failure, neither of which is "no search running".
  String? _searchQuery;
  bool _searchLoading = false;

  /// Set on a failed search, cleared on the next attempt. Kept apart from
  /// [_searchResults] so "the request failed" never renders identically to
  /// "the request came back with nothing", which is the loading/empty
  /// confusion this screen exists to avoid.
  bool _searchFailed = false;
  bool _searchForbidden = false;

  /// The message currently swapped into its inline edit field, if any. At
  /// most one at a time: starting a new edit implicitly cancels another.
  String? _editingId;

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
  /// retry after an uncertain failure can never post twice.
  Future<void> _send(List<String> attachmentIds) async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;

    final store = await ref.read(storeProvider.future);
    final session = ref.read(sessionProvider);
    final id = newMessageId();

    _composer.clear();
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

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchQuery = null;
        _searchResults = null;
        _searchLoading = false;
        _searchFailed = false;
        _searchForbidden = false;
        _searchController.clear();
      }
    });
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchQuery = null;
        _searchResults = null;
        _searchLoading = false;
        _searchFailed = false;
        _searchForbidden = false;
      });
      return;
    }
    setState(() {
      _searchQuery = trimmed;
      _searchLoading = true;
      _searchFailed = false;
      _searchForbidden = false;
    });
    try {
      final results = await ref
          .read(apiProvider)
          .searchMessages(widget.channelId, q: trimmed);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searchLoading = false;
      });
    } on api.ForbiddenException {
      if (!mounted) return;
      // Not transient: the same query will fail again until the caller's
      // permissions change, so a retry button here would only waste a tap.
      setState(() {
        _searchResults = null;
        _searchLoading = false;
        _searchFailed = true;
        _searchForbidden = true;
      });
    } on api.ApiException {
      if (!mounted) return;
      setState(() {
        _searchResults = null;
        _searchLoading = false;
        _searchFailed = true;
      });
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
                  searchOpen: _searchOpen,
                  onToggleSearch: _toggleSearch,
                ),
              if (_searchOpen)
                ChannelSearchBar(
                    controller: _searchController, onChanged: _runSearch),
              Expanded(
                child: _searchQuery != null
                    ? ChannelSearchResults(
                        results: _searchResults,
                        knownUsernames: knownUsernames,
                        loading: _searchLoading,
                        failed: _searchFailed,
                        forbidden: _searchForbidden,
                        onRetry: () => _runSearch(_searchQuery!),
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
