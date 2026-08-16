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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/member_presence.dart';
import '../providers/member_search.dart';
import '../providers/presence_controller.dart';
import '../providers/providers.dart';
import 'member_pane_rows.dart';
import 'member_pane_search.dart';

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
          final matching = membersMatching(
            members,
            ref.watch(memberQueryProvider),
          );
          final byJoined = ref.watch(memberSortProvider) == MemberSort.joined;
          final grouped = groupMembersByPresence(matching, statusOf);
          return Column(
            children: [
              // The whole roster, never the filtered view; see _Header.
              _Header(count: members.length),
              const MemberPaneSearch(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: AppSpacing.s8,
                  ),
                  children: [
                    if (matching.isEmpty)
                      MemberEmptyResult(query: ref.watch(memberQueryProvider)),
                    if (byJoined) ...[
                      MemberGroupLabel('Recently joined · ${matching.length}'),
                      for (final m in membersByJoinedNewestFirst(matching))
                        MemberRow(
                          profile: m,
                          status: statusOf[m.id] ?? AppPresence.offline,
                          isSelf: m.id == myId,
                        ),
                    ] else if (grouped.online.isNotEmpty) ...[
                      MemberGroupLabel('Online · ${grouped.online.length}'),
                      for (final m in grouped.online)
                        MemberRow(
                          profile: m,
                          status: statusOf[m.id] ?? AppPresence.offline,
                          isSelf: m.id == myId,
                        ),
                    ],
                    if (!byJoined && grouped.offline.isNotEmpty) ...[
                      MemberGroupLabel('Offline · ${grouped.offline.length}'),
                      for (final m in grouped.offline)
                        MemberRow(
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

/// The pane's own title bar, counting the whole roster.
///
/// Never the filtered count: this pane is where somebody checks how big the
/// Space is, and a search box quietly changing that number would answer a
/// question nobody asked.
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
