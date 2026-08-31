// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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
///
/// This pane watches presence only through `reachablePresenceKey`, a
/// selector over the reachable id set rather than the raw map, so a member's
/// dot changing colour within the same Online/Offline section never
/// rebuilds the pane; only someone crossing sections does. Each `MemberRow`
/// separately watches its own id for the dot itself, which is what actually
/// keeps a single dot change from rebuilding every row.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../permissions.dart';
import '../providers/admin_providers.dart';
import '../providers/member_presence.dart';
import '../providers/member_selection.dart';
import '../providers/presence_controller.dart';
import '../providers/providers.dart';
import 'member_bulk_actions.dart';
import 'member_pane_rows.dart';
import 'member_selection_bar.dart';

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
    // Scoped watch: see the class doc comment above for why.
    ref.watch(presenceControllerProvider.select(reachablePresenceKey));
    final myId = ref.watch(meProvider).valueOrNull?.id;
    final mine = ref.watch(myPermissionsProvider);
    final canTimeOut = mine.hasPermission(Perm.kickMembers);
    final canRemove = mine.hasPermission(Perm.banMembers);
    final selecting = ref.watch(memberSelectionProvider).active;
    // A bit revoked mid-selection leaves a mode with no verb left in it.
    ref.listen(myPermissionsProvider, (_, next) {
      final stillAllowed =
          next.hasPermission(Perm.kickMembers) ||
          next.hasPermission(Perm.banMembers);
      if (!stillAllowed) ref.read(memberSelectionProvider.notifier).clear();
    });

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        border: Border(left: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Column(
        children: [
          _Header(
            count: membersAsync.valueOrNull?.length,
            // Only a moderator is offered the mode; the server refuses the rest anyway.
            onStartSelecting: (canTimeOut || canRemove) && !selecting
                ? ref.read(memberSelectionProvider.notifier).enter
                : null,
          ),
          Expanded(
            child: membersAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (error, _) => Center(
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
              data: (members) {
                // A read, not a watch: this build already reruns on the scoped watch above.
                final presence = ref.read(presenceControllerProvider);
                final statusOf = {
                  for (final entry in presence.entries)
                    entry.key: presenceOf(entry.value),
                };
                final grouped = groupMembersByPresence(members, statusOf);
                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: AppSpacing.s8,
                  ),
                  children: [
                    if (grouped.online.isNotEmpty) ...[
                      MemberGroupLabel('Online · ${grouped.online.length}'),
                      for (final m in grouped.online)
                        MemberRow(profile: m, isSelf: m.id == myId),
                    ],
                    if (grouped.offline.isNotEmpty) ...[
                      MemberGroupLabel('Offline · ${grouped.offline.length}'),
                      for (final m in grouped.offline)
                        MemberRow(profile: m, isSelf: m.id == myId),
                    ],
                  ],
                );
              },
            ),
          ),
          // Outside the async branches on purpose: a roster refetch that fails
          // mid-selection must not take the only way out of the mode with it.
          if (selecting)
            MemberSelectionBar(
              canTimeOut: canTimeOut,
              canRemove: canRemove,
              onTimeOut: (duration) =>
                  unawaited(timeOutSelectedMembers(ref, context, duration)),
              onRemove: () => confirmAndRemoveSelectedMembers(ref, context),
            ),
        ],
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
  const _Header({required this.count, this.onStartSelecting});

  final int? count;

  /// Enters selection mode. Null when the viewer holds neither moderation
  /// bit, or when the mode is already running.
  final VoidCallback? onStartSelecting;

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
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == null ? 'MEMBERS' : 'MEMBERS · $count',
              style: AppText.label.copyWith(color: tokens.textSecondary),
            ),
          ),
          if (onStartSelecting != null)
            AppIconButton(
              icon: AppIcons.shield,
              semanticLabel: 'Select members to moderate',
              onPressed: onStartSelecting,
            ),
        ],
      ),
    );
  }
}
