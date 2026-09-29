// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Marks a voice channel that joins with the mic off, so nobody is surprised
/// by a muted mic on arrival.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

const joinMutedLabel = 'Joins muted';

/// The glyph alone, for a row with no room for words.
class JoinMutedBadge extends StatelessWidget {
  const JoinMutedBadge({super.key, this.size = AppSizes.icon16});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Tooltip(
      message: joinMutedLabel,
      child: Icon(
        AppIcons.micOff,
        size: size,
        color: tokens.textSecondary,
        semanticLabel: joinMutedLabel,
      ),
    );
  }
}

/// The glyph with its words, for the screen a member joins from.
class JoinMutedNote extends StatelessWidget {
  const JoinMutedNote({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      label: 'This channel joins muted. You can unmute once you are in.',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            AppIcons.micOff,
            size: AppSizes.icon16,
            color: tokens.textSecondary,
          ),
          const SizedBox(width: AppSpacing.s8),
          Flexible(
            child: Text(
              'Joins with your mic off',
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
