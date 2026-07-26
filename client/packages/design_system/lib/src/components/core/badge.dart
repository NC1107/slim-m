// SPDX-License-Identifier: Apache-2.0
/// A small label chip: an unread count, a member role, a bot tag, or a
/// stale-ness warning.
///
/// Only [AppBadgeVariant.count] is filled; the other three are outlined and
/// unfilled, each with its own letter-spacing (0.06/0.08/0.05em for
/// role/tag/warn). [AppBadgeVariant.role] is not per-role-coloured: the
/// source design styles it from the accent, the same for every role, so a
/// caller cannot recolour it per role even though real role data usually
/// carries one. Ported as specified rather than "improved" with a colour
/// parameter the design does not have.
library;

import 'package:flutter/material.dart';

import '../../app_metrics.dart';
import '../../app_tokens.dart';
import '../../app_typography.dart';

enum AppBadgeVariant { count, role, tag, warn }

class AppBadge extends StatelessWidget {
  const AppBadge(
      {super.key,
      required this.variant,
      required this.label,
      this.icon,
      this.semanticLabel});

  /// Convenience for the unread-count case: caps a large count rather than
  /// growing the pill to fit an arbitrarily wide number.
  factory AppBadge.count(int count, {Key? key, int max = 99}) {
    return AppBadge(
        key: key,
        variant: AppBadgeVariant.count,
        label: count > max ? '$max+' : '$count');
  }

  final AppBadgeVariant variant;
  final String label;

  /// A small leading glyph, gapped from the label. Optional in every
  /// variant.
  final IconData? icon;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    // The source design sets role/tag/warn at a literal 10px, a step the
    // six-size type scale (11/12/14/15/20/24) does not have; [AppText.micro]
    // (11px) is the nearest and is used for all four rather than a one-off.
    final fontSize = AppText.micro.fontSize!;

    final Color? background;
    final Color foreground;
    final Color border;
    final String text;
    var letterSpacing = 0.0;
    var tabularNumerals = false;

    switch (variant) {
      case AppBadgeVariant.count:
        background = tokens.accentFill;
        foreground = tokens.accentOn;
        border = tokens.accentFill;
        text = label;
        tabularNumerals = true;
      case AppBadgeVariant.role:
        background = null;
        foreground = tokens.accent;
        border = tokens.accentFill;
        text = label.toUpperCase();
        letterSpacing = fontSize * 0.06;
      case AppBadgeVariant.tag:
        background = null;
        foreground = tokens.textSecondary;
        border = tokens.borderSubtle;
        text = label.toUpperCase();
        letterSpacing = fontSize * 0.08;
      case AppBadgeVariant.warn:
        background = null;
        foreground = tokens.warnText;
        border = tokens.warnText;
        text = label.toUpperCase();
        letterSpacing = fontSize * 0.05;
        tabularNumerals = true;
    }

    final textStyle = TextStyle(
      fontFamily: AppFonts.sans,
      fontSize: fontSize,
      fontWeight: AppWeights.semi,
      color: foreground,
      letterSpacing: letterSpacing,
      fontFeatures:
          tabularNumerals ? const [FontFeature.tabularFigures()] : null,
    );

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: AppSizes.icon16, color: foreground),
          const SizedBox(width: AppSpacing.s4),
        ],
        Text(text, style: textStyle),
      ],
    );

    final Widget badge;
    if (variant == AppBadgeVariant.count) {
      badge = Container(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadii.full)),
        child: child,
      );
    } else {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: child,
      );
    }

    // Without ExcludeSemantics, the inner Text's own auto-generated label
    // merges with the explicit one below into a doubled announcement.
    return Semantics(
      // `label`, not `text`: three variants uppercase their display string,
      // and many screen readers read an all-caps word letter by letter.
      label: semanticLabel ?? label,
      container: true,
      child: ExcludeSemantics(child: badge),
    );
  }
}
