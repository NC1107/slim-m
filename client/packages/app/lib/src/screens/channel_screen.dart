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
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../ids.dart';
import '../providers/blocks_controller.dart';
import '../providers/channel_drafts.dart';
import '../providers/channel_history.dart';
import '../providers/channel_permissions.dart';
import '../providers/channel_search_controller.dart';
import '../providers/emoji_catalog_provider.dart';
import '../providers/member_presence.dart';
import '../providers/message_actions.dart';
import '../providers/message_editing.dart';
import '../providers/message_extras.dart';
import '../providers/message_jump.dart';
import '../providers/pins_controller.dart';
import '../providers/providers.dart';
import '../providers/sync_controller.dart';
import '../providers/user_profiles.dart';
import '../routing/breakpoints.dart';
import '../widgets/blocked_dm_notice.dart';
import '../widgets/channel_header.dart';
import '../widgets/channel_search.dart';
import '../widgets/composer.dart';
import '../widgets/jump_to_latest_button.dart';
import '../widgets/message_jump.dart';
import '../widgets/message_transcript.dart';
import '../widgets/reply_banner.dart';
import 'channel_message_actions.dart';
import 'channel_read_marker.dart';
import 'channel_transcript_scroll.dart';

export '../ids.dart' show newMessageId;

/// One channel's messages.
/// The usernames a mention can be matched against, read from the member
/// roster [members].
///
/// `valueOrNull`, never `maybeWhen(data:)`: an `AsyncError` keeps whatever
/// resolved before it, and only the first of those two can see that value.
/// Reading it the other way made a failed fetch indistinguishable from an
/// empty deployment, so every `@name` in view fell back to plain text the
/// moment the connection dropped (reported 2026-08-13, "mentions also get
/// unhighlighted when the server was offline").
///
/// A cold start with no connection genuinely has nothing to match against and
/// still renders mentions plain; that is the honest answer rather than a gap,
/// since nothing has ever told this client who the members are.
Set<String> knownUsernamesFrom(AsyncValue<List<api.UserProfile>> members) =>
    members.valueOrNull?.map((m) => m.username.toLowerCase()).toSet() ??
    const <String>{};

class ChannelScreen extends ConsumerStatefulWidget {
  const ChannelScreen({
    required this.channelId,
    this.isThread = false,
    super.key,
  });

  final String channelId;

  /// True only from [ThreadScreen], which already knows what it is opening
  /// and does not need to ask the local store. The store's own
  /// `channel?.parentMessageId` is the fallback for the ordinary route
  /// through `ConversationPane`, which never sets this and has always relied
  /// on the row - but a thread reached by URL (a deep link, a reload while
  /// inside one, or `scripts/lib/e2e_threads.py`) has never fetched that row:
  /// a thread is excluded from `GET /channels` and `GET /dms` by design
  /// (docs/decisions/0005-threads.md), so `watchChannelRow` answers null and
  /// this screen built the full parent-channel header, `Pinned messages`,
  /// `Open canvas` and `Toggle member list` included - exactly the chrome
  /// `ThreadScreen`'s own doc comment says must never reach a thread.
  final bool isThread;

  @override
  ConsumerState<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends ConsumerState<ChannelScreen> {
  final _composer = TextEditingController();

  /// The query text only; the search itself (open, hits, failure) lives in
  /// [channelSearchProvider], which the compact app bar drives too.
  final _searchController = TextEditingController();

  /// The message the next send will reply to, if any. Cleared by sending,
  /// by an explicit cancel, and by switching channels - a reply is scoped to
  /// the conversation it was started in, not carried across a channel switch.
  Message? _replyingTo;

  late final ReadMarker _readMarker = ReadMarker(ref);

  /// The scroll controller, the jump-to-latest arrow's visibility, and the
  /// read-marking that follows from both; see `channel_transcript_scroll.dart`.
  late final TranscriptScrollTracker _scrollTracker = TranscriptScrollTracker(
    markRead: _markReadUpToLatest,
  );

  /// Captured once rather than read from `ref` in [dispose]: by then the
  /// element has already detached, and `ref.read` there throws "Cannot use
  /// ref after the widget was disposed" (see `composer.dart`'s own note on
  /// the same trap). The controller itself needs no further `ref` access
  /// once resolved, so holding it plainly is enough.
  late final ChannelDraftsController _drafts = ref.read(channelDraftsProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_hydrateExtras());
    // Fresh or reused (see [ReadMarker]), this must open on this channel's own draft.
    _composer.text = _drafts.draftFor(widget.channelId);
  }

