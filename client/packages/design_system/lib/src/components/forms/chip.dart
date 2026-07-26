// SPDX-License-Identifier: Apache-2.0
/// A small token with two variants. `operator` is a static, non-interactive
/// span used in a search bar (`from:priya`); `reaction` is a real button
/// carrying an emoji (user content, never interface chrome), a count, and
/// whether the current user is among the people who reacted.
library;

import 'package:flutter/material.dart';

import '../../app_metrics.dart';
import '../../app_tokens.dart';
import '../../app_typography.dart';
import 'focusable_tap_target.dart';

class AppChip extends StatelessWidget {
  /// A static, non-interactive token: mono text on an accent-soft fill. Used
  /// in the search bar for a structured operator like `from:priya`.
  const AppChip.operator({
    super.key,
    required this.label,
    this.icon,
  })  : _isReaction = false,
        emoji = null,
        count = 0,
        active = false,
        onTap = null;

  /// A real button: an emoji, a count, and whether the current user reacted.
  const AppChip.reaction({
    super.key,
    required this.emoji,
    required this.count,
    required this.active,
    this.onTap,
  })  : _isReaction = true,
        label = null,
        icon = null;

  final bool _isReaction;

  /// Operator-only: the label text (e.g. `from:priya`).
  final String? label;

  /// Operator-only: an optional leading glyph, built by the caller.
  final Widget? icon;

  /// Reaction-only: the emoji glyph. User content, so it is a runtime string
  /// rather than a literal typed into source.
  final String? emoji;

  /// Reaction-only: how many people reacted.
  final int count;

  /// Reaction-only: whether the current user is one of them.
  final bool active;

  final VoidCallback? onTap;

  // Neither the operator's 7px horizontal padding nor the reaction's 6px
  // emoji-to-count gap match a step in AppSpacing (nearest are s8 and s4/s8
  // respectively). The design gives exact pixel values for both, used as
  // literals here and reported as a token gap.
  static const double _operatorPaddingH = 7;
  static const double _reactionGap = 6;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    if (!_isReaction) {
      return Semantics(
        label: label,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: _operatorPaddingH),
          decoration: BoxDecoration(
            color: tokens.accentSoft,
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                icon!,
                const SizedBox(width: AppSpacing.s4)
              ],
              Text(
                label ?? '',
                style: AppText.caption
                    .copyWith(color: tokens.accent, fontFamily: AppFonts.mono),
              ),
            ],
          ),
        ),
      );
    }

    final semanticLabel =
        '${emoji ?? ''} reaction, $count, ${active ? 'you reacted' : 'tap to react'}';

    return FocusableTapTarget(
      onTap: onTap,
      enabled: onTap != null,
      selected: active,
      semanticLabel: semanticLabel,
      ringRadius: AppRadii.full,
      builder: (context, focused, hovered) {
        return Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
          decoration: BoxDecoration(
            color: active ? tokens.accentSoft : tokens.surfaceRaised,
            border: Border.all(
                color: active ? tokens.accentFill : tokens.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 13px, lineHeight 1: the design's own literal, not on the
              // AppText scale (nearest steps are caption 12 and ui 14).
              Text(emoji ?? '',
                  style: const TextStyle(fontSize: 13, height: 1)),
              const SizedBox(width: _reactionGap),
              Text(
                '$count',
                style: AppText.caption.copyWith(
                  color: active ? tokens.accent : tokens.textSecondary,
                  fontWeight: active ? AppWeights.semi : AppWeights.regular,
                  fontFamily: AppFonts.sans,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
