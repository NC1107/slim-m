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
/// are already reading is noise, not news. Own messages and muted channels are
/// skipped for the reasons their names give.
///
/// Read once from bootstrap, beside the sync and push controllers, so the
/// subscription lives for the whole signed-in session.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_platform/platform.dart';

import 'channel_notification_overrides_controller.dart';
import 'live_events.dart';
import 'providers.dart';
import 'push_controller.dart';

final desktopMessageNotifierProvider = Provider<void>((ref) {
  // Android and iOS notify from platform push; only the desktop needs this.
  if (!isDesktopHost) return;

  final selfId = ref.read(sessionProvider).tokens?.userId;
  final notifications = ref.read(localNotificationsProvider);

  final sub = ref.read(liveEventsProvider).listen((event) {
    if (event is! api.MessageCreated) return;
    final message = event.message;

    // Not my own message echoed back to me.
    if (message.authorId != null && message.authorId == selfId) return;

    // Skip while focused: a foreground app already shows unread in the rail.
    final foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (foreground) return;

    // A muted channel asked for silence.
    if (ref
        .read(channelNotificationOverridesProvider)
        .isMuted(message.channelId)) {
      return;
    }

    final author = message.authorDisplayName;
    final text = author == null || author.isEmpty
        ? 'New message'
        : 'New message from $author';
    // Fire-and-forget: a failed notification must never break event handling.
    notifications.show(text, channel: LocalAlertChannel.messages);
  });
  ref.onDispose(sub.cancel);
});
