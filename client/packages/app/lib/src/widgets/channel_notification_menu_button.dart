// SPDX-License-Identifier: Apache-2.0
/// The channel header's own route to muting a channel, or narrowing it to
/// mentions only, without leaving the conversation to find a settings
/// screen.
///
/// The rail row's long-press/right-click menu (`_channelMenuItems` in
/// `channel_rail_channel_rows.dart`) offers the identical two toggles; this
/// is the header's, since a phone at compact width shows no rail row to
/// right-click, and `SpaceMenuButton`'s own overlay/portal shape is the
/// template both follow.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/channel_notification_overrides_controller.dart';
import 'animated_menu_portal.dart';
import 'context_menu_focus.dart';

class ChannelNotificationMenuButton extends ConsumerStatefulWidget {
  const ChannelNotificationMenuButton({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<ChannelNotificationMenuButton> createState() =>
      _ChannelNotificationMenuButtonState();
}

class _ChannelNotificationMenuButtonState
    extends ConsumerState<ChannelNotificationMenuButton> {
  final _controller = AnimatedMenuController();
  final _link = LayerLink();

  /// Tapping the already-selected toggle clears the override rather than
  /// re-setting it: that is this menu's only "back to the account default"
  /// affordance, so a mute or mentions-only choice is always one tap to undo.
  void _toggle(
    api.NotificationPreference preference,
    api.NotificationPreference? current,
  ) {
    _controller.hide();
    final notifier = ref.read(channelNotificationOverridesProvider.notifier);
    if (current == preference) {
      unawaited(notifier.clear(widget.channelId));
    } else if (preference == api.NotificationPreference.nothing) {
      unawaited(notifier.mute(widget.channelId));
    } else {
      unawaited(notifier.mentionsOnly(widget.channelId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(
      channelNotificationOverridesProvider.select(
        (s) => s.overrideFor(widget.channelId),
      ),
    );
    final muted = current == api.NotificationPreference.nothing;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller.portal,
        // Positioned so the follower sizes to its content, not the whole screen a Column would otherwise fill it against.
        overlayChildBuilder: (context) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            child: AnimatedMenuSurface(
              controller: _controller,
              alignment: Alignment.topRight,
              child: TapRegion(
                onTapOutside: (_) => _controller.hide(),
                // Escape closes it and Tab reaches every item once open.
                child: ContextMenuKeyboardScope(
                  onDismiss: _controller.hide,
                  child: AppMenu(
                    width: 220,
                    children: [
                      AppMenuItem(
                        label: 'Mute channel',
                        leading: AppIcons.notificationsOff,
                        selected: muted,
                        onTap: () => _toggle(
                          api.NotificationPreference.nothing,
                          current,
                        ),
                      ),
                      AppMenuItem(
                        label: 'Mentions only',
                        leading: AppIcons.mentions,
                        selected:
                            current == api.NotificationPreference.mentions,
                        onTap: () => _toggle(
                          api.NotificationPreference.mentions,
                          current,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        child: AppIconButton(
          icon: muted ? AppIcons.notificationsOff : AppIcons.notificationsOn,
          semanticLabel: muted
              ? 'Channel notifications, muted'
              : current == api.NotificationPreference.mentions
              ? 'Channel notifications, mentions only'
              : 'Channel notifications',
          tooltip: 'Notifications',
          active: current != null,
          onPressed: _controller.toggle,
        ),
      ),
    );
  }
}
