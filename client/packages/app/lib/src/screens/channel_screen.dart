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
import 'package:slimm_design_system/design_system.dart';

import '../ids.dart';
import '../providers/admin_providers.dart';
import '../providers/blocks_controller.dart';
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
import '../widgets/jump_to_latest_button.dart';
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

  /// The channel's newest delivered seq and last-read marker as of the most
  /// recent build, cached for [_onScrollChanged]: scrolling never rebuilds
  /// the transcript's `StreamBuilder`, so nothing else keeps these current
  /// for it.
  int _latestSeq = 0;
  int _lastReadSeq = 0;

  /// Whether the transcript is scrolled away from the newest message, for the
  /// "jump to latest" affordance alone. A [ValueNotifier] rather than a
  /// `setState`-tracked field on purpose: rebuilding the whole screen on every
  /// scroll frame that crosses the threshold would make the read marker's own
  /// correctness depend on that rebuild reaching the transcript's gate, which
  /// is exactly the coupling [_onScrollChanged] is not allowed to lean on.
  final ValueNotifier<bool> _scrolledAway = ValueNotifier(false);

  /// How close to [ScrollPosition.minScrollExtent] still counts as "at the
  /// latest message", covering overscroll bounce and float rounding from
  /// [_scrollToLatest]'s own animation landing.
  static const double _atLatestSlop = 4;

  @override
  void initState() {
    super.initState();
    unawaited(_hydrateExtras());
    _scroll.addListener(_onScrollChanged);
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
    _scroll
      ..removeListener(_onScrollChanged)
      ..dispose();
    _scrolledAway.dispose();
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
      onReport: () => unawaited(reportMessage(context, message)),
      canBlockAuthor: canBlockMessageAuthor(message, myId),
      onBlockAuthor: () => unawaited(blockMessageAuthor(context, message)),
    );
  }

  /// Both the flag and the query live in [channelSearchProvider] so the
  /// compact layout's app bar, built above this screen, can drive them too.
  void _search(String query) =>
      ref.read(channelSearchProvider(widget.channelId).notifier).run(query);

  void _toggleSearch() =>
      ref.read(channelSearchProvider(widget.channelId).notifier).toggle();

  /// Advances the read marker to `seq`, the newest delivered message in the
  /// channel ([VisibleTranscript.newestSeq]).
  ///
  /// Pending sends are excluded there: they carry seq 0 until the server
  /// acknowledges them, so treating one as "read" would either no-op or,
  /// once the real send lands with its assigned seq, immediately look
  /// unread again for a message the user already sees on screen. A blocked
  /// author's message counts, for the reason that field records.
  ///
  /// The local write and the network call are both monotonic and idempotent
  /// (`MessageStore.setReadMarker`, the server's `PUT .../read`), so a
  /// redundant call is harmless; [_markedReadSeq] exists only to keep a busy
  /// channel from re-sending the same seq on every unrelated rebuild.
  ///
  /// Callers are responsible for the scroll gate: this only knows the seq to
  /// advance to, never whether the viewport is actually showing it, since
  /// both `build` and [_onScrollChanged] call it under their own check.
  void _markReadUpToLatest(int seq, int lastReadSeq) {
    if (seq == 0) return;
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
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        // The list is reversed, so the latest message sits at offset zero.
        _scroll.position.minScrollExtent,
        duration: AppMotion.reduced(context, AppMotion.slow),
        curve: AppMotion.entrance,
      );
    });
  }

  /// True while the viewport shows the newest message: no scrollable has
  /// attached yet (nothing has laid out to have scrolled away from, and the
  /// list starts bottom-anchored so a first paint always begins there), or
  /// the offset already sits within [_atLatestSlop] of
  /// [ScrollPosition.minScrollExtent].
  bool get _atLatest {
    if (!_scroll.hasClients) return true;
    final position = _scroll.position;
    return position.pixels <= position.minScrollExtent + _atLatestSlop;
  }

  /// Scrolling never rebuilds the transcript's `StreamBuilder`, so returning
  /// to the latest message needs its own trigger to re-mark read; this is it,
  /// on its own, independent of whether the affordance below happens to
  /// repaint.
  void _onScrollChanged() {
    final atLatest = _atLatest;
    _scrolledAway.value = !atLatest;
    if (atLatest) _markReadUpToLatest(_latestSeq, _lastReadSeq);
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
    final blocked = ref.watch(blocksProvider.select((state) => state.ids));
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
          const Center(child: Text('Could not open the local store.')),
      data: (store) => StreamBuilder<List<Channel>>(
        stream: store.watchChannels(),
        builder: (context, channelsSnapshot) {
          final channel = channelsSnapshot.data
              ?.where((c) => c.id == widget.channelId)
              .cast<Channel?>()
              .firstOrNull;
          final channelName = channel?.name ?? '';
          final lastReadSeq = channel?.lastReadSeq ?? 0;

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
                      : Stack(
                          children: [
                            StreamBuilder<List<Message>>(
                              stream: store.watchChannel(widget.channelId),
                              builder: (context, snapshot) {
                                final transcript = visibleTranscript(
                                  snapshot.data ?? const <Message>[],
                                  blocked,
                                );
                                _latestSeq = transcript.newestSeq;
                                _lastReadSeq = lastReadSeq;
                                // Gated on the viewport: scrolled into history, this rebuild is a message arriving somewhere unread.
                                if (_atLatest) {
                                  _markReadUpToLatest(
                                    transcript.newestSeq,
                                    lastReadSeq,
                                  );
                                }
                                return MessageTranscript(
                                  messages: transcript.messages,
                                  syncStatus: syncStatus,
                                  // Only a real named channel gets the header; a DM's name is a person, and voice never reaches here.
                                  channelName: channel?.kind == 'text'
                                      ? channelName
                                      : null,
                                  channelTopic: channel?.topic,
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
                                  onRetry: (m) =>
                                      unawaited(retryMessage(ref, m)),
                                  onDiscard: (m) =>
                                      unawaited(discardMessage(ref, m)),
                                  // Failed text lands back in the composer to fix
                                  // and resend; the failed row is then discarded,
                                  // so nothing the user wrote is ever lost.
                                  onEditFailed: (m) {
                                    _composer.text = m.content;
                                    unawaited(discardMessage(ref, m));
                                  },
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
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Center(
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: _scrolledAway,
                                  builder: (context, scrolledAway, _) =>
                                      JumpToLatestButton(
                                        visible: scrolledAway,
                                        onTap: _scrollToLatest,
                                      ),
                                ),
                              ),
                            ),
                          ],
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
