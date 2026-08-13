// SPDX-License-Identifier: Apache-2.0
/// Three personal settings sections about how the account presents itself
/// live: presence visibility, push notification status, and a link to the
/// voice preferences screen.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/notification_preference_controller.dart';
import '../providers/notification_sound_settings.dart';
import '../providers/presence_controller.dart';
import '../providers/providers.dart';
import '../providers/push_content_preview_settings.dart';
import '../providers/push_controller.dart';
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
/// rendered as its own "Unknown" rather than asserting one of the choices.
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
      title: 'Notifications',
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
        const _PushContentPreviewRow(),
        const _NotificationPreferenceRow(),
      ],
    );
  }
}

/// The "show message text on the lock screen" toggle.
///
/// Reachable only on iOS: that is the one platform with a Notification
/// Service Extension able to decrypt the preview this asks the server to
/// seal (`push/http/push.rs`'s own doc comment on `include_content`; see
/// `ios/NotificationServiceExtension`). Asking for it on Android would carry
/// a bigger envelope with nothing on that device able to open it - harmless,
/// since the relay still cannot read it either way, but pointless, so the
/// row is gated rather than offering a choice that changes nothing. Kept
/// discoverable in source rather than merely absent: this doc comment is the
/// record of why, the same treatment `pasteKeystrokeReadsClipboardImage`
/// gives its own iOS exclusion.
class _PushContentPreviewRow extends ConsumerWidget {
  const _PushContentPreviewRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }
    final enabled = ref.watch(pushContentPreviewSettingsProvider);

    return SettingsToggleRow(
      label: 'Show message text on your lock screen',
      description:
          'Off by default. When on, a locked iPhone shows who sent a '
          'message and part of what it says - decrypted on this device, '
          'never by the relay that delivers the push.',
      value: enabled,
      semanticLabel: 'Show message text on your lock screen',
      onChanged: (value) async {
        await ref
            .read(pushContentPreviewSettingsProvider.notifier)
            .setEnabled(value);
        unawaited(ref.read(pushControllerProvider.notifier).register());
      },
    );
  }
}

/// Every preference offered in [_NotificationPreferenceRow]'s select sheet,
/// each paired with its label.
const _notificationPreferenceOptions = <(api.NotificationPreference, String)>[
  (api.NotificationPreference.everything, 'All messages'),
  (api.NotificationPreference.mentions, 'Mentions and direct messages'),
  (api.NotificationPreference.nothing, 'Nothing'),
];

/// The "which messages wake a device" row inside [NotificationsSection].
///
/// A real `GET` backs this (`GET /push/preference`), unlike presence
/// visibility, so the current value is read from the server rather than
/// echoed from the last local choice; see [notificationPreferenceProvider].
/// A server too old to have the route answers with an [api.NotFoundException],
/// read here as "not offered by this server" - the row disappears entirely
/// rather than offering a choice that would just 404 on every tap, the same
/// "no handler rather than a button that would just fail" treatment
/// `VoiceState.retryable` already established for a voice join button a 501
/// would only refuse the same way again.
///
/// A 404 reads as "not offered" above; any other fetch failure with nothing
/// cached is a different thing entirely, and stays "Unknown" forever with no
/// way back unless it is told apart from that case, so it renders its own
/// retryable error instead.
class _NotificationPreferenceRow extends ConsumerStatefulWidget {
  const _NotificationPreferenceRow();

  @override
  ConsumerState<_NotificationPreferenceRow> createState() =>
      _NotificationPreferenceRowState();
}

class _NotificationPreferenceRowState
    extends ConsumerState<_NotificationPreferenceRow>
    with GuardedActionState<_NotificationPreferenceRow> {
  Future<void> _set(api.NotificationPreference preference) async {
    final ok = await guard(
      whatFailed: 'update your notification preference',
      action: () => ref.read(apiProvider).setNotificationPreference(preference),
    );
    if (ok) ref.invalidate(notificationPreferenceProvider);
  }

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(notificationPreferenceProvider);
    if (preference.hasError && preference.error is api.NotFoundException) {
      return const SizedBox.shrink();
    }
    // See this row's own doc comment for the 404-versus-everything-else split.
    final loadFailed = preference.hasError && preference.valueOrNull == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSelectRow<api.NotificationPreference>(
          label: 'Notify me for',
          sheetTitle: 'Notifications',
          value: preference.valueOrNull,
          choices: [
            for (final (value, label) in _notificationPreferenceOptions)
              SettingsChoice(value: value, label: label),
          ],
          onChanged: _set,
        ),
        if (loadFailed)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s8,
              0,
              AppSpacing.s8,
              AppSpacing.s8,
            ),
            child: AppErrorState(
              message: 'Could not load your notification preference.',
              onRetry: () => ref.invalidate(notificationPreferenceProvider),
            ),
          ),
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

/// Voice call preferences: microphone, screen share quality, and sounds.
/// A separate screen rather than inline rows, matching how much is on it.
