// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Desktop-only: posts an OS notification when a message arrives while the
/// window is not in the foreground.
///
/// The desktop has no remote push - nothing wakes a closed app the way FCM or
/// APNs wakes a phone - so the only notifications it can show are for messages
/// that arrive over the live socket while the app is running. This turns those
/// into `org.freedesktop.Notifications` alerts through
/// [LocalNotifications.show]; on Android and iOS the platform push already
/// does this, so this stays inert there.
///
/// Only when the window is not focused. A focused desktop app shows its own
/// unread state in the rail, and a second OS banner on top of the channel you
/// are already reading is noise, not news. Own messages are skipped for the
/// reason their name gives.
///
/// The channel's own override runs through [channelEarnsASound], the gate the
/// chime already uses and the rule the server's
/// `narrow_for_notification_preference` enforces for push. This path used to
/// read only the mute half of it, so a channel narrowed to mentions kept
/// raising a banner for every ordinary message while the chime beside it
/// stayed silent.
///
/// Also gated by the notification schedule (`notification_schedule_rules.dart`),
/// the same policy `notification_sound_controller.dart` already applies to
/// the chime - the owner's own instruction was that both foreground paths
/// honour it, not only the one with a sound attached.
///
/// Read once from bootstrap, beside the sync and push controllers, so the
/// subscription lives for the whole signed-in session.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_platform/platform.dart';

import '../widgets/message_mentions.dart' show messageMentionsUsername;
import 'channel_notification_overrides_controller.dart';
import 'live_events.dart';
import 'notification_schedule_controller.dart';
import 'notification_schedule_rules.dart';
import 'notification_sound_rules.dart';
import 'providers.dart';
import 'push_controller.dart';

final desktopMessageNotifierProvider = Provider<void>((ref) {
  // Android and iOS notify from platform push; only the desktop needs this.
  if (!isDesktopHost) return;

  final notifier = _DesktopMessageNotifier(ref);
  final sub = ref.read(liveEventsProvider).listen(notifier.onServerEvent);
  ref.onDispose(sub.cancel);
});

/// Holds the one thing this handler caches across events: the caller's own
/// username, for mention detection, the same "cached against the id it was
/// resolved for" shape `NotificationSoundController` uses for the identical
/// lookup.
class _DesktopMessageNotifier {
  _DesktopMessageNotifier(this._ref);

  final Ref _ref;
  String? _selfUsername;
  String? _selfUsernameForId;

  void onServerEvent(api.ServerEvent event) {
    if (event case api.MessageCreated(:final message)) {
      unawaited(_onMessageCreated(message));
    }
  }

  Future<void> _onMessageCreated(api.Message message) async {
    // Per event, not at bootstrap: signing in as someone else changes "me".
    final selfId = _ref.read(sessionProvider).tokens?.userId;
    if (message.authorId != null && message.authorId == selfId) return;

    // Skip while focused: a foreground app shows unread in the rail already.
    final foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (foreground) return;

    final store = await _ref.read(storeProvider.future);
    final channel = await store.watchChannelRow(message.channelId).first;
    final isDm = channel?.kind == 'dm';

    var mentionsSelf = false;
    if (!isDm && selfId != null) {
      final username = await _resolveSelfUsername(selfId);
      if (username != null) {
        mentionsSelf = messageMentionsUsername(message.content, username);
      }
    }

    if (!channelEarnsASound(
      channelOverride: _ref
          .read(channelNotificationOverridesProvider)
          .overrideFor(message.channelId),
      isDm: isDm,
      mentionsSelf: mentionsSelf,
    )) {
      return;
    }

    final schedule = _ref.read(notificationScheduleProvider).valueOrNull;
    if (!scheduleEarnsASound(
      state: evaluateNotificationSchedule(schedule),
      channelAllowed:
          schedule?.allowedChannelIds.contains(message.channelId) ?? false,
      authorAllowed:
          schedule?.allowedUserIds.contains(message.authorId) ?? false,
      isDm: isDm,
      mentionsSelf: mentionsSelf,
    )) {
      return;
    }

    final author = message.authorDisplayName;
    final text = author == null || author.isEmpty
        ? 'New message'
        : 'New message from $author';
    final notifications = _ref.read(localNotificationsProvider);
    // The per-kind OS control only reaches a banner filed under the kind it is; see LocalAlertChannel.
    final alertChannel = mentionsSelf
        ? LocalAlertChannel.mentions
        : LocalAlertChannel.messages;
    // Fire-and-forget: a failed notification must never break event handling.
    unawaited(notifications.show(text, channel: alertChannel));
  }

  /// Best-effort, matching `NotificationSoundController`'s own: a lookup
  /// failure just leaves this one message read as not a mention.
  Future<String?> _resolveSelfUsername(String selfId) async {
    if (_selfUsernameForId == selfId) return _selfUsername;
    try {
      final me = await _ref.read(apiProvider).me();
      _selfUsername = me.username;
      _selfUsernameForId = selfId;
    } catch (_) {
      // Handled above: the caller reads the unchanged (possibly null) cache.
    }
    return _selfUsername;
  }
}
