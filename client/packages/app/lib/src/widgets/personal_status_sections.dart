// SPDX-License-Identifier: Apache-2.0
/// Three personal settings sections about how the account presents itself
/// live: presence visibility, push notification status, and a link to the
/// voice preferences screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/presence_controller.dart';
import '../providers/providers.dart';
import '../providers/push_controller.dart';
import '../routing/routes.dart';
import 'settings_section_header.dart';
import 'settings_select_row.dart';

/// Sets the caller's own visibility preference via `PATCH /presence`. See
/// [presenceVisibilityDisplayProvider] for why the selected segment is a
/// local echo of the last choice rather than a value read back from the
/// server: there is no endpoint that returns it.
class PresenceSection extends ConsumerWidget {
  const PresenceSection({super.key});

  static const _options = [
    (api.PresenceVisibility.online, 'Online'),
    (api.PresenceVisibility.away, 'Away'),
    (api.PresenceVisibility.dnd, 'Do not disturb'),
    (api.PresenceVisibility.hidden, 'Appear offline'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(presenceVisibilityDisplayProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('Presence'),
        SettingsSelectRow<api.PresenceVisibility>(
          label: 'Status',
          sheetTitle: 'Presence',
          value: selected ?? _options.first.$1,
          choices: [
            for (final option in _options)
              SettingsChoice(value: option.$1, label: option.$2),
          ],
          onChanged: (visibility) async {
            ref.read(presenceVisibilityDisplayProvider.notifier).state =
                visibility;
            try {
              await ref.read(apiProvider).setPresenceVisibility(visibility);
            } on api.ApiException catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Could not update presence. ${e.message}'),
                ),
              );
            }
          },
        ),
      ],
    );
  }
}

/// Whether this device is registered for push, read plainly off the state
/// [PushController] tracks: this is what makes a registration problem
/// diagnosable from the device itself, instead of guessing from server logs.
class NotificationsSection extends ConsumerWidget {
  const NotificationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(pushControllerProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final registered = status == PushStatus.registered;
    final blocked = status == PushStatus.registeredNotificationsBlocked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('Notifications'),
        ListTile(
          leading: Icon(
            registered ? AppIcons.notificationsOn : AppIcons.notificationsOff,
            color: registered
                ? tokens.accent
                : blocked
                ? tokens.dangerText
                : tokens.textSecondary,
          ),
          title: Text(status.label),
        ),
      ],
    );
  }
}

/// Voice call preferences: microphone, screen share quality, and sounds.
/// A separate screen rather than inline rows, matching how much is on it.
class VoiceSection extends StatelessWidget {
  const VoiceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('Voice'),
        ListTile(
          leading: const Icon(AppIcons.mic),
          title: const Text('Microphone, screen share, sounds'),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: () => context.push(Routes.voiceSettings),
        ),
      ],
    );
  }
}
