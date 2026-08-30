// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A bordered content surface: the baseline building block for anything that
/// groups related content off the plain background.
///
/// Elevation here is border-first like the rest of the system: a hairline
/// plus a raised (or sunken) fill, a shadow only for [floating]. The source
/// `Card.jsx` is a purely presentational panel with no click handling of its
/// own, so this port has none either; a clickable card is a different
/// component built from this one, not a variant of it.
library;

import 'package:flutter/material.dart';

import '../../app_metrics.dart';
import '../../app_tokens.dart';
import '../../app_typography.dart';

/// A bordered content container with an optional uppercase micro title header.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.title,
    this.action,
    this.floating = false,
    this.sunken = false,
    this.padding = const EdgeInsets.all(AppSpacing.s16),
    this.semanticLabel,
  });

  final Widget child;

  /// An uppercase micro-label header, with its own bottom hairline. Rendered
  /// only when non-null, matching the source's `{title && (...)}`.
  final String? title;

  /// A widget pinned to the end of the title row (an icon button, a link).
  /// Has no effect when [title] is null: the source's header, including this
  /// slot, only exists at all once there is a title to put it next to.
  final Widget? action;

  /// Adds `--shadow-float`, the one shadow token a genuinely floating surface
  /// gets (a dragged canvas window, a modal) - distinct from `--shadow-menu`,
  /// which belongs to [AppMenu] alone.
  final bool floating;

  /// Uses `surfaceSunken` instead of `surfaceRaised`, for a card nested inside
  /// an already-raised surface.
  final bool sunken;
  final EdgeInsetsGeometry padding;

  /// Falls back to nothing: a card's content is usually already legible to a
  /// screen reader without a synthetic label layered on top of it.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: sunken ? tokens.surfaceSunken : tokens.surfaceRaised,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: floating ? AppShadows.float : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.s12,
                horizontal: AppSpacing.s16,
              ),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppText.label.copyWith(color: tokens.textSecondary),
                    ),
                  ),
                  if (action != null) action!,
                ],
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );

    return Semantics(label: semanticLabel, container: true, child: card);
  }
}
