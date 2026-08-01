// SPDX-License-Identifier: Apache-2.0
/// The strip above the composer while a reply is staged: who it targets, a
/// one-line snippet, and a way to cancel back to an ordinary send.
///
/// Unlike `reply_quote.dart`, this never has a resolution problem to render
/// honestly: the message it names is always one this session just fetched
/// and is looking straight at, since the only way to start a reply is
/// tapping "Reply" on a row already on screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/user_profiles.dart';
import 'author_label.dart';

class ReplyBanner extends ConsumerWidget {
  const ReplyBanner({super.key, required this.message, required this.onCancel});

  final Message message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final label = authorLabel(
      authorId: message.authorId,
      cachedDisplayName: message.authorDisplayName,
      profiles: ref.watch(batchProfilesControllerProvider),
    );
    final snippet = message.content.replaceAll('\n', ' ').trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s8,
        ),
        child: Row(
          children: [
            Icon(AppIcons.reply, size: 14, color: tokens.textSecondary),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Replying to $label',
                      style: AppText.caption.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: AppWeights.semi,
                      ),
                    ),
                    if (snippet.isNotEmpty)
                      TextSpan(
                        text: '  $snippet',
                        style: AppText.caption.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AppIconButton(
              icon: AppIcons.dismiss,
              semanticLabel: 'Cancel reply',
              tooltip: 'Cancel reply',
              size: AppIconButtonSize.sm,
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}
