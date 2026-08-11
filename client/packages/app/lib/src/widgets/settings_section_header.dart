// SPDX-License-Identifier: Apache-2.0
/// The container vocabulary every settings and administration screen is built
/// from: a group header naming who a run of sections belongs to, the section
/// header each one opens with, and [SettingsSectionCard], which is *the* way
/// this app expresses "a group of related settings".
///
/// See [docs/decisions/0013-settings-container-system.md] for the survey that
/// made this the single idiom and the six competing ones it replaced. The
/// short version: a screen in this area is a stack of [SettingsSectionCard]s
/// and nothing else is a container, so a reader crossing from personal
/// settings to a moderation screen meets one rhythm rather than six.
///
/// **Horizontal inset is owned by the screen frame, never by a section.**
/// [SettingsScreenScaffold] and [SettingsPanesScaffold]'s own pane body each
/// pad by [AppSpacing.s16] already, and this file used to add another
/// [AppSpacing.s16] on top - so personal and Space settings sat at 32 while
/// every admin screen sat at 16 and the debug log sat at 0. Three insets on
/// sibling screens is exactly the incoherence this vocabulary exists to
/// close, and one owner for the inset is what keeps it closed.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// `SettingsGroupHeader` used to live here, a step up the type scale from
/// [SettingsSectionHeader], for naming a run of sections rather than one.
/// Its last caller was `AppInfoSection`, which used it *instead of* a
/// container rather than above several - the one personal-settings section
/// with no bordered box at all. That section is a [SettingsSectionCard] now
/// like every other, which left this with no callers, so it is deleted rather
/// than kept as a second header level nothing reaches. A future screen that
/// genuinely needs to name a run of sections should bring it back
/// deliberately rather than inherit it as dead code.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.title, {super.key, this.description});

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.s24,
        bottom: AppSpacing.s8,
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
    this.title,
    required this.children,
    this.description,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  /// Null for a screen whose entire body is this one group, where a header
  /// would only restate the app bar title above it.
  ///
  /// The header exists to tell several groups apart, so on a screen with one
  /// group it is a hairline and 24dp of space carrying no information -
  /// "Roles" under a screen titled "Roles". Applying "a screen body is a
  /// stack of section cards" literally produced exactly that on four screens
  /// before this was nullable, which is worth recording: a vocabulary rule
  /// still needs the judgement about when a slot has nothing to say.
  ///
  /// A single-group screen that *can* say something useful should still pass
  /// a title, or a [description]: "Invites" beside a "New invite" form earns
  /// its header because there are two groups to separate.
  final String? title;
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
  Widget build(BuildContext context) {
    // A description with no title had nowhere to render and no test caught it; this catches it instead.
    assert(
      title != null || description == null,
      'SettingsSectionCard.description needs a title to render under',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          SettingsSectionHeader(title!, description: description),
        AppCard(
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
      ],
    );
  }
}