  @override
  void didUpdateWidget(ChannelScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This State outlives a channel switch (see [ReadMarker]), so the field
    // would otherwise still hold the previous channel's query.
    if (oldWidget.channelId != widget.channelId) {
      _searchController.clear();
      // A jump neither finished nor consumed before the switch must not
      // replay against whichever channel is open next.
      ref.read(messageJumpProvider.notifier).cancelFor(oldWidget.channelId);
      _replyingTo = null;
      _scrollTracker.resetForChannelSwitch();
      _drafts.save(oldWidget.channelId, _composer.text);
      _composer.text = _drafts.draftFor(widget.channelId);
    }
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
    // Last chance to save unsent text before a torn-down State (voice, a DM call, canvas) loses it.
    _drafts.save(widget.channelId, _composer.text);
    _composer.dispose();
    _scrollTracker.dispose();
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
    _drafts.clear(widget.channelId);
    // Read and cleared before the first await, same as the composer text.
    final replyToId = _replyingTo?.id;
    setState(() => _replyingTo = null);

    await sendOptimistically(
      ref.read,
      id: newMessageId(),
      channelId: widget.channelId,
      authorId: ref.read(sessionProvider).tokens?.userId ?? '',
      content: text,
      attachmentIds: attachmentIds,
      replyToId: replyToId,
      onQueued: _scrollToLatest,
    );
    _scrollToLatest();
  }

  void _startReply(Message message) => setState(() => _replyingTo = message);

  void _cancelReply() => setState(() => _replyingTo = null);

  Future<void> _pickReaction(Message message, String emoji) => setReaction(
    ref,
    message.id,
    emoji,
    wasActive: hasReacted(ref, message.id, emoji),
  );

  Future<void> _toggleReaction(Message message, api.ReactionSummary reaction) =>
      setReaction(ref, message.id, reaction.emoji, wasActive: reaction.reacted);

  /// Writes only: nothing here watches [editingMessageIdProvider], so
  /// starting, cancelling or submitting an edit never rebuilds this screen.
  /// Each row resolves its own `editing` flag with `.select`; see that
  /// provider's own doc comment.
  void _startEdit(Message message) =>
      ref.read(editingMessageIdProvider(widget.channelId).notifier).state =
          message.id;

  void _cancelEdit() =>
      ref.read(editingMessageIdProvider(widget.channelId).notifier).state =
          null;

  void _submitEdit(Message message, String content) {
    ref.read(editingMessageIdProvider(widget.channelId).notifier).state = null;
    unawaited(submitMessageEdit(ref, context, message, content));
  }

  /// Both the flag and the query live in [channelSearchProvider] so the
  /// compact layout's app bar, built above this screen, can drive them too.
  void _search(String query) =>
      ref.read(channelSearchProvider(widget.channelId).notifier).run(query);

  void _toggleSearch() =>
      ref.read(channelSearchProvider(widget.channelId).notifier).toggle();

  void _markReadUpToLatest(int seq, int lastReadSeq) =>
      _readMarker.advance(widget.channelId, seq: seq, lastReadSeq: lastReadSeq);

