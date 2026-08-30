// SPDX-License-Identifier: Apache-2.0
/// Three personal settings sections about how the account presents itself
/// live: presence visibility, push notification status, and a link to the
/// voice preferences screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/notification_sound_settings.dart';
import '../providers/presence_controller.dart';
import '../providers/push_controller.dart';
import 'notification_settings_rows.dart';
import 'presence_menu.dart' show applyPresenceVisibility, presenceOptions;
import 'run_guarded.dart';
import 'settings_section_header.dart';
import 'settings_select_row.dart';
import 'settings_toggle_row.dart';
import 'status_text_row.dart';

/// Sets the caller's own visibility preference via `PATCH /presence`. See
/// [presenceVisibilityDisplayProvider] for why the selected segment is a
/// local echo of the last choice rather than a value read back from the
/// server: there is no endpoint that returns it, so a null [selected] is
/// rendered as its own "Not set" rather than asserting one of the choices.
/// "Not set" over the row's default "Unknown", which read as an error value
/// against the online/away/dnd/offline vocabulary on a fresh account (UX6).
class PresenceSection extends ConsumerStatefulWidget {
  const PresenceSection({super.key});

  @override
  ConsumerState<PresenceSection> createState() => _PresenceSectionState();
}

class _PresenceSectionState extends ConsumerState<PresenceSection>
    with GuardedActionState<PresenceSection> {
  Future<void> _set(api.PresenceVisibility visibility) =>
      applyPresenceVisibility(ref, visibility, guard: guard);

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(presenceVisibilityDisplayProvider);

    return SettingsSectionCard(
      title: 'Presence',
      children: [
        SettingsSelectRow<api.PresenceVisibility>(
          label: 'Status',
          sheetTitle: 'Presence',
          value: selected,
          unknownLabel: 'Not set',
          choices: [
            for (final (visibility, label, _) in presenceOptions)
              SettingsChoice(value: visibility, label: label),
          ],
          onChanged: _set,
        ),
        const StatusTextRow(),
        if (actionError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s8,
              0,
              AppSpacing.s8,
              AppSpacing.s8,
            ),
            child: AppErrorState(
              message: actionError!,
              onDismiss: clearActionError,
            ),
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
      ],
    );
  }
}

/// Voice call preferences: microphone, screen share quality, and sounds.
/// A separate screen rather than inline rows, matching how much is on it.
