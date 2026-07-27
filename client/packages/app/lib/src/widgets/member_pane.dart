// SPDX-License-Identifier: Apache-2.0
/// The right-hand member pane: the deployment's roster.
///
/// Presence is real now: [_presenceSeedProvider] batch-fetches status for the
/// resolved member list and [presenceControllerProvider] keeps it current
/// from live `presence.changed` events, so [groupMembersByPresence] (a real,
/// tested grouping function; see member_pane_test.dart) is finally called
/// with a real status map instead of an empty one.
///
/// A member's first role becomes a badge. `@everyone` is excluded server-side,
/// so an empty list means no badge rather than no data. There is still no
/// in-voice flag on a profile, so the design's speaker glyph is left off.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/dms.dart';
import '../providers/presence_controller.dart';
import '../providers/providers.dart';
import '../routing/routes.dart';
import 'user_avatar.dart';

/// The deployment's members. Real endpoint, real data.
final membersProvider = FutureProvider.autoDispose<List<api.UserProfile>>(
  (ref) => ref.watch(apiProvider).listMembers(),
);

/// Seeds live presence for the resolved member list. A trigger, not a data
/// source in its own right: [AppMemberPane] watches this purely to start it,
/// and reads the actual statuses back from [presenceControllerProvider].
/// `autoDispose` and depending on the (also `autoDispose`) [membersProvider]
/// keeps this from outliving the pane, unlike [presenceControllerProvider]
/// itself, which is worth keeping warm for the rest of the session.
final _presenceSeedProvider = FutureProvider.autoDispose<void>((ref) async {
  final members = await ref.watch(membersProvider.future);
  await ref
      .read(presenceControllerProvider.notifier)
      .refresh(members.map((m) => m.id));
});

/// Whether the member pane is shown at expanded width. Defaults open; the
/// channel header's members toggle flips it. [HomeShell] also gates this on
/// layout, since the toggle can only hide the pane, not summon room for it
/// that is not there.
final memberPaneVisibleProvider = StateProvider<bool>((ref) => true);

/// The design-system status a server [api.PresenceState] renders as. Both
/// [PresenceState.away] and [PresenceState.dnd] still group under "online"
/// below (see [groupMembersByPresence]): each is reachable in some capacity,
/// which is the distinction that bucket exists to draw, and the row itself
/// still shows the more specific dot shape/colour.
AppPresence _presenceOf(api.PresenceState? state) => switch (state) {
      api.PresenceState.online => AppPresence.online,
      api.PresenceState.away => AppPresence.away,
      api.PresenceState.dnd => AppPresence.dnd,
      api.PresenceState.offline || null => AppPresence.offline,
    };

/// Splits and sorts [members] by presence. A member absent from [statusOf]
/// counts as offline, which is the only honest default when presence is
/// unknown rather than assumed online. Away and do-not-disturb both count as
/// "online" for grouping purposes: both are a live, connected session, just
/// with a status layered on top, and grouping either under "Offline" would
/// read as a lie the row's own presence dot then has to contradict.
({List<api.UserProfile> online, List<api.UserProfile> offline})
    groupMembersByPresence(
  List<api.UserProfile> members,
  Map<String, AppPresence> statusOf,
) {
  final online = <api.UserProfile>[];
  final offline = <api.UserProfile>[];
  for (final member in members) {
    final status = statusOf[member.id];
    final isOnlineGroup = status == AppPresence.online ||
        status == AppPresence.away ||
        status == AppPresence.dnd;
    (isOnlineGroup ? online : offline).add(member);
  }
  int byName(api.UserProfile a, api.UserProfile b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  online.sort(byName);
  offline.sort(byName);
  return (online: online, offline: offline);
}

/// 236px, `--surface-sunken`, a left hairline: the design's right member pane.
class AppMemberPane extends ConsumerWidget {
  const AppMemberPane({super.key});

  static const double width = 236;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final membersAsync = ref.watch(membersProvider);
    // Purely to start the seed fetch; the actual statuses come back through
    // presenceControllerProvider below, watched per row.
    ref.watch(_presenceSeedProvider);
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
                child:
                    Center(child: CircularProgressIndicator(strokeWidth: 2))),
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
                      // A 403 means a lost permission, not a fault: the
                      // same request would only fail again.
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
              entry.key: _presenceOf(entry.value),
          };
          final grouped = groupMembersByPresence(members, statusOf);
          return Column(
            children: [
              _Header(count: members.length),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8, vertical: AppSpacing.s8),
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
      child: Text(text.toUpperCase(),
          style: AppText.label.copyWith(color: tokens.textSecondary)),
    );
  }
}

/// A row is muted (dimmed, per [AppListRow.muted]) only once fully offline;
/// away and do-not-disturb still read as present, matching the grouping
/// rule above.
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
    // Only the first: the design gives a member one badge, and a row that
    // grows with role count would push the name out of a 236px pane.
    final badge = profile.roles.isEmpty ? null : profile.roles.first;

    return AppListRow(
      // Taller than a channel row: the design pairs a 26px avatar with a
      // status dot hanging off its corner, which crops at the default height.
      height: 36,
      label: profile.displayName,
      muted: status == AppPresence.offline,
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
      onTap: isSelf
          ? null
          : () async {
              final channelId = await openDirectMessage(ref, profile.id);
              if (context.mounted) context.go(Routes.channel(channelId));
            },
    );
  }
}
