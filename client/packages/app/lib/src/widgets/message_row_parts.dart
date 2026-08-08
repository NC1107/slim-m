// SPDX-License-Identifier: Apache-2.0
/// The smaller pieces a message row can carry beneath its body: the edited
/// marker, the reactions row, an attachment placeholder, the failed-send
/// row, and the "New" divider between read and unread messages.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/display_preferences.dart';
import '../routing/breakpoints.dart';

import 'custom_emoji_image.dart';
import 'emoji_picker.dart';
import 'message_row_identity.dart' show formatMessageDay, formatMessageTime;

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
  });

  final List<api.ReactionSummary> reactions;
  final ValueChanged<api.ReactionSummary> onReactionTap;

  /// Called with the emoji character the picker chose.
  final ValueChanged<String> onPickReaction;

  /// The deployment's custom emoji, lower-cased name to id. Empty while the
  /// set is loading or unfetchable, which leaves a shortcode reaction as the
  /// literal text it already was, exactly as a message body degrades.
  final Map<String, String> customEmoji;

  /// Renders existing reactions and nothing else.
  ///
  /// The add-a-reaction control used to live here, revealed on hover, and
  /// that is what made rows jump: an unreacted message rendered nothing, so
  /// hovering swapped absent for present and grew the row, moving the whole
  /// log under the pointer. It lives in [MessageRow]'s hover overlay now,
  /// outside layout entirely.
  ///
  /// The reasoning that put it here was sound and still holds - a permanent
  /// add-button under every message costs a row of vertical space each and
  /// turns a quiet list into a grid of identical glyphs. That is why the fix
  /// is an overlay rather than reserving the space: reserving it would buy
  /// back exactly the cost this avoided.
  ///
  /// Pulled tight against the body above by [AppSpacing.s4] - the closest
  /// step to the few pixels of line-height leftover a real device still
  /// showed at a flush 0 - as a [Transform.translate] rather than a negative
  /// [Padding], which asserts its insets are non-negative. That is safe here
  /// specifically because [FailedRow] is this row's only possible sibling
  /// below it in [MessageRow]'s column, and the two never render together:
  /// both key off `_unsent`, and this row only ever shows once that is false.
  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();

    // See the negative-inset note on this class's own doc comment above.
    return Transform.translate(
      offset: const Offset(0, -AppSpacing.s4),
      child: Wrap(
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
        ],
      ),
    );
  }
}

/// The "N replies" affordance under a message that has an opened thread,
/// tapping through to it - Slack's shape, which is what the owner named.
///
/// Absent entirely for a message with no thread, and also for a thread with
/// nobody in it yet: [Message.threadReplyCount] is `0` right after a thread
/// is opened but before the first reply lands, and an empty "0 replies" row
/// would read as a feature that broke rather than as nothing to show.
///
/// [onTap] is only ever wired when the caller's own [MessageActions.canOpenThread]
/// is true; when it is false (view-only, or a rare race with the parent's own
/// permissions changing) this renders as inert text rather than a button that
/// would just 403 on tap, the same "no tap handler at all" treatment
/// `AppSegmentedOption.disabled` already gives an unavailable choice.
///
/// Always its own `Semantics(container: true)`, tappable or not: static text
/// still has to be its own stop for a screen reader, and without a boundary
/// here it would merge into the row's own long-press semantics, reading an
/// inert row as actionable.
class ThreadReplySummary extends ConsumerWidget {
  const ThreadReplySummary({
    super.key,
    required this.replyCount,
    this.lastReplyAt,
    this.onTap,
  });

  final int replyCount;
  final int? lastReplyAt;

  /// Opens (or reuses) the thread and navigates to it. Null makes this
  /// inert; see this class's own doc comment for when that happens.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final enabled = onTap != null;
    final color = enabled ? tokens.accent : tokens.textDisabled;
    final countLabel = replyCount == 1 ? '1 reply' : '$replyCount replies';
    final lastReplyAt = this.lastReplyAt;
    final use24Hour = watchUse24Hour(ref, context);
    final text = lastReplyAt == null
        ? countLabel
        : '$countLabel · Last reply '
              '${_lastReplyLabel(lastReplyAt, use24Hour: use24Hour)}';
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(AppIcons.thread, size: 13, color: color),
        const SizedBox(width: AppSpacing.s4),
        // Flexible, not a bare Text: an absolute "Last reply" date can overflow a phone-width row otherwise.
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: color),
          ),
        ),
      ],
    );
    final padded = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s4),
      child: row,
    );
    // See this class's own doc comment for why `container` is always true.
    return Semantics(
      container: true,
      button: enabled,
      label: enabled ? '$text. Open thread.' : text,
      child: enabled
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: padded,
            )
          : padded,
    );
  }
}

/// The exact time when the newest reply is from today (more useful than
/// "Today" would be for a channel with any real traffic), the relative or
/// absolute day otherwise - [formatMessageDay]'s own scale, reused rather
/// than inventing a second one just for this row.
String _lastReplyLabel(int epochMs, {required bool use24Hour}) {
  final day = formatMessageDay(epochMs);
  return day == 'Today'
      ? formatMessageTime(epochMs, use24Hour: use24Hour)
      : day;
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
  const FailedRow({
    super.key,
    required this.onRetry,
    required this.onDiscard,
    this.onEdit,
    this.reason,
  });

  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  /// Puts the failed text somewhere editable rather than losing it; absent,
  /// the action is simply not offered.
  final VoidCallback? onEdit;

  /// Why the send failed, already a plain sentence from `describeApiFailure`
  /// - never shown at all for an older local row that predates this field,
  /// rather than a placeholder claiming to know something it does not.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // The time slot already says "not sent" in red (MessageTimeMark), so
    // these buttons are only the way forward: Retry outlined in danger, the
    // neutral verbs beside it (error grammar: red is outlined, never filled,
    // and always ships a verb).
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reason != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s4),
              child: Text(
                reason!,
                style: AppText.label.copyWith(color: tokens.dangerText),
              ),
            ),
          Wrap(
            spacing: AppSpacing.s8,
            children: [
              AppButton(
                label: 'Retry',
                size: AppButtonSize.sm,
                variant: AppButtonVariant.danger,
                onPressed: onRetry,
              ),
              if (onEdit != null)
                AppButton(
                  label: 'Edit',
                  size: AppButtonSize.sm,
                  onPressed: onEdit,
                ),
              AppButton(
                label: 'Discard',
                size: AppButtonSize.sm,
                onPressed: onDiscard,
              ),
            ],
          ),
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
