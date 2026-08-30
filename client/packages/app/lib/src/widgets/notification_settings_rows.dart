// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The rows inside [NotificationsSection] (`personal_status_sections.dart`)
/// that are each their own genuine round trip to the server, rather than a
/// bare toggle backed by local state: the lock-screen preview switch, the
/// account-wide notification preference, and the quiet-hours window.
///
/// Split out of personal_status_sections.dart purely to stay under this
/// repo's line budget.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/notification_preference_controller.dart';
import '../providers/providers.dart';
import '../providers/push_content_preview_settings.dart';
import '../providers/push_controller.dart';
import '../providers/quiet_hours_controller.dart';
import 'run_guarded.dart';
import 'settings_select_row.dart';
import 'settings_toggle_row.dart';

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
class PushContentPreviewRow extends ConsumerWidget {
  const PushContentPreviewRow({super.key});

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

/// Every preference offered in [NotificationPreferenceRow]'s select sheet,
/// each paired with its label.
const _notificationPreferenceOptions = <(api.NotificationPreference, String)>[
  (api.NotificationPreference.everything, 'All messages'),
  (api.NotificationPreference.mentions, 'Mentions and direct messages'),
  (api.NotificationPreference.nothing, 'Nothing'),
];

/// The "which messages wake a device" row inside `NotificationsSection`.
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
class NotificationPreferenceRow extends ConsumerStatefulWidget {
  const NotificationPreferenceRow({super.key});

  @override
  ConsumerState<NotificationPreferenceRow> createState() =>
      _NotificationPreferenceRowState();
}

class _NotificationPreferenceRowState
    extends ConsumerState<NotificationPreferenceRow>
    with GuardedActionState<NotificationPreferenceRow> {
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

/// The default window offered the first time this account turns quiet hours
/// on: 23:00-08:00, the motivating case named in the feature's own design
/// note, not an arbitrary placeholder.
const _defaultQuietHoursStart = TimeOfDay(hour: 23, minute: 0);
const _defaultQuietHoursEnd = TimeOfDay(hour: 8, minute: 0);

/// The "do not wake me for ordinary chatter overnight" row inside
/// `NotificationsSection`, beside [NotificationPreferenceRow].
///
/// A window in effect narrows [api.NotificationPreference.everything] to
/// [api.NotificationPreference.mentions] for its own duration
/// (`push::recipients::narrow_for_notification_preference`) - never to
/// [api.NotificationPreference.nothing], so a real mention still wakes a
/// device overnight. Times are entered and shown in this device's local
/// clock; [utcMinutesFromLocalTimeOfDay] converts before every write, and
/// [localTimeOfDayFromUtcMinutes] converts back for display, so the server
/// only ever sees UTC.
class QuietHoursRow extends ConsumerStatefulWidget {
  const QuietHoursRow({super.key});

  @override
  ConsumerState<QuietHoursRow> createState() => _QuietHoursRowState();
}

class _QuietHoursRowState extends ConsumerState<QuietHoursRow>
    with GuardedActionState<QuietHoursRow> {
  Future<void> _apply(TimeOfDay start, TimeOfDay end) async {
    final ok = await guard(
      whatFailed: 'update your quiet hours',
      action: () => ref
          .read(apiProvider)
          .setQuietHours(
            api.QuietHours(
              startMinute: utcMinutesFromLocalTimeOfDay(start),
              endMinute: utcMinutesFromLocalTimeOfDay(end),
            ),
          ),
    );
    if (ok) ref.invalidate(quietHoursProvider);
  }

  Future<void> _toggle(bool enabled) async {
    if (!enabled) {
      final ok = await guard(
        whatFailed: 'turn off quiet hours',
        action: () => ref.read(apiProvider).clearQuietHours(),
      );
      if (ok) ref.invalidate(quietHoursProvider);
      return;
    }
    await _apply(_defaultQuietHoursStart, _defaultQuietHoursEnd);
  }

  Future<void> _pickStart(TimeOfDay start, TimeOfDay end) async {
    final picked = await showTimePicker(context: context, initialTime: start);
    if (picked != null) await _apply(picked, end);
  }

  Future<void> _pickEnd(TimeOfDay start, TimeOfDay end) async {
    final picked = await showTimePicker(context: context, initialTime: end);
    if (picked != null) await _apply(start, picked);
  }

  @override
  Widget build(BuildContext context) {
    final quietHours = ref.watch(quietHoursProvider);
    if (quietHours.hasError && quietHours.error is api.NotFoundException) {
      return const SizedBox.shrink();
    }
    final loadFailed = quietHours.hasError && quietHours.valueOrNull == null;
    final window = quietHours.valueOrNull;
    final enabled = window != null;
    final start = window == null
        ? _defaultQuietHoursStart
        : localTimeOfDayFromUtcMinutes(window.startMinute);
    final end = window == null
        ? _defaultQuietHoursEnd
        : localTimeOfDayFromUtcMinutes(window.endMinute);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsToggleRow(
          label: 'Quiet hours',
          description:
              'Narrows notifications to mentions and direct messages during '
              'this window each day. A mention still wakes a device.',
          value: enabled,
          onChanged: quietHours.isLoading ? null : _toggle,
          semanticLabel: 'Quiet hours',
        ),
        if (enabled) ...[
          AppListRow(
            label: 'Starts',
            trailing: Text(start.format(context)),
            onTap: () => _pickStart(start, end),
          ),
          AppListRow(
            label: 'Ends',
            trailing: Text(end.format(context)),
            onTap: () => _pickEnd(start, end),
          ),
        ],
        if (loadFailed)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s8,
              0,
              AppSpacing.s8,
              AppSpacing.s8,
            ),
            child: AppErrorState(
              message: 'Could not load your quiet hours.',
              onRetry: () => ref.invalidate(quietHoursProvider),
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
