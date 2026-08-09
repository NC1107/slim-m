// SPDX-License-Identifier: Apache-2.0
/// The right-hand member pane: the deployment's roster.
///
/// Presence is real now: `presenceSeedProvider` (in `member_presence.dart`,
/// where the roster and presence data this pane renders all live now)
/// batch-fetches status for the resolved member list and
/// [presenceControllerProvider] keeps it current from live
/// `presence.changed` events, so `groupMembersByPresence` is finally called
/// with a real status map instead of an empty one.
///
/// A member's first role becomes a badge. `@everyone` is excluded server-side,
/// so an empty list means no badge rather than no data. There is still no
/// in-voice flag on a profile, so the design's speaker glyph is left off.
///
/// `membersProvider` is deliberately deployment-wide, never filtered to who
/// can see whichever channel is open (`GET /members`'s own doc comment: any
/// authenticated caller may read it, since the list is not scoped to one
/// channel). Nothing here is a new information leak - the same roster is
/// already readable directly by any authenticated caller - but it means this
/// pane must never be offered for a DM, whose two participants are never
/// this list; `home_shell.dart`'s `_MemberPaneSlot` and
/// `channel_header.dart`'s `ChannelHeader.isDm` are what withhold it there.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/member_presence.dart';
import '../providers/presence_controller.dart';
import '../providers/providers.dart';
import 'member_profile.dart';
import 'user_avatar.dart';

/// Whether the member pane is shown, wherever it fits. Defaults open; the
/// channel header's members toggle flips it. [HomeShell] also gates this on
/// `LayoutClass.fitsMemberPane`, since the toggle can only hide the pane, not
/// summon room for it that is not there.
final memberPaneVisibleProvider = StateProvider<bool>((ref) => true);

/// 236px, `--surface-sunken`, a left hairline: the design's right member pane.
class AppMemberPane extends ConsumerWidget {
  const AppMemberPane({super.key});

  static const double width = 236;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final membersAsync = ref.watch(membersProvider);
    // Purely to start the seed fetch; statuses come back through presenceControllerProvider below.
    ref.watch(presenceSeedProvider);
    // Purely a side-effect subscription: no value of its own, only a possible invalidate on membersProvider.
    ref.watch(memberRosterKeepAliveProvider);
    // Same shape: a timeout or a removal makes a row on screen wrong.
    ref.watch(memberModerationWatcherProvider);
    final presence = ref.watch(presenceControllerProvider);
    final myId = ref.watch(meProvider).valueOrNull?.id;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        border: Border(left: BorderSide(color: tokens.borderSubtle)),
      ),
      child: membersAsync.when(
        loading: () => Column(
          children: [
            const _Header(count: null),
            const Expanded(
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ],
        ),
        error: (error, _) => Column(
          children: [
            const _Header(count: null),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Could not load members.',
                        style: TextStyle(color: tokens.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      // A 403 means a lost permission, not a fault: retrying would only fail the same way.
                      if (error is! api.ForbiddenException) ...[
                        const SizedBox(height: AppSpacing.s12),
                        TextButton(
                          onPressed: () => ref.invalidate(membersProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        data: (members) {
          final statusOf = {
            for (final entry in presence.entries)
              entry.key: presenceOf(entry.value),
          };
          final grouped = groupMembersByPresence(members, statusOf);
          return Column(
            children: [
              _Header(count: members.length),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: AppSpacing.s8,
                  ),
                  children: [
                    if (grouped.online.isNotEmpty) ...[
                      _GroupLabel('Online · ${grouped.online.length}'),
                      for (final m in grouped.online)
                        _MemberRow(
                          profile: m,
                          status: statusOf[m.id] ?? AppPresence.offline,
                          isSelf: m.id == myId,
                        ),
                    ],
                    if (grouped.offline.isNotEmpty) ...[
                      _GroupLabel('Offline · ${grouped.offline.length}'),
                      for (final m in grouped.offline)
                        _MemberRow(
                          profile: m,
                          status: statusOf[m.id] ?? AppPresence.offline,
                          isSelf: m.id == myId,
                        ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Text(
        count == null ? 'MEMBERS' : 'MEMBERS · $count',
        style: AppText.label.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

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
/// rule above.
///
/// A right-click reaches the same profile popover a tap already does, rather
/// than a second, narrower menu: every verb this row could offer already
/// lives there, gated exactly as it already is.
class _MemberRow extends ConsumerWidget {
  const _MemberRow({
    required this.profile,
    required this.status,
    required this.isSelf,
  });

  final api.UserProfile profile;
  final AppPresence status;

  /// Nothing opens a DM with yourself: `POST /dms/{userId}` has no concept
  /// of one, and a self-conversation would just be a second copy of the
  /// notes only you would ever see.
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the first: a row that grew with role count would push the name out of a 236px pane.
    final badge = profile.roles.isEmpty ? null : profile.roles.first;

    void open() => unawaited(
      showMemberProfile(context, ref, profile: profile, status: status),
    );

    final row = AppListRow(
      // Taller than a channel row: a 26px avatar's corner status dot crops at the default height.
      height: 36,
      label: profile.displayName,
      muted: status == AppPresence.offline,
      // Presence is a dot and an opacity on screen, and was reaching a screen
      // reader as the word "muted" or as nothing at all.
      stateDescription: _presenceDescription(status),
      trailing: badge == null
          ? null
          : AppBadge(variant: AppBadgeVariant.role, label: badge),
      leading: UserAvatar(
        userId: profile.id,
        avatarUpdatedAt: profile.avatarUpdatedAt,
        name: profile.displayName,
        size: 26,
        status: status,
      ),
      // Opens the profile, which is where every verb about a member lives now.
      onTap: open,
    );
    return GestureDetector(onSecondaryTapDown: (_) => open(), child: row);
  }
}
