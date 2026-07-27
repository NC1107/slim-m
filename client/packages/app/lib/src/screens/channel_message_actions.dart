// SPDX-License-Identifier: Apache-2.0
/// Acting on one message, from a screen that can confirm and can report back.
///
/// `providers/message_actions.dart` is the layer below this one: it applies
/// the optimistic update and lets the request fail up to its caller. These are
/// the callers. Every one of them needs a [BuildContext] to put a dialog or a
/// snackbar in front of somebody, which is the whole reason they could not
/// live down there with the rest.
///
/// Split out of `channel_screen.dart`, where the same try/report block was
/// written five times over.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';

import '../providers/message_actions.dart';
import '../providers/message_extras.dart';
import '../providers/pins_controller.dart';
import '../providers/providers.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/report_dialog.dart';

/// Runs [action], and on a refusal from the server says so in [failure]'s
/// words followed by the server's own.
///
/// The mounted check is not decoration: every one of these awaits a network
/// round trip, and a user who leaves the channel meanwhile takes the element
/// this would otherwise reach through with them.
Future<void> _reporting(
  BuildContext context,
  String failure,
  Future<void> Function() action,
) async {
  try {
    await action();
  } on api.ApiException catch (e) {
    if (!context.mounted) return;
    _say(context, '$failure ${e.message}');
  }
}

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Puts a message on screen before the network has answered, then reconciles
/// with the server's copy.
///
/// The id is the caller's and is reused on retry, so a retry after an
/// uncertain failure can never post twice. [onQueued] fires once the local
/// row exists and before the request goes out, which is when a sender wants
/// the transcript scrolled.
Future<void> sendOptimistically(
  WidgetRef ref, {
  required String id,
  required String channelId,
  required String authorId,
  required String content,
  List<String> attachmentIds = const [],
  VoidCallback? onQueued,
}) async {
  final store = await ref.read(storeProvider.future);
  await store.addPending(
    id: id,
    channelId: channelId,
    authorId: authorId,
    content: content,
  );
  onQueued?.call();
  try {
    final sent = await ref
        .read(apiProvider)
        .sendMessage(
          channelId: channelId,
          id: id,
          content: content,
          attachmentIds: attachmentIds,
        );
    // Lands on the same row, because it carries the same id.
    await store.applyMessage(sent);
    ref.read(messageExtrasProvider.notifier).applyMessage(sent);
  } on api.ApiException {
    await store.markFailed(id);
  }
}

/// Re-sends a message whose first attempt failed, under its original id.
Future<void> retryMessage(WidgetRef ref, Message message) => sendOptimistically(
  ref,
  id: message.id,
  channelId: message.channelId,
  authorId: message.authorId ?? '',
  content: message.content,
);

/// Discards a failed send. Nothing reached the server, so nothing to undo.
Future<void> discardMessage(WidgetRef ref, Message message) async =>
    (await ref.read(storeProvider.future)).discard(message.id);

/// Saves an inline edit. Unchanged text is not a request.
Future<void> submitMessageEdit(
  WidgetRef ref,
  BuildContext context,
  Message message,
  String content,
) async {
  if (content == message.content) return;
  await _reporting(
    context,
    'Could not save the edit.',
    () => editMessageAction(ref, message, content),
  );
}

/// Asks first, because a delete removes the message for everyone.
Future<void> confirmAndDeleteMessage(
  WidgetRef ref,
  BuildContext context,
  Message message,
) async {
  final confirmed = await confirmDangerousAction(
    context,
    title: 'Delete message?',
    message:
        'This removes it for everyone in the channel. '
        'This cannot be undone.',
    confirmLabel: 'Delete',
  );
  if (!confirmed || !context.mounted) return;
  await _reporting(
    context,
    'Could not delete the message.',
    () => deleteMessageAction(ref, message),
  );
}

/// Pins or unpins, [pinned] being what it is now rather than what to make it.
Future<void> toggleMessagePin(
  WidgetRef ref,
  BuildContext context, {
  required String channelId,
  required Message message,
  required bool pinned,
}) async {
  final controller = ref.read(pinsControllerProvider(channelId).notifier);
  await _reporting(
    context,
    'Could not update the pin.',
    () => pinned ? controller.unpin(message.id) : controller.pin(message.id),
  );
}

/// Files a report against a message, once the reporter has given a reason.
Future<void> reportMessage(
  WidgetRef ref,
  BuildContext context,
  Message message,
) async {
  final reason = await promptReportReason(
    context,
    subjectLabel: 'this message',
  );
  if (reason == null || !context.mounted) return;
  await _reporting(context, 'Could not file the report.', () async {
    await ref
        .read(apiProvider)
        .report(
          subject: api.ReportSubject.message,
          subjectId: message.id,
          reason: reason,
        );
    if (!context.mounted) return;
    _say(context, 'Report filed. A moderator will review it.');
  });
}

/// Blocks a message's author. A message with no live author has nobody to
/// block, so it is not offered one.
Future<void> blockMessageAuthor(
  WidgetRef ref,
  BuildContext context,
  Message message,
) async {
  final authorId = message.authorId;
  if (authorId == null) return;
  await _reporting(context, 'Could not block that user.', () async {
    await ref.read(apiProvider).blockUser(authorId);
    if (!context.mounted) return;
    _say(context, 'Blocked. Their messages are hidden for you.');
  });
}
