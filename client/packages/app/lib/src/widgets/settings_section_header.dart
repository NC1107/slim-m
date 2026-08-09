// SPDX-License-Identifier: Apache-2.0
/// The two headers settings is built from: a group header naming who a run of
/// sections belongs to, and the section header each one opens with.
///
/// Pulled out of the original combined settings screen so a new section (the
/// avatar one) could share it without that file growing past its line budget.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// Names who the sections under it belong to. Personal and Space settings
/// are separate screens now, so the one caller left is [AppInfoSection],
/// naming its "App" group against the personal sections above it on the
/// same screen.
///
/// A step up the type scale from [SettingsSectionHeader] rather than a
/// different colour, so the two levels stay apart for a reader who cannot
/// tell the colours apart.
class SettingsGroupHeader extends StatelessWidget {
  const SettingsGroupHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s24,
        AppSpacing.s16,
        0,
      ),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: AppText.heading.copyWith(
            color: tokens.textPrimary,
            fontWeight: AppWeights.semi,
            letterSpacing: AppText.heading.fontSize! * AppTracking.title,
          ),
        ),
      ),
    );
  }
}

class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.title, {super.key, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s24,
        AppSpacing.s16,
        AppSpacing.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: AppText.ui.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.semi,
              ),
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              description!,
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// A [SettingsSectionHeader] above an [AppCard] holding its rows, so a
/// section reads as a bordered group rather than rows floating loose on the
/// plain pane background - the flat, undifferentiated look the owner
/// reported on a wide desktop window.
///
/// The header stays outside the card and keeps its own prominent styling
/// (unlike [AppCard.title], which is a small uppercase micro-label meant for
/// a nested panel): a settings section's name is the more important of the
/// two things on screen, and this widget exists only to give what follows it
/// a visible boundary, not to replace it.
///
/// The rows sit inside a [Material] of their own: a [ListTile] (several
/// sections still use one) paints its background and ink splashes on the
/// nearest [Material], and [AppCard]'s own filled, bordered box would
/// otherwise sit between it and the Scaffold's, which is exactly the
/// "background color or ink splashes may be invisible" assertion a tap on
/// one of those rows used to raise.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    super.key,
    required this.title,
    required this.children,
    this.description,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  /// The card's own inner column, not `stretch`: a row widget (`AppListRow`,
  /// `ListTile`, `SettingsSelectRow`) already fills whatever width it is
  /// offered on its own, but non-row content (`MediaCapabilitySection`'s
  /// button, `AvatarSettingsSection`'s centred picture) needs to keep
  /// whichever alignment it had before this widget existed rather than being
  /// stretched into a shape nothing here ever asked for.
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SettingsSectionHeader(title, description: description),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.s8),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: crossAxisAlignment,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      ),
    ],
  );
}
