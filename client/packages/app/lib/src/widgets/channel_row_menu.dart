// SPDX-License-Identifier: Apache-2.0
/// The one menu a channel row offers, reached three ways: a right-click or
/// long-press on the row (`ContextMenuRegion`, wired in
/// `channel_rail_channel_rows.dart`), and the row's own kebab, which used to
/// open a separate "manage" sheet directly instead of this menu - the
/// "outdated code" backlog item 135 named. The kebab now opens this same
/// [ContextMenuRegion] programmatically (see `ContextMenuRegionState.open`)
/// rather than keeping a second, divergent affordance.
///
/// "Manage channel..." (rename, topic, delete) and "Channel permissions..."
/// used to be two separate entries into two disconnected surfaces; they are
/// now one "Channel settings..." entry into one screen
/// (`channel_settings_screen.dart`) that gates its own sections on the same
/// two bits this menu used to gate the two entries on.
///
/// Split out of `channel_rail_channel_rows.dart` to keep that file inside
/// the review budget once it also carried the kebab's own `GlobalKey` wiring.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../permissions.dart';
import '../providers/channel_notification_overrides_controller.dart';
import '../providers/providers.dart';
import '../routing/routes.dart';
import '../screens/channel_settings_screen.dart';
import 'channel_rail.dart' show selectedChannelId;

/// Opening it always, muting it or narrowing it to mentions only (the same
/// two toggles the header used to duplicate until 2026-08-13, tapping the
/// active one clears back to the account default), and "Channel
/// settings..." for a caller who holds [canManage], the deployment-wide
/// MANAGE_ROLES bit, or both - the settings screen itself decides which
/// sections a holder of only one of the two actually sees.
///
/// Read fresh every time the menu opens rather than watched, the same choice
/// `DmRow._menuItems`'s own doc comment makes: the row itself already
/// rebuilds on a live mute change, and a menu that is already open does not
/// need to react to one landing mid-look.
List<Widget> channelRowMenuItems(
  BuildContext context,
  VoidCallback close,
  Channel channel,
  bool canManage,
) {
  final container = ProviderScope.containerOf(context, listen: false);
  final current = container
      .read(channelNotificationOverridesProvider)
      .overrideFor(channel.id);
  // Coarse deployment-wide gate like the channel-manage one; the overwrite screen re-checks this channel's own MANAGE_ROLES on open.
  final canManageRoles =
      container
          .read(meProvider)
          .valueOrNull
          ?.permissions
          .hasPermission(Perm.manageRoles) ??
      false;

  void toggle(api.NotificationPreference preference) {
    close();
    final notifier = container.read(
      channelNotificationOverridesProvider.notifier,
    );
    unawaited(
      current == preference
          ? notifier.clear(channel.id)
          : preference == api.NotificationPreference.nothing
          ? notifier.mute(channel.id)
          : notifier.mentionsOnly(channel.id),
    );
  }

  return [
    AppMenuItem(
      label: 'Open channel',
      leading: AppIcons.hash,
      onTap: () {
        close();
        context.go(Routes.channel(channel.id));
      },
    ),
    const AppMenuDivider(),
    AppMenuItem(
      label: 'Mute channel',
      leading: AppIcons.notificationsOff,
      selected: current == api.NotificationPreference.nothing,
      onTap: () => toggle(api.NotificationPreference.nothing),
    ),
    AppMenuItem(
      label: 'Mentions only',
      leading: AppIcons.mentions,
      selected: current == api.NotificationPreference.mentions,
      onTap: () => toggle(api.NotificationPreference.mentions),
    ),
    if (canManage || canManageRoles) ...[
      const AppMenuDivider(),
      AppMenuItem(
        label: 'Channel settings...',
        leading: AppIcons.settings,
        onTap: () {
          // Captured before push() moves the router's own location; see ChannelSettingsRouteArgs.
          final wasOpen = selectedChannelId(context) == channel.id;
          close();
          context.push(
            Routes.channelSettings,
            extra: ChannelSettingsRouteArgs(channel: channel, wasOpen: wasOpen),
          );
        },
      ),
    ],
  ];
}
