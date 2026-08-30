// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Everything below the transcript: the reply banner and composer normally,
/// and the selection bar while messages are being picked for deletion.
///
/// One slot with two states rather than a stack, because the two are
/// mutually exclusive in fact: nothing can be composed into a transcript that
/// is being selected out of, and a reply banner left showing would name a
/// message the send button can no longer act on.
///
/// Extracted from `channel_screen.dart` rather than added to it. That file
/// sits at a 500-line hard ceiling with single digits to spare, and the
/// selection branch does not fit; the same pressure already moved
/// `messageActionsFor` into `channel_message_actions.dart`. It lives beside
/// the screen rather than in `widgets/` because deleting a selection is a
/// screen-level act - it confirms, reports failure, and leaves the mode.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/message_selection.dart';
import '../providers/providers.dart';
import '../widgets/composer.dart';
import '../widgets/message_selection_bar.dart';
import '../widgets/reply_banner.dart';
import '../widgets/timeout_banner.dart';
import 'channel_message_actions.dart';

class ChannelComposerArea extends ConsumerWidget {
  const ChannelComposerArea({
    required this.channelId,
    required this.controller,
    required this.channelName,
    required this.onSend,
    required this.replyingTo,
    required this.onCancelReply,
    super.key,
  });

  final String channelId;
  final TextEditingController controller;
  final String channelName;
  final Future<void> Function(List<String>) onSend;
  final Message? replyingTo;
  final VoidCallback onCancelReply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(messageSelectionProvider(channelId)).active) {
      return MessageSelectionBar(
        channelId: channelId,
        onDelete: () => confirmAndDeleteSelectedMessages(
          ref,
          context,
          channelId: channelId,
        ),
      );
    }
    final me = ref.watch(meProvider).valueOrNull;
    final timedOutUntil = me?.timedOutUntil;
    final stillTimedOut =
        timedOutUntil != null &&
        timedOutUntil > DateTime.now().millisecondsSinceEpoch;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppRevealBand(
          child: stillTimedOut
              ? TimeoutBanner(until: timedOutUntil, reason: me?.timeoutReason)
              : null,
        ),
        AppRevealBand(
          child: replyingTo == null
              ? null
              : ReplyBanner(message: replyingTo!, onCancel: onCancelReply),
        ),
        Composer(
          controller: controller,
          channelId: channelId,
          channelName: channelName,
          onSend: onSend,
        ),
      ],
    );
  }
}
