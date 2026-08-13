// SPDX-License-Identifier: Apache-2.0
/// Forwarding a message: picking where, composing the content, and sending
/// it - three small pieces the context menu's "Forward message" item drives.
///
/// The wire shape is deliberately the plainest one available: an ordinary
/// `POST /channels/{id}/messages` whose content opens with a markdown quote
/// block, never a stretched `reply_to_id`. `reply_to_id` was the other
/// option, and it is refused outright the moment a target crosses channels -
/// `Store::send_message` in `crates/slimm-server/src/store/messages.rs`
/// checks a reply's parent against the *exact* destination channel and
/// answers `SendError::InvalidReplyTarget` otherwise, precisely because
/// letting a reply point at a message the recipient may not even be able to
/// view would be a new cross-channel read this project has never granted.
/// A plain send needs no such check: everything it can name is text this
/// client already has in hand, and the destination picker itself only ever
/// offers a channel or DM the caller can already send to.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Unprefixed (for `sendMessage`, an extension method only visible where its
// library is imported - see api.dart's own `show` list comment), `Message`
// hidden: `slimm_data` has its own local-store `Message`, the one this file
// actually renders and forwards, and the two names collide.
import 'package:slimm_api/api.dart' hide Message;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../ids.dart';
import '../providers/forward_targets.dart';
import '../providers/message_extras.dart';
import '../providers/providers.dart';
import '../providers/user_profiles.dart';
import 'app_snackbar.dart';
import 'author_label.dart';
import 'run_guarded.dart';

/// Quotes [message]'s current content as a markdown block quote, attributed
/// to its author, the same `>`-per-line syntax `message_markdown_blocks.dart`
/// already renders - so a forward reads correctly on every existing client
/// with no new markup to teach any of them.
String buildForwardedContent({
  required String authorLabel,
  required String content,
}) {
  final quoted = content.split('\n').map((line) => '> $line').join('\n');
  return 'Forwarded from $authorLabel\n$quoted';
}

/// Opens the destination picker, then sends the forward. Returns once the
/// sheet is dismissed either way; a cancelled pick sends nothing.
Future<void> forwardMessage(
  BuildContext context,
  WidgetRef ref,
  Message message,
) async {
  final target = await showAppSheet<ForwardTarget>(
    context,
    builder: (context) =>
        _ForwardTargetSheet(excludeChannelId: message.channelId),
  );
  if (target == null || !context.mounted) return;

  final authorName = authorLabel(
    authorId: message.authorId,
    cachedDisplayName: message.authorDisplayName,
    profiles: ref.read(batchProfilesControllerProvider),
  );
  final failure = await runGuarded(
    whatFailed: 'forward the message',
    action: () => _sendForward(ref, message, target, authorName),
  );
  if (!context.mounted) return;
  showAppSnackbar(context, failure ?? 'Forwarded to ${target.label}.');
}

Future<void> _sendForward(
  WidgetRef ref,
  Message message,
  ForwardTarget target,
  String authorName,
) async {
  final content = buildForwardedContent(
    authorLabel: authorName,
    content: message.content,
  );
  final sent = await ref
      .read(apiProvider)
      .sendMessage(
        channelId: target.channelId,
        id: newMessageId(),
        content: content,
      );
  final store = await ref.read(storeProvider.future);
  await store.applyMessage(sent);
  ref.read(messageExtrasProvider.notifier).applyMessage(sent);
}

const _headingPadding = EdgeInsets.fromLTRB(
  AppSpacing.s16,
  0,
  AppSpacing.s16,
  AppSpacing.s12,
);

/// Lists every [ForwardTarget], newest-channel-first exactly as the API
/// already orders channels and DMs - no re-sorting here, since a forward is
/// a one-off pick rather than a list somebody scans repeatedly.
class _ForwardTargetSheet extends ConsumerWidget {
  const _ForwardTargetSheet({required this.excludeChannelId});

  final String excludeChannelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(forwardTargetsProvider(excludeChannelId));
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: _headingPadding,
            child: Text('Forward to', style: AppText.heading),
          ),
          AppAsyncView(
            value: AppAsyncState(
              data: targets.valueOrNull,
              error: targets.error,
            ),
            errorMessage: 'Could not load where you can forward this.',
            onRetry: () =>
                ref.invalidate(forwardTargetsProvider(excludeChannelId)),
            emptyMessage: 'Nowhere to forward this to yet.',
            isEmpty: (list) => list.isEmpty,
            data: (context, list) => ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final target in list)
                    AppListRow(
                      leading: Icon(
                        target.isDm ? AppIcons.account : AppIcons.hash,
                      ),
                      label: target.label,
                      onTap: () => Navigator.of(context).pop(target),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
