// SPDX-License-Identifier: Apache-2.0
/// One direct-message row in the rail: open on tap, and a right-click or
/// long-press menu to report or block the person on the other end of it.
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
import '../routing/routes.dart';
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

    void run(Future<void> Function() action) {
      close();
      unawaited(action());
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
            leading: AppIcons.revoke,
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
    return ContextMenuRegion(
      itemsBuilder: (menuContext, close) => _menuItems(menuContext, ref, close),
      // AppListRow is already its own tab stop; see ContextMenuFocus.ownsFocusNode.
      ownsFocusNode: false,
      child: AppListRow(
        label: channel.name,
        selected: selected,
        unread: channel.cursor > channel.lastReadSeq,
        leading: AppAvatar(name: channel.name, size: 20),
        onTap: () => context.go(Routes.channel(channel.id)),
      ),
    );
  }
}
