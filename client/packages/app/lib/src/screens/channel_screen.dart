// SPDX-License-Identifier: Apache-2.0
/// The conversation: history, live arrivals, and the composer.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';

/// Generates the UUIDv7 that identifies a message and makes its send
/// idempotent. Time-ordered, which is what the server's storage assumes.
String newMessageId() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final random = Random.secure();
  final bytes = <int>[
    (now >> 40) & 0xff,
    (now >> 32) & 0xff,
    (now >> 24) & 0xff,
    (now >> 16) & 0xff,
    (now >> 8) & 0xff,
    now & 0xff,
    ...List<int>.generate(10, (_) => random.nextInt(256)),
  ];
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20)}';
}

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

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Sends, showing the message immediately and reconciling with the server's
  /// copy when it lands. The id is generated here and reused on retry, so a
  /// retry after an uncertain failure can never post twice.
  Future<void> _send() async {
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
          );
      // Lands on the same row, because it carries the same id.
      await store.applyMessage(sent);
    } on api.ApiException {
      // Keep the text as a failed row rather than dropping it; the user can
      // retry or discard, and either way they do not lose what they wrote.
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
    } on api.ApiException {
      await store.markFailed(message.id);
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(storeProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return storeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('Could not open the local store: $e')),
      data: (store) => Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: store.watchChannel(widget.channelId),
              builder: (context, snapshot) {
                final messages = snapshot.data ?? const <Message>[];
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet.',
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _MessageRow(
                    message: messages[i],
                    previous: i == 0 ? null : messages[i - 1],
                    onRetry: () => _retry(messages[i]),
                    onDiscard: () async =>
                        (await ref.read(storeProvider.future))
                            .discard(messages[i].id),
                  ),
                );
              },
            ),
          ),
          _Composer(controller: _composer, onSend: _send),
        ],
      ),
    );
  }
}

/// One message. Consecutive messages from the same author are grouped, so a
/// back-and-forth reads as a conversation rather than a wall of repeated names.
class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.previous,
    required this.onRetry,
    required this.onDiscard,
  });

  final Message message;
  final Message? previous;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  bool get _grouped =>
      previous != null &&
      previous!.authorId == message.authorId &&
      (message.createdAt - previous!.createdAt).abs() < 5 * 60 * 1000;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final unsent = message.pending || message.failed;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        _grouped ? AppSpacing.s4 : AppSpacing.s12,
        AppSpacing.s16,
        AppSpacing.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_grouped)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s4),
              child: Text(
                // Never the raw id. A missing name means the row was cached
                // before the server sent names and has not been re-synced, and
                // showing a 36-character uuid where a person's name goes reads
                // as corruption rather than as staleness. A null author is a
                // deleted account, which is a different and knowable thing.
                message.authorDisplayName ??
                    (message.authorId == null ? 'Deleted user' : 'Unknown'),
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  message.content,
                  style: TextStyle(
                    color: unsent ? tokens.textSecondary : tokens.textPrimary,
                  ),
                ),
              ),
              if (message.editedAt != null)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.s8),
                  child: Text(
                    'edited',
                    style: TextStyle(color: tokens.textSecondary, fontSize: 11),
                  ),
                ),
              if (message.pending)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.s8),
                  child: Icon(AppIcons.pending,
                      size: 14, color: tokens.textSecondary),
                ),
            ],
          ),
          if (message.failed)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s4),
              child: Row(
                children: [
                  Icon(
                    AppIcons.failed,
                    size: 14,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Text(
                    'Not sent.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
                  TextButton(
                      onPressed: onDiscard, child: const Text('Discard')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 6,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                hintText: 'Message',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          // 48x48 keeps the target within reach of the accessibility baseline.
          SizedBox(
            height: 48,
            width: 48,
            child: IconButton(
              onPressed: onSend,
              icon: const Icon(AppIcons.send),
              tooltip: 'Send',
            ),
          ),
        ],
      ),
    );
  }
}
