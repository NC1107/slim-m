// SPDX-License-Identifier: Apache-2.0
/// The conversation: history, live arrivals, search, and the composer.
///
/// This screen holds the state a channel view has to carry across a rebuild
/// (what is being edited, what has been marked read, where the scroll is) and
/// wires the pieces together. The two things it used to also do live next
/// door now: `channel_message_actions.dart` acts on a single message, and
/// `widgets/message_transcript.dart` lays the list out.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';

import '../ids.dart';
import '../providers/admin_providers.dart';
import '../providers/channel_search_controller.dart';
import '../providers/emoji_catalog_provider.dart';
import '../providers/member_presence.dart';
import '../providers/message_actions.dart';
import '../providers/message_extras.dart';
import '../providers/pins_controller.dart';
import '../providers/providers.dart';
import '../providers/sync_controller.dart';
import '../routing/breakpoints.dart';
import '../widgets/channel_header.dart';
import '../widgets/channel_search.dart';
import '../widgets/composer.dart';
import '../widgets/message_context_menu.dart';
import '../widgets/message_transcript.dart';
import 'channel_message_actions.dart';

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
      final recent = await ref
          .read(apiProvider)
          .listMessages(widget.channelId, limit: 50);
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
  /// copy when it lands. The field is cleared before the first await, so two
  /// calls in one turn cannot both read the same text: the second finds it
  /// empty and returns.
  Future<void> _send(List<String> attachmentIds) async {
    final text = _composer.text.trim();
    // A staged file is a message on its own, so only a send carrying neither
    // text nor attachment is the one to drop.
    if (text.isEmpty && attachmentIds.isEmpty) return;
    _composer.clear();

    await sendOptimistically(
      ref,
      id: newMessageId(),
      channelId: widget.channelId,
      authorId: ref.read(sessionProvider).tokens?.userId ?? '',
      content: text,
      attachmentIds: attachmentIds,
      onQueued: _scrollToLatest,
    );
    _scrollToLatest();
  }

  Future<void> _pickReaction(Message message, String emoji) => setReaction(
    ref,
    message.id,
    emoji,
    wasActive: hasReacted(ref, message.id, emoji),
  );

  Future<void> _toggleReaction(Message message, api.ReactionSummary reaction) =>
      setReaction(ref, message.id, reaction.emoji, wasActive: reaction.reacted);

  void _startEdit(Message message) => setState(() => _editingId = message.id);

  void _cancelEdit() => setState(() => _editingId = null);

  void _submitEdit(Message message, String content) {
    setState(() => _editingId = null);
    unawaited(submitMessageEdit(ref, context, message, content));
  }

  /// What this viewer may do to [message], which is the screen's business:
  /// it is the one holding the session and the permission bits.
  MessageActions _actionsFor(
    Message message, {
    required String? myId,
    required int myPermissions,
    required Set<String> pinnedIds,
  }) {
    final pinned = pinnedIds.contains(message.id);
    return MessageActions(
      canEdit: canEditMessage(message, myId),
      onEdit: () => _startEdit(message),
      canDelete: canDeleteMessage(message, myId, myPermissions),
      onDelete: () => unawaited(confirmAndDeleteMessage(ref, context, message)),
      canManagePins: canManageMessagePin(message, myPermissions),
      pinned: pinned,
      onTogglePin: () => unawaited(
        toggleMessagePin(
          ref,
          context,
          channelId: widget.channelId,
          message: message,
          pinned: pinned,
        ),
      ),
      canReport: canReportMessage(message, myId),
      onReport: () => unawaited(reportMessage(ref, context, message)),
      canBlockAuthor: canBlockMessageAuthor(message, myId),
      onBlockAuthor: () => unawaited(blockMessageAuthor(ref, context, message)),
    );
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
      // Best-effort: the local marker already advanced, so the UI is correct,
      // and the next message or reconnect gives the server another chance.
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
    ref.listen(channelSearchProvider(widget.channelId).select((s) => s.open), (
      _,
      open,
    ) {
      if (!open) _searchController.clear();
    });
    final knownUsernames = ref
        .watch(membersProvider)
        .maybeWhen(
          data: (members) =>
              members.map((m) => m.username.toLowerCase()).toSet(),
          orElse: () => const <String>{},
        );
    final customEmoji = ref.watch(customEmojiIndexProvider);
    final extrasById = ref.watch(messageExtrasProvider);
    final syncStatus = ref.watch(syncControllerProvider);
    final myId = ref.watch(meProvider).valueOrNull?.id;
    final myPermissions = ref.watch(myPermissionsProvider);
    final pinnedIds = <String>{
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
                  controller: _searchController,
                  onChanged: _search,
                ),
              // Tapping the transcript dismisses the keyboard, which on a phone
              // is otherwise covering most of what the tap was aiming at.
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: search.query != null
                      ? ChannelSearchResults(
                          results: search.results,
                          knownUsernames: knownUsernames,
                          customEmoji: customEmoji,
                          loading: search.loading,
                          failed: search.failed,
                          forbidden: search.forbidden,
                          onRetry: () => _search(search.query!),
                        )
                      : StreamBuilder<List<Message>>(
                          stream: store.watchChannel(widget.channelId),
                          builder: (context, snapshot) {
                            final messages = snapshot.data ?? const <Message>[];
                            final lastReadSeq = channel?.lastReadSeq ?? 0;
                            _markReadUpToLatest(messages, lastReadSeq);
                            return MessageTranscript(
                              messages: messages,
                              syncStatus: syncStatus,
                              scrollController: _scroll,
                              lastReadSeq: lastReadSeq,
                              editingId: _editingId,
                              knownUsernames: knownUsernames,
                              customEmoji: customEmoji,
                              extrasById: extrasById,
                              actionsFor: (message) => _actionsFor(
                                message,
                                myId: myId,
                                myPermissions: myPermissions,
                                pinnedIds: pinnedIds,
                              ),
                              onRetry: (m) => unawaited(retryMessage(ref, m)),
                              onDiscard: (m) =>
                                  unawaited(discardMessage(ref, m)),
                              onPickReaction: (m, emoji) =>
                                  unawaited(_pickReaction(m, emoji)),
                              onReactionTap: (m, reaction) =>
                                  unawaited(_toggleReaction(m, reaction)),
                              onVote: (m, option) =>
                                  unawaited(castVote(ref, m.id, option)),
                              onSubmitEdit: _submitEdit,
                              onCancelEdit: _cancelEdit,
                            );
                          },
                        ),
                ),
              ),
              Composer(
                controller: _composer,
                channelId: widget.channelId,
                channelName: channelName,
                onSend: _send,
              ),
            ],
          );
        },
      ),
    );
  }
}
