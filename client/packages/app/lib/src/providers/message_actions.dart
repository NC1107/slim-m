// SPDX-License-Identifier: Apache-2.0
/// Reaction and poll-vote actions shared by any screen that renders a
/// message: apply the optimistic local update first, then make the real
/// request, reverting on failure where a clean revert exists.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

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
