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
import '../widgets/run_guarded.dart';
import '../widgets/safety_actions.dart';

/// Runs [action], and on a refusal from the server says so.
///
/// The mounted check is not decoration: every one of these awaits a network
/// round trip, and a user who leaves the channel meanwhile takes the element
/// this would otherwise reach through with them.
Future<void> _reporting(
  BuildContext context,
  String whatFailed,
  Future<void> Function() action,
) async {
  final failure = await runGuarded(whatFailed: whatFailed, action: action);
  if (failure != null && context.mounted) _say(context, failure);
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
  String? replyToId,
  VoidCallback? onQueued,
}) async {
  final store = await ref.read(storeProvider.future);
  await store.addPending(
    id: id,
    channelId: channelId,
    authorId: authorId,
    content: content,
    replyToId: replyToId,
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
          replyToId: replyToId,
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
  replyToId: message.replyToId,
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
    'save the edit',
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
    'delete the message',
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
    'update the pin',
    () => pinned ? controller.unpin(message.id) : controller.pin(message.id),
  );
}

/// Files a report against a message, once the reporter has given a reason.
///
/// [ref] is unused: `fileReport` takes a [ProviderContainer], derived from
/// [context] below, because this row's context never gets popped out from
/// under it the way the member popover's does. The parameter stays only so
/// this keeps its call site's shape unchanged.
Future<void> reportMessage(BuildContext context, Message message) => fileReport(
  context,
  ProviderScope.containerOf(context, listen: false),
  subject: api.ReportSubject.message,
  subjectId: message.id,
  subjectLabel: 'this message',
);

/// Blocks a message's author. A message with no live author has nobody to
/// block, so it is not offered one.
Future<void> blockMessageAuthor(BuildContext context, Message message) async {
  final authorId = message.authorId;
  if (authorId == null) return;
  await blockUser(
    context,
    ProviderScope.containerOf(context, listen: false),
    authorId,
  );
}
