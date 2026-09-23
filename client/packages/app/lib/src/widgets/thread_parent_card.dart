// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The message a thread hangs off, shown once above its replies so a thread
/// never reads as a conversation with no visible subject - before this,
/// `ThreadScreen` resolved `threadParentProvider` only for its own AppBar
/// title and never rendered the parent message anywhere.
///
/// Styled after `ForwardedMessageCard`'s own boxed treatment (a bordered,
/// sunken container with an icon+label row over an avatar+name row) rather
/// than `ReplyQuote`'s bare inline line: a reply quote sits inside another
/// message's own row, where a full box would crowd it, but this card is the
/// only thing above the transcript and reads better as a small
/// self-contained block. The body stays a truncated snippet, matching
/// `ReplyQuote`'s and `ThreadRow`'s (`threads_sheet.dart`) own ceiling,
/// rather than the full markdown render `MessageBody` gives an ordinary
/// row - this is context for orientation, not a second copy of the message
/// to read in full.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/user_profiles.dart';
import 'author_label.dart';
import 'message_jump.dart';
import 'user_avatar.dart';

/// How much of the parent's own text is shown before it is cut off, matching
/// `ReplyQuote`'s own ceiling.
const int _snippetMaxRunes = 240;

/// The avatar beside the parent's own author, matching
/// `ForwardedMessageCard`'s own quoted-author sizing.
const double _avatarSize = 20;

class ThreadParentCard extends ConsumerWidget {
  const ThreadParentCard({
    super.key,
    required this.parent,
    required this.threadChannelId,
  });

  final api.ThreadParent parent;

  /// This thread's own channel id, so a tap that jumps to the parent (which
  /// always lives somewhere else) knows what it is jumping away from.
  final String threadChannelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    resolveAuthorProfiles(ref, [parent.parentAuthorId]);

    final decoration = BoxDecoration(
      color: tokens.surfaceSunken,
      border: Border.all(color: tokens.borderSubtle),
      borderRadius: BorderRadius.circular(AppRadii.control),
    );
    final header = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.thread, size: 13, color: tokens.textSecondary),
        const SizedBox(width: AppSpacing.s4),
        Text(
          'Thread on',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
      ],
    );

    final Widget body;
    final String semanticLabel;
    if (parent.parentDeleted) {
      body = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.delete, size: 13, color: tokens.textSecondary),
          const SizedBox(width: AppSpacing.s4),
          Text(
            'This message was deleted.',
            style: AppText.caption.copyWith(
              color: tokens.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
      semanticLabel = 'Thread on a message that was deleted';
    } else {
      final resolution = ref.watch(
        batchProfilesControllerProvider.select(
          (m) => authorResolution(m, parent.parentAuthorId ?? ''),
        ),
      );
      final name = authorLabelResolved(
        authorId: parent.parentAuthorId,
        cachedDisplayName: parent.parentAuthorDisplayName,
        resolution: resolution,
      );
      final snippet = _snippet(parent.parentContent ?? '');
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthorAvatar(
            name: name,
            userId: parent.parentAuthorId,
            size: _avatarSize,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AuthorNameLine(
                  name: name,
                  profile: resolution.profile,
                  style: AppText.caption.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: AppWeights.semi,
                  ),
                ),
                Text(
                  snippet,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
        ],
      );
      semanticLabel = 'Thread on $name: $snippet';
    }

    final canJump =
        !parent.parentDeleted &&
        parent.parentChannelId != null &&
        parent.parentMessageId != null;
    // On tap, not on build: eager lookup would demand a router from every surface a message renders on. Mirrors ForwardedMessageCard.
    final onJump = !canJump
        ? null
        : () => jumpToMessage(
            GoRouter.of(context),
            ref.read,
            currentChannelId: threadChannelId,
            channelId: parent.parentChannelId!,
            messageId: parent.parentMessageId!,
          );

    final card = Container(
      decoration: decoration,
      padding: const EdgeInsets.all(AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          const SizedBox(height: AppSpacing.s4),
          body,
        ],
      ),
    );

    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s12,
        AppSpacing.s12,
        0,
      ),
      child: Semantics(
        button: onJump != null,
        label: onJump != null
            ? '$semanticLabel, go to the original'
            : semanticLabel,
        child: ExcludeSemantics(child: card),
      ),
    );

    if (onJump == null) return padded;
    return AppFocusRing(
      radius: AppRadii.control,
      builder: (context, onFocusChange) => InkWell(
        onTap: onJump,
        // AppFocusRing replaces this overlay; see ForwardedMessageCard's own copy.
        focusColor: Colors.transparent,
        onFocusChange: onFocusChange,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: padded,
      ),
    );
  }
}

/// A one-line, rune-safe truncation - matches `ReplyQuote._snippet`, since
/// `String.substring` cuts mid-surrogate on a codepoint outside the BMP.
String _snippet(String content) {
  final oneLine = content.replaceAll('\n', ' ').trim();
  if (oneLine.isEmpty) return '(no text)';
  final runes = oneLine.runes.toList(growable: false);
  if (runes.length <= _snippetMaxRunes) return oneLine;
  return '${String.fromCharCodes(runes.take(_snippetMaxRunes))}…';
}
