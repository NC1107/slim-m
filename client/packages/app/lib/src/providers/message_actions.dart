// SPDX-License-Identifier: Apache-2.0
/// Message-row actions shared by any screen that renders a message: reaction
/// and poll-vote toggles apply an optimistic local update before the real
/// request, reverting on failure where a clean revert exists; edit and
/// delete let the request fail up to the caller, which has a user-visible
/// error to show. The `can*` gates decide what a caller may even offer,
/// mirroring the server's own author-or-permission checks.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';

import '../permissions.dart';
import 'message_extras.dart';
import 'providers.dart';

/// Toggles a reaction: off if [wasActive], on otherwise. Applied
/// optimistically before the request, so a chip responds immediately; a
/// failure reverts it, and the acting connection's own `reactions.changed`
/// broadcast (it receives its own broadcasts too) reconciles the rest
/// either way.
Future<void> setReaction(
  WidgetRef ref,
  String messageId,
  String emoji, {
  required bool wasActive,
}) async {
  final extras = ref.read(messageExtrasProvider.notifier);
  final activate = !wasActive;
  extras.applyLocalReactionToggle(messageId, emoji, activate);
  try {
    final client = ref.read(apiProvider);
    if (activate) {
      await client.addReaction(messageId: messageId, emoji: emoji);
    } else {
      await client.removeReaction(messageId: messageId, emoji: emoji);
    }
  } on api.ApiException {
    extras.applyLocalReactionToggle(messageId, emoji, wasActive);
  }
}

/// Whether the caller has already reacted to [messageId] with [emoji],
/// according to whatever this session currently has cached.
bool hasReacted(WidgetRef ref, String messageId, String emoji) => ref
    .read(messageExtrasProvider.notifier)
    .extrasFor(messageId)
    .reactions
    .any((r) => r.emoji == emoji && r.reacted);

/// Casts (or changes) a vote, applied optimistically for the same reason
/// reactions are: `poll.voted` never reports back who voted, only the
/// refreshed tally, so the voter's own [api.Poll.votedOption] would
/// otherwise never update on their own screen.
Future<void> castVote(WidgetRef ref, String messageId, int option) async {
  ref.read(messageExtrasProvider.notifier).applyLocalVote(messageId, option);
  try {
    await ref.read(apiProvider).votePoll(messageId: messageId, option: option);
  } on api.ApiException {
    // Best-effort: the next poll.voted broadcast or a re-fetch corrects
    // this. There is no clean revert for a vote the way there is for a
    // reaction, since the previous choice is already folded into the
    // locally merged tally.
  }
}

bool _isAuthor(Message message, String? myUserId) =>
    message.authorId != null && message.authorId == myUserId;

/// Own message only, matching the server's author check: a member holding
/// MANAGE_MESSAGES can edit someone else's message server-side too, but
/// that is deliberately not offered here (see `channel_screen.dart`).
bool canEditMessage(Message message, String? myUserId) =>
    !message.pending && !message.failed && _isAuthor(message, myUserId);

/// Own message, or MANAGE_MESSAGES. A pending or failed send was never
/// stored server-side, so it has nothing here to delete; its own
/// retry/discard row covers that case instead.
bool canDeleteMessage(Message message, String? myUserId, int myPermissions) =>
    !message.pending &&
    !message.failed &&
    (_isAuthor(message, myUserId) ||
        myPermissions.hasPermission(Perm.manageMessages));

/// MANAGE_MESSAGES only; there is no author exception for pinning.
bool canManageMessagePin(Message message, int myPermissions) =>
    !message.pending &&
    !message.failed &&
    myPermissions.hasPermission(Perm.manageMessages);

/// Any live message not your own. The server enforces no authorship rule
/// on `/reports`; this is purely a client-side UX gate.
bool canReportMessage(Message message, String? myUserId) =>
    !message.pending && !message.failed && !_isAuthor(message, myUserId);

/// Blocking is keyed by author id, so a message with no live author (its
/// account was deleted and the content anonymized) has nobody left to block.
bool canBlockMessageAuthor(Message message, String? myUserId) =>
    !message.pending &&
    !message.failed &&
    message.authorId != null &&
    !_isAuthor(message, myUserId);

/// Edits a message, then applies the server's returned copy (with its
/// fresh `edited_at`) to the local store and the extras cache the same way
/// a live `message.edited` event would, so the row's own edited marker
/// updates without waiting for that broadcast to loop back.
Future<void> editMessageAction(
  WidgetRef ref,
  Message message,
  String content,
) async {
  final updated = await ref
      .read(apiProvider)
      .editMessage(
        channelId: message.channelId,
        messageId: message.id,
        content: content,
      );
  final store = await ref.read(storeProvider.future);
  await store.applyMessage(updated);
  ref.read(messageExtrasProvider.notifier).applyMessage(updated);
}

/// Deletes a message server-side, then drops its local row so it vanishes
/// from this device immediately rather than waiting for the `message.deleted`
/// broadcast [SyncController] applies the same way.
Future<void> deleteMessageAction(WidgetRef ref, Message message) async {
  await ref
      .read(apiProvider)
      .deleteMessage(channelId: message.channelId, messageId: message.id);
  final store = await ref.read(storeProvider.future);
  await store.discard(message.id);
}