  void _scrollToLatest() => _scrollTracker.scrollToLatest(
    duration: AppMotion.reduced(context, AppMotion.slow),
  );

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
    final jumpArrival = watchMessageJump(ref, context, widget.channelId);
    final knownUsernames = knownUsernamesFrom(ref.watch(membersProvider));
    final customEmoji = ref.watch(customEmojiIndexProvider);
    final blocked = ref.watch(blocksProvider.select((state) => state.ids));
    final history = ref.watch(channelHistoryProvider(widget.channelId));
    final paging = ref.read(channelHistoryProvider(widget.channelId).notifier);
    final syncStatus = ref.watch(syncControllerProvider);
    final historyKnown = ref.watch(initialSyncCompleteProvider);
    final myId = ref.watch(meProvider).valueOrNull?.id;
    // Per-channel, not deployment-wide: docs/decisions/0011-per-channel-permissions.md, site 1.
    final myPermissions = ref.watch(
      myChannelPermissionsProvider(widget.channelId),
    );
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
      data: (store) => StreamBuilder<Channel?>(
        stream: store.watchChannelRow(widget.channelId),
        builder: (context, channelSnapshot) {
          final channel = channelSnapshot.data;
          final channelName = channel?.name ?? '';
          final lastReadSeq = channel?.lastReadSeq ?? 0;
          final dmPartnerId = channel?.dmParticipantId;
          final blockedDm =
              dmPartnerId != null && blocked.contains(dmPartnerId);
          // Ored with the store's own answer; see isThread's doc comment.
          final isThread = widget.isThread || channel?.parentMessageId != null;
          // Only a real named channel gets "#name"; shared so the transcript and composer cannot drift.
          final hashChannelName = channel?.kind == 'text' ? channelName : null;
          final isDm = channel?.kind == 'dm';

          return Column(
            children: [
              // A thread supplies its own bar at every width; see thread_screen.dart.
              if (layout.showsBothPanes && !isThread)
                ChannelHeader(
                  channelId: widget.channelId,
                  name: channelName,
                  topic: channel?.topic,
                  isVoice: false,
                  isDm: isDm,
                  searchOpen: search.open,
                  onToggleSearch: _toggleSearch,
                ),
              AppRevealBand(
                child: search.open
                    ? ChannelSearchBar(
                        controller: _searchController,
                        onChanged: _search,
                      )
                    : null,
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
                          onSelect: (m) {
                            _toggleSearch();
                            jumpToMessage(
                              GoRouter.of(context),
                              ref.read,
                              currentChannelId: widget.channelId,
                              channelId: m.channelId,
                              messageId: m.id,
                            );
                          },
                        )
                      : Stack(
                          children: [
                            StreamBuilder<List<Message>>(
                              stream: store.watchChannel(
                                widget.channelId,
                                limit: history.window,
                              ),
                              builder: (context, snapshot) {
                                final rows = snapshot.data ?? const <Message>[];
                                final transcript = visibleTranscript(
                                  rows,
                                  blocked,
                                );
                                final oldest = oldestDeliveredSeq(rows);
                                paging.syncOldest(oldest);
                                resolveAuthorProfiles(
                                  ref,
                                  transcript.messages.map((m) => m.authorId),
                                );
                                _scrollTracker.updateKnownSeqs(
                                  latestSeq: transcript.newestSeq,
                                  lastReadSeq: lastReadSeq,
                                );
                                // Gated on the viewport: scrolled into history, this rebuild is a message arriving somewhere unread.
                                if (_scrollTracker.atLatest) {
                                  _markReadUpToLatest(
                                    transcript.newestSeq,
                                    lastReadSeq,
                                  );
                                }
                                return MessageTranscript(
                                  channelId: widget.channelId,
                                  selfId: ref
                                      .read(sessionProvider)
                                      .tokens
                                      ?.userId,
                                  messages: transcript.messages,
                                  syncStatus: syncStatus,
                                  historyKnown: historyKnown,
                                  channelName: hashChannelName,
                                  channelIsThread: isThread,
                                  channelTopic: channel?.topic,
                                  scrollController: _scrollTracker.controller,
                                  lastReadSeq: lastReadSeq,
                                  knownUsernames: knownUsernames,
                                  customEmoji: customEmoji,
                                  // A channel with nothing delivered has no history to page, so its oldest loaded row is vacuously its first.
                                  history: history.copyWith(
                                    atStart:
                                        history.atStart ||
                                        (oldest == null &&
                                            syncStatus == SyncStatus.live),
                                  ),
                                  onLoadOlder: () =>
                                      unawaited(paging.loadOlder()),
                                  onRetryOlder: () => unawaited(paging.retry()),
                                  // The policy itself lives in `channel_message_actions.dart`; this only supplies the screen's own state.
                                  actionsFor: (message, hasExistingThread) =>
                                      messageActionsFor(
                                        ref,
                                        context,
                                        message,
                                        channelId: widget.channelId,
                                        channelIsThread: isThread,
                                        hasExistingThread: hasExistingThread,
                                        myId: myId,
                                        myPermissions: myPermissions,
                                        pinnedIds: pinnedIds,
                                        onReply: _startReply,
                                        onEdit: _startEdit,
                                      ),
                                  onRetry: (m) =>
                                      unawaited(retryMessage(ref.read, m)),
                                  onDiscard: (m) =>
                                      unawaited(discardMessage(ref.read, m)),
                                  // Failed text lands back in the composer to fix
                                  // and resend; the failed row is then discarded,
                                  // so nothing the user wrote is ever lost.
                                  onEditFailed: (m) {
                                    _composer.text = m.content;
                                    unawaited(discardMessage(ref.read, m));
                                  },
                                  onPickReaction: (m, emoji) =>
                                      unawaited(_pickReaction(m, emoji)),
                                  onReactionTap: (m, reaction) =>
                                      unawaited(_toggleReaction(m, reaction)),
                                  onVote: (m, option) =>
                                      unawaited(castVote(ref, m.id, option)),
                                  onSubmitEdit: _submitEdit,
                                  onCancelEdit: _cancelEdit,
                                  onJumpToReply: (replyToId) => jumpToMessage(
                                    GoRouter.of(context),
                                    ref.read,
                                    currentChannelId: widget.channelId,
                                    channelId: widget.channelId,
                                    messageId: replyToId,
                                  ),
                                  jumpTargetId: jumpArrival?.messageId,
                                  jumpToken: jumpArrival?.token,
                                  onJumpArrived: jumpArrival == null
                                      ? null
                                      : () => ref
                                            .read(messageJumpProvider.notifier)
                                            .consume(jumpArrival.token),
                                );
                              },
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Center(
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: _scrollTracker.scrolledAway,
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
              if (blockedDm)
                BlockedDmNotice(userId: dmPartnerId, name: channelName)
              else ...[
                AppRevealBand(
                  child: _replyingTo == null
                      ? null
                      : ReplyBanner(
                          message: _replyingTo!,
                          onCancel: _cancelReply,
                        ),
                ),
                Composer(
                  controller: _composer,
                  channelId: widget.channelId,
                  channelName: hashChannelName ?? '',
                  onSend: _send,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
