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
import '../providers/message_actions.dart';
import '../providers/message_extras.dart';
import '../providers/providers.dart';
import '../routing/breakpoints.dart';
import '../widgets/channel_header.dart';
import '../widgets/channel_search.dart';
import '../widgets/composer.dart';
import '../widgets/member_pane.dart';
import '../widgets/message_row.dart';

export '../ids.dart' show newMessageId;

/// The fixed emoji the message row's quick-react glyph adds, standing in
/// for a full picker.
const String _quickReactionEmoji = '\u{1F44D}';

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

  Future<void> _quickReact(Message message) => setReaction(
        ref,
        message.id,
        _quickReactionEmoji,
        wasActive: hasReacted(ref, message.id, _quickReactionEmoji),
      );

  Future<void> _toggleReaction(Message message, api.ReactionSummary reaction) =>
      setReaction(ref, message.id, reaction.emoji, wasActive: reaction.reacted);

  Future<void> _vote(Message message, int option) =>
      castVote(ref, message.id, option);

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchResults = null;
        _searchController.clear();
      }
    });
  }

  Future<void> _runSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    try {
      final results = await ref
          .read(apiProvider)
          .searchMessages(widget.channelId, q: query);
      if (!mounted) return;
      setState(() => _searchResults = results);
    } on api.ApiException {
      if (!mounted) return;
      setState(() => _searchResults = const []);
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
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final layout = LayoutClass.of(context);
    final knownUsernames = ref.watch(membersProvider).maybeWhen(
          data: (members) =>
              members.map((m) => m.username.toLowerCase()).toSet(),
          orElse: () => const <String>{},
        );
    final extrasById = ref.watch(messageExtrasProvider);

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
                child: _searchResults != null
                    ? ChannelSearchResults(
                        results: _searchResults!,
                        knownUsernames: knownUsernames)
                    : StreamBuilder<List<Message>>(
                        stream: store.watchChannel(widget.channelId),
                        builder: (context, snapshot) {
                          final messages = snapshot.data ?? const <Message>[];
                          if (messages.isEmpty) {
                            return Center(
                              child: Text('No messages yet.',
                                  style:
                                      TextStyle(color: tokens.textSecondary)),
                            );
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
                                onQuickReact: () => _quickReact(message),
                                onReactionTap: (reaction) =>
                                    _toggleReaction(message, reaction),
                                onVote: (option) => _vote(message, option),
                                reactions: extras.reactions,
                                attachments: extras.attachments,
                                poll: extras.poll,
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
