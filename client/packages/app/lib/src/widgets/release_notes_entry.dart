// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// One version's notes, drawn the same way in the what's-new sheet and the
/// full history under About.
///
/// The version is its own badge so a reader can tell releases apart at a
/// glance, the headline is the heading under it, and each point is a real
/// list item with a hanging indent. A warning point stays an [AppCallout] so
/// it cannot be skimmed past.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../whats_new/whats_new_content.dart';

/// The badge and headline that open an entry.
class ReleaseNotesHeading extends StatelessWidget {
  const ReleaseNotesHeading({super.key, required this.entry});

  final WhatsNewEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppBadge(
          variant: AppBadgeVariant.role,
          label: entry.version,
          semanticLabel: 'Version ${entry.version}',
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          entry.headline,
          style: AppText.body.copyWith(
            color: tokens.textPrimary,
            fontWeight: AppWeights.semi,
          ),
        ),
      ],
    );
  }
}

/// The points of an entry, without its heading.
class ReleaseNotesPoints extends StatelessWidget {
  const ReleaseNotesPoints({super.key, required this.entry});

  final WhatsNewEntry entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final point in entry.points)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: point.warn
                ? AppCallout(tone: AppCalloutTone.warn, child: Text(point.body))
                : _Bullet(text: point.body),
          ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  static const double _dot = AppSpacing.s4 + 1;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final style = AppText.body.copyWith(color: tokens.textSecondary);
    final lineHeight = style.fontSize! * style.height!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: AppSpacing.s16,
          height: lineHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: _dot,
              height: _dot,
              decoration: BoxDecoration(
                color: tokens.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
