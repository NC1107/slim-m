// SPDX-License-Identifier: Apache-2.0
/// One direct-message row in the rail: open on tap, and a right-click or
/// long-press menu to mute it, narrow it to mentions only, or report or
/// block the person on the other end of it.
///
/// Also the in-app half of `docs/IMPLIED-GAPS.md` #2: a call already
/// happening in this DM shows as an icon, and tapping the row while it is
/// lit opens straight into the call pane rather than the plain transcript.
/// Kept current by `dmCallActivityProvider` (`providers/dm_call_activity.dart`)
/// rather than `voiceRosterProvider`'s own per-channel poll: every DM row
/// mounts at once (`DirectMessagesSection` renders the whole list), and one
/// independent 15-second poller per row multiplied with the DM list and
/// burst the write-class rate budget the instant the rail rendered. See that
/// provider's own doc comment for the fix.
///
/// There is deliberately no "close" or "hide this conversation" item here.
/// Nothing backs one: `store/dms.rs` has no concept of leaving or archiving a
/// DM, only `channel_scopes_moderation` and the generic channel routes this
/// row already reaches through Open, and inventing a client-only hide flag
/// for a DM (unlike the personal space's own "Remove from list", which hides
/// a channel that is entirely the caller's own) would silently disagree with
/// every other device signed into the same account. See `personal_space_menu.dart`
/// for the one DM-shaped row that does have a real hide affordance, and why.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/blocks_controller.dart';
import '../providers/channel_notification_overrides_controller.dart';
import '../providers/dm_call_activity.dart';
import '../routing/routes.dart';
import '../screens/dm_call_pane.dart' show dmCallOpenProvider;
import 'context_menu_region.dart';
import 'safety_actions.dart';

/// [channel] is never the caller's own personal space: that DM-shaped row is
/// [PersonalSpaceRow], reached separately, since a self-conversation has no
/// other participant to report or block.
class DmRow extends ConsumerWidget {
  const DmRow({super.key, required this.channel, required this.selected});

  final Channel channel;
  final bool selected;

  /// Read fresh every time the menu opens rather than watched: the row
  /// itself already rebuilds on a live block change, and a menu that is
  /// already open does not need to react to one landing mid-look.
  List<Widget> _menuItems(
    BuildContext context,
    WidgetRef ref,
    VoidCallback close,
  ) {
    final peerId = channel.dmParticipantId;
    final blocked = peerId != null && ref.read(blocksProvider).contains(peerId);
    final container = ProviderScope.containerOf(context, listen: false);
    final currentPreference = ref
        .read(channelNotificationOverridesProvider)
        .overrideFor(channel.id);

    void run(Future<void> Function() action) {
      close();
      unawaited(action());
    }

    void toggleNotifications(api.NotificationPreference preference) {
      final notifier = ref.read(channelNotificationOverridesProvider.notifier);
      run(
        () => currentPreference == preference
            ? notifier.clear(channel.id)
            : preference == api.NotificationPreference.nothing
            ? notifier.mute(channel.id)
            : notifier.mentionsOnly(channel.id),
      );
    }

    return [
      AppMenuItem(
        label: 'Open',
        leading: AppIcons.send,
        onTap: () {
          close();
          context.go(Routes.channel(channel.id));
        },
      ),
      const AppMenuDivider(),
      AppMenuItem(
        label: 'Mute',
        leading: AppIcons.notificationsOff,
        selected: currentPreference == api.NotificationPreference.nothing,
        onTap: () => toggleNotifications(api.NotificationPreference.nothing),
      ),
      AppMenuItem(
        label: 'Mentions only',
        leading: AppIcons.mentions,
        selected: currentPreference == api.NotificationPreference.mentions,
        onTap: () => toggleNotifications(api.NotificationPreference.mentions),
      ),
      if (peerId != null) ...[
        const AppMenuDivider(),
        AppMenuItem(
          label: 'Report user',
          leading: AppIcons.report,
          onTap: () => run(
            () => fileReport(
              context,
              container,
              subject: api.ReportSubject.user,
              subjectId: peerId,
              subjectLabel: 'this member',
            ),
          ),
        ),
        if (blocked)
          AppMenuItem(
            label: 'Unblock',
            leading: AppIcons.restoreAccess,
            onTap: () => run(() => unblockUser(context, container, peerId)),
          )
        else
          AppMenuItem(
            label: 'Block',
            leading: AppIcons.revoke,
            tone: AppMenuItemTone.danger,
            onTap: () => run(() => blockUser(context, container, peerId)),
          ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // Queued, not fetched directly: the controller bounds how many rows become simultaneous requests.
    ref.read(dmCallActivityProvider.notifier).ensureTracked(channel.id);
    final inCall = ref.watch(
      dmCallActivityProvider.select((m) => m[channel.id] ?? false),
    );
    // A live call outranks the mute glyph in this one slot; unread still counts either way.
    final muted = ref.watch(
      channelNotificationOverridesProvider.select((s) => s.isMuted(channel.id)),
    );
    return ContextMenuRegion(
      itemsBuilder: (menuContext, close) => _menuItems(menuContext, ref, close),
      // AppListRow is already its own tab stop; see ContextMenuFocus.ownsFocusNode.
      ownsFocusNode: false,
      child: AppListRow(
        label: channel.name,
        selected: selected,
        unread: channel.cursor > channel.lastReadSeq,
        muted: muted,
        leading: AppAvatar(name: channel.name, size: 20),
        trailing: inCall
            ? Icon(
                AppIcons.startCall,
                size: AppSizes.icon16,
                color: tokens.accent,
              )
            : muted
            ? Icon(
                AppIcons.notificationsOff,
                size: AppSizes.icon16,
                color: tokens.textSecondary,
              )
            : null,
        stateDescription: inCall ? 'call in progress' : null,
        onTap: () {
          // Opens straight into the call pane, the same double action RailCallSummary uses.
          if (inCall) ref.read(dmCallOpenProvider.notifier).state = channel.id;
          context.go(Routes.channel(channel.id));
        },
      ),
    );
  }
}
