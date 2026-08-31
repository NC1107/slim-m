// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The rows the member pane is built out of: a group heading, a member, and
/// what an empty result says.
///
/// Split from `member_pane.dart` when the search box pushed it past the
/// review budget. The pane keeps what decides *which* members show; this
/// keeps what decides how one of them draws, and the two change for
/// different reasons.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/member_presence.dart';
import '../providers/member_selection.dart';
import '../providers/presence_controller.dart';
import 'member_profile.dart';
import 'user_avatar.dart';

/// Test-only: how many times each member's row has actually run `build`,
/// keyed by user id. A rendered frame looks the same whether or not a
/// rebuild happened, so a rebuild-scoping test needs this to tell the two
/// apart. Reset with [debugResetMemberRowBuildCounts] between cases.
@visibleForTesting
final Map<String, int> debugMemberRowBuildCounts = {};

/// See [debugMemberRowBuildCounts].
@visibleForTesting
void debugResetMemberRowBuildCounts() => debugMemberRowBuildCounts.clear();

class MemberGroupLabel extends StatelessWidget {
  const MemberGroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      // A heading in its natural case, for the same reason the rail's are.
      child: Semantics(
        container: true,
        header: true,
        label: text,
        child: ExcludeSemantics(
          child: Text(
            text.toUpperCase(),
            style: AppText.label.copyWith(color: tokens.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// How a presence state is spoken, since on screen it is only a dot's colour
/// and silhouette.
///
/// Hidden is deliberately absent: it renders for the one person appearing
/// offline, and naming it aloud beside their own name tells them nothing they
/// did not choose.
String? _presenceDescription(AppPresence status) => switch (status) {
  AppPresence.online => 'online',
  AppPresence.away => 'away',
  AppPresence.dnd => 'do not disturb',
  AppPresence.offline => 'offline',
  AppPresence.hidden => null,
};

/// A row is muted (dimmed, per [AppListRow.muted]) only once fully offline;
/// away and do-not-disturb still read as present, matching the grouping
/// rule the pane applies.
///
/// A right-click reaches the same profile popover a tap already does, rather
/// than a second, narrower menu: every verb this row could offer already
/// lives there, gated exactly as it already is.
///
/// Presence is looked up here rather than passed in, and scoped to this
/// member's own id: `AppMemberPane` no longer watches the raw presence map,
/// so a `PresenceChanged` for someone else never reaches this row's build
/// at all, only the row for whoever actually changed.
class MemberRow extends ConsumerWidget {
  const MemberRow({required this.profile, required this.isSelf, super.key});

  final api.UserProfile profile;

  /// Nothing opens a DM with yourself: `POST /dms/{userId}` has no concept
  /// of one, and a self-conversation would just be a second copy of the
  /// notes only you would ever see.
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugMemberRowBuildCounts[profile.id] =
        (debugMemberRowBuildCounts[profile.id] ?? 0) + 1;
    final status = presenceOf(
      ref.watch(presenceControllerProvider.select((m) => m[profile.id])),
    );
    // The roster snapshot, patched by memberProfileOverridesProvider if a live edit has since landed.
    final displayed =
        ref.watch(
          memberProfileOverridesProvider.select((m) => m[profile.id]),
        ) ??
        profile;
    // Only the first: a row that grew with role count would push the name out of a 236px pane.
    final badge = displayed.roles.isEmpty ? null : displayed.roles.first;

    // While selection is on a row picks rather than opens; the mode replaces the verb.
    final selection = ref.watch(memberSelectionProvider);
    final selectable = selection.active && !isSelf;
    final selected = selection.contains(profile.id);

    void open() => unawaited(
      showMemberProfile(context, ref, profile: displayed, status: status),
    );
    void toggle() =>
        ref.read(memberSelectionProvider.notifier).toggle(profile.id);

    final row = AppListRow(
      // Taller than a channel row: a 26px avatar's corner status dot crops at the default height.
      height: 36,
      label: displayed.displayName,
      // Tucked under the name, with the avatar centred across both lines.
      subtitle: displayed.statusText,
      muted: status == AppPresence.offline,
      // On screen presence is only a dot and an opacity; this is how it is spoken.
      stateDescription: _presenceDescription(status),
      trailing: badge == null
          ? null
          : AppBadge(variant: AppBadgeVariant.role, label: badge),
      leading: UserAvatar(
        userId: profile.id,
        avatarUpdatedAt: displayed.avatarUpdatedAt,
        name: displayed.displayName,
        size: 26,
        status: status,
      ),
      selected: selected,
      // Opens the profile, which is where every verb about a member lives now.
      onTap: selectable
          ? toggle
          : selection.active
          ? null
          : open,
    );

    return GestureDetector(
      onSecondaryTapDown: selection.active ? null : (_) => open(),
      child: row,
    );
  }
}
