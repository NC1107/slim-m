// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The personal settings sections about how this device behaves: push
/// notification status and a link to the voice preferences screen.
///
/// Presence used to live here too. It moved out rather than being duplicated:
/// the rail footer's own status menu already sets both the visibility and the
/// status text, right where a person looks to change them.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart'
    show LocalAlertChannel, isAndroidHost, isLinuxHost;

import '../providers/notification_sound_settings.dart';
import '../providers/push_controller.dart';
import '../providers/toasts.dart';
import 'notification_settings_rows.dart';
import 'settings_section_header.dart';
import 'settings_toggle_row.dart';

/// Whether this device is registered for push, read plainly off the state
/// [PushController] tracks: this is what makes a registration problem
/// diagnosable from the device itself, instead of guessing from server logs.
class NotificationsSection extends ConsumerWidget {
  const NotificationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(pushControllerProvider);
    final soundsEnabled = ref.watch(messageSoundSettingsProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final registered = status == PushStatus.registered;
    final blocked = status == PushStatus.registeredNotificationsBlocked;

    return SettingsSectionCard(
      children: [
        AppListRow(
          leading: Icon(
            registered ? AppIcons.notificationsOn : AppIcons.notificationsOff,
            color: registered
                ? tokens.accent
                : blocked
                ? tokens.dangerText
                : tokens.textSecondary,
          ),
          label: status.label,
        ),
        SettingsToggleRow(
          label: 'Play a sound for messages, mentions and errors',
          value: soundsEnabled,
          onChanged: (value) =>
              ref.read(messageSoundSettingsProvider.notifier).setEnabled(value),
          semanticLabel: 'Play a sound for messages, mentions and errors',
        ),
        const PushContentPreviewRow(),
        const NotificationPreferenceRow(),
        const QuietHoursRow(),
        // Only where a local notification actually displays (Android, Linux desktop); a pipe test via the same LocalNotifications.show path a real alert uses.
        if (isAndroidHost || isLinuxHost) const _TestNotificationRow(),
      ],
    );
  }
}

/// A button that posts a local notification straight away, so someone can
/// confirm slim-m's notifications reach their OS - most useful on the Linux
/// desktop, where there is no remote push to fall back on and a silent
/// failure is otherwise invisible.
class _TestNotificationRow extends ConsumerWidget {
  const _TestNotificationRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return AppListRow(
      leading: Icon(AppIcons.notificationsOn, color: tokens.textSecondary),
      label: 'Send a test notification',
      onTap: () {
        unawaited(
          ref
              .read(localNotificationsProvider)
              .show(
                'Test notification - if you can see this, slim-m can reach '
                'your notifications.',
                channel: LocalAlertChannel.messages,
              ),
        );
        ref.read(toastsProvider.notifier).show('Test notification sent.');
      },
    );
  }
}

/// Voice call preferences: microphone, screen share quality, and sounds.
/// A separate screen rather than inline rows, matching how much is on it.
