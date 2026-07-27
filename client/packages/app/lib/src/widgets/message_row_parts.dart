// SPDX-License-Identifier: Apache-2.0
/// The smaller pieces a message row can carry beneath its body: the edited
/// marker, the reactions row, an attachment placeholder, the failed-send
/// row, and the "New" divider between read and unread messages.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import 'emoji_picker.dart';

class EditedMarker extends StatelessWidget {
  const EditedMarker({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '(edited)',
        style: AppText.micro.copyWith(
          color: tokens.textSecondary,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: tokens.textSecondary,
        ),
      ),
    );
  }
}

/// One chip per distinct emoji already on the message (real counts, and
/// [api.ReactionSummary.reacted] driving the active state), plus the
/// add-reaction glyph, which opens [EmojiPickerButton]'s floating picker.
/// Tapping an existing chip calls [onReactionTap] with that summary; the
/// caller decides whether that means adding or removing based on whether it
/// was already active.
class ReactionsRow extends StatelessWidget {
  const ReactionsRow({
    super.key,
    required this.reactions,
    required this.onReactionTap,
    required this.onPickReaction,
    this.showAddButton = false,
  });

  final List<api.ReactionSummary> reactions;
  final ValueChanged<api.ReactionSummary> onReactionTap;

  /// Called with the emoji character the picker chose.
  final ValueChanged<String> onPickReaction;

  /// Whether to offer the add-a-reaction control. The row keeps rendering
  /// existing reactions without it.
  final bool showAddButton;

  @override
  Widget build(BuildContext context) {
    // The design shows a reactions row only on a message that has one. A
    // permanent add-button under every message costs a row of vertical space
    // each and turns a quiet list into a grid of identical glyphs; the
    // affordance belongs on hover, with the row absent until then.
    if (reactions.isEmpty && !showAddButton) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: AppSpacing.s4,
        runSpacing: AppSpacing.s4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final reaction in reactions)
            AppChip.reaction(
              emoji: reaction.emoji,
              count: reaction.count,
              active: reaction.reacted,
              onTap: () => onReactionTap(reaction),
            ),
          if (showAddButton) EmojiPickerButton(onSelect: onPickReaction),
        ],
      ),
    );
  }
}

/// The design's bordered "not loaded" placeholder, using [AppTokens.stripe],
/// the token reserved for exactly that state. Real attachments render
/// through `AttachmentView` now; this is what it shows for an image still
/// in flight, or on a server too old to answer the fetch at all.
class AttachmentPlaceholder extends StatelessWidget {
  const AttachmentPlaceholder({super.key, this.width = 420, this.height = 168});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: tokens.stripe,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
    );
  }
}

class FailedRow extends StatelessWidget {
  const FailedRow({super.key, required this.onRetry, required this.onDiscard});

  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s4),
      child: Row(
        children: [
          Icon(
            AppIcons.failed,
            size: AppSizes.icon16,
            color: tokens.dangerText,
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            'Not sent.',
            style: AppText.caption.copyWith(color: tokens.dangerText),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
          TextButton(onPressed: onDiscard, child: const Text('Discard')),
        ],
      ),
    );
  }
}

/// The row that marks where a channel's unread messages begin, placed
/// directly above the first one past the read marker.
class NewMessagesDivider extends StatelessWidget {
  const NewMessagesDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          Container(height: 1, color: tokens.accentFill.withValues(alpha: 0.5)),
          Container(
            padding: const EdgeInsets.only(left: AppSpacing.s8),
            color: tokens.surfaceBase,
            child: Text(
              'NEW',
              style: AppText.label.copyWith(color: tokens.accent),
            ),
          ),
        ],
      ),
    );
  }
}
