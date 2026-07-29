// SPDX-License-Identifier: Apache-2.0
/// The smaller pieces a message row can carry beneath its body: the edited
/// marker, the reactions row, an attachment placeholder, the failed-send
/// row, and the "New" divider between read and unread messages.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../routing/breakpoints.dart';

import 'custom_emoji_image.dart';
import 'emoji_picker.dart';

/// 16, not the 13 the chip's text glyph uses: 13 is a font size, and an emoji
/// face draws well inside its em box while an image fills whatever box it gets.
const double _reactionEmojiSize = 16;

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
///
/// A reaction key is not always a codepoint. The server keys a reaction on
/// whatever short string it is given, so one of the deployment's own emoji
/// rides there as its `:shortcode:` and is drawn here through [customEmoji],
/// the same index a message body resolves against.
class ReactionsRow extends StatelessWidget {
  const ReactionsRow({
    super.key,
    required this.reactions,
    required this.onReactionTap,
    required this.onPickReaction,
    this.customEmoji = const {},
    this.showAddButton = false,
  });

  final List<api.ReactionSummary> reactions;
  final ValueChanged<api.ReactionSummary> onReactionTap;

  /// Called with the emoji character the picker chose.
  final ValueChanged<String> onPickReaction;

  /// The deployment's custom emoji, lower-cased name to id. Empty while the
  /// set is loading or unfetchable, which leaves a shortcode reaction as the
  /// literal text it already was, exactly as a message body degrades.
  final Map<String, String> customEmoji;

  /// Whether to offer the add-a-reaction control. The row keeps rendering
  /// existing reactions without it.
  final bool showAddButton;

  /// The design shows a reactions row only on a message that has one. A
  /// permanent add-button under every message costs a row of vertical space
  /// each and turns a quiet list into a grid of identical glyphs, so the
  /// affordance belongs on hover with the row absent until then.
  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty && !showAddButton) return const SizedBox.shrink();

    // No top inset: it reads as part of the message above, not a new line.
    return Wrap(
      spacing: AppSpacing.s4,
      runSpacing: AppSpacing.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Keyed by emoji and wrapped in a one-shot pop (scale .85 to 1 with
        // fade): a chip that just appeared confirms the tap landed, and an
        // existing chip keeps its state so it never replays.
        for (final reaction in reactions)
          _ChipPop(
            key: ValueKey('reaction-${reaction.emoji}'),
            child: AppChip.reaction(
              emoji: reaction.emoji,
              count: reaction.count,
              active: reaction.reacted,
              glyph: switch (customEmojiIdFor(reaction.emoji, customEmoji)) {
                final String id => CustomEmojiImage(
                  emojiId: id,
                  size: _reactionEmojiSize,
                ),
                null => null,
              },
              onTap: () => onReactionTap(reaction),
            ),
          ),
        if (showAddButton) EmojiPickerButton(onSelect: onPickReaction),
      ],
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
    // The rows' own gutter, or the divider sits 10dp right of them on phones.
    final gutter = LayoutClass.of(context) == LayoutClass.compact
        ? AppSizes.paneGutterCompact
        : AppSizes.paneGutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 14, gutter, 6),
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

/// A calendar-day separator: a centred date with a rule to each side, shown
/// above the first message of a new day. It answers the "two messages a day
/// apart still just show the time" gap, where a timestamp alone cannot say
/// which day it belongs to.
class DayDivider extends StatelessWidget {
  const DayDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final gutter = LayoutClass.of(context) == LayoutClass.compact
        ? AppSizes.paneGutterCompact
        : AppSizes.paneGutter;
    Widget rule() =>
        Expanded(child: Container(height: 1, color: tokens.borderSubtle));
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 6),
      child: Row(
        children: [
          rule(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
            child: Text(
              label,
              // Mono with tabular figures: dates and times are the mono
              // surfaces in this system, and the brand rides on that.
              style: AppText.label.copyWith(
                color: tokens.textSecondary,
                fontFamily: AppFonts.mono,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          rule(),
        ],
      ),
    );
  }
}

/// A one-shot pop for a chip that just appeared: scale .85 to 1 with a fade,
/// the motion spec's confirmation entrance. Mount-only, so a rebuild of an
/// existing chip never replays it.
class _ChipPop extends StatelessWidget {
  const _ChipPop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: AppMotion.reduced(context, AppMotion.pop),
    curve: AppMotion.entrance,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
    ),
    child: child,
  );
}
