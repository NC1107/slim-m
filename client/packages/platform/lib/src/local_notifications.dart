// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Shows Android's local, content-free notification for a data-only push,
/// and owns the versioned channels it displays through.
///
/// Android 8+ (API 26) refuses to show anything without a channel, and a
/// channel's importance, sound and vibration are fixed forever once
/// created: the OS silently ignores any later attempt to change them on an
/// existing id. Every channel id here therefore follows `<kind>_v<version>`
/// ("messages_v1", "mentions_v1"; the call channel is Android's own
/// `NotificationCompat.CallStyle` one and lives natively in
/// `IncomingCallNotifier.kt`, which follows the identical convention since
/// `flutter_local_notifications` has no CallStyle support): raising or
/// lowering a channel's settings later means minting that one channel's
/// next version and letting the old id age out, never editing it in place.
/// [LocalAlertChannel] is where a version bump actually happens - each
/// variant's `id` is the one line that changes.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'host_platform.dart';

const messagesChannelId = 'messages_v1';
const messagesChannelName = 'Messages';
const mentionsChannelId = 'mentions_v1';
const mentionsChannelName = 'Mentions';

/// The Android channel a plain content-free alert posts through, and the
/// stable notification id it replaces rather than stacks beside.
///
/// Two channels rather than one, even with both at the same importance
/// today: a channel is the only unit Android's own notification settings
/// let a person control per *kind* of alert, so someone who wants a mention
/// to buzz but an ordinary message to stay quiet - or the reverse - needs
/// them split apart from the start. Collapsing the two into one channel now
/// and splitting later would need the exact same mint-a-new-id dance the
/// library doc above describes, for a distinction a person can already
/// reach for the day this ships.
enum LocalAlertChannel {
  messages(
    id: messagesChannelId,
    name: messagesChannelName,
    description: 'New messages.',
    notificationId: 1,
  ),
  mentions(
    id: mentionsChannelId,
    name: mentionsChannelName,
    description: 'Messages that mention you.',
    notificationId: 2,
  );

  const LocalAlertChannel({
    required this.id,
    required this.name,
    required this.description,
    required this.notificationId,
  });

  final String id;
  final String name;
  final String description;

  /// A fixed id per channel rather than one shared id: a person can
  /// legitimately have an unread ordinary message and an unread mention at
  /// once, and collapsing both onto one notification id would silently
  /// drop whichever arrived first the moment the second one replaced it.
  final int notificationId;
}

/// Registers the plugin's Android platform implementation, the way the real
/// plugin does for itself in a running app. A plain `flutter_test` run never
/// does this on its own, so a test that constructs [LocalNotifications] with
/// `isAndroid: true` and lets it reach the real plugin (rather than
/// injecting a fake [AndroidPermissionRequester]) needs to call this first,
/// typically from `setUpAll` - without it, resolving the Android
/// implementation throws `LateInitializationError` instead of behaving like
/// any other unregistered platform.
@visibleForTesting
void registerAndroidLocalNotificationsPluginForTest() {
  AndroidFlutterLocalNotificationsPlugin.registerWith();
}

/// The minimal Android runtime-permission surface [LocalNotifications]
/// needs, factored out so a test can report "denied" (or "granted") without
/// a real Android device or plugin channel behind it - the same
/// seam-behind-an-interface shape [FcmTokenSource] uses in this package.
abstract interface class AndroidPermissionRequester {
  /// Requests Android's POST_NOTIFICATIONS permission (a no-op grant below
  /// API 33) and reports whether the app is left permitted to show
  /// notifications, one way or another.
  Future<bool> requestNotificationsPermission();
}

/// The real seam, backed by the plugin's own Android implementation.
class _PluginPermissionRequester implements AndroidPermissionRequester {
  _PluginPermissionRequester(this._plugin);
  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<bool> requestNotificationsPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }
}

/// Displays the fixed local notification a data-only push needs on Android,
/// and creates the versioned channel it displays through.
///
/// A clean no-op on iOS, Linux and the web: iOS shows its alert straight from
/// APNs with no app code involved (a `kind` that should alert already carries
/// a plain-text `aps.alert` the OS renders itself), and neither Linux nor a
/// browser has a push channel to display anything from. flutter_local_
/// notifications ships no web implementation either, so there is nothing
/// behind the plugin to call there.
class LocalNotifications {
  LocalNotifications({
    FlutterLocalNotificationsPlugin? plugin,
    bool? isAndroid,
    AndroidPermissionRequester? permissionRequester,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _isAndroid = isAndroid ?? isAndroidHost,
        _permissionRequester = permissionRequester;

  final FlutterLocalNotificationsPlugin _plugin;
  final bool _isAndroid;

  /// Nullable rather than defaulted in the initializer list: the default wraps
  /// `_plugin`, and an initializer list cannot read a field it is still in the
  /// middle of assigning. Built lazily in requestPermission instead.
  final AndroidPermissionRequester? _permissionRequester;
  bool _ready = false;

  /// Creates every [LocalAlertChannel] and initializes the plugin. Every
  /// call here is idempotent on the native side, so calling this more than
  /// once - including once per background isolate, which cannot remember it
  /// already ran - is safe: an unchanged channel id is a no-op, and Android
  /// only reads a changed name or description back out of it, never
  /// importance.
  ///
  /// Deliberately does NOT request notification permission: that needs an
  /// Activity, and this is called from [show], which FCM invokes from its
  /// own Activity-less background isolate for every backgrounded or killed
  /// push - the one path that exists to display those at all. Asking here
  /// used to throw in exactly that isolate, silently dropping every
  /// backgrounded notification. See [requestPermission] for where the ask
  /// actually belongs.
  Future<void> _ensureReady() async {
    if (!_isAndroid || _ready) return;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    for (final channel in LocalAlertChannel.values) {
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          channel.id,
          channel.name,
          description: channel.description,
          importance: Importance.high,
        ),
      );
    }
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_notify'),
      ),
    );
    _ready = true;
  }

  /// Requests Android's runtime notification permission (Android 13+; a
  /// no-op grant on everything older), and reports whether notifications
  /// are actually permitted afterwards.
  ///
  /// Callers MUST only ever invoke this from the foreground app - somewhere
  /// with a live Activity, such as in response to a fresh sign-in or an app
  /// resume - never from FCM's background isolate: asking the OS to show a
  /// permission dialog needs an Activity to show it in front of, and this
  /// throws there instead of prompting anyone. [show] never calls this for
  /// exactly that reason.
  Future<bool> requestPermission() async {
    if (!_isAndroid) return true;
    await _ensureReady();
    final requester =
        _permissionRequester ?? _PluginPermissionRequester(_plugin);
    return requester.requestNotificationsPermission();
  }

  /// Shows [text] as this app's one active notification for [channel],
  /// replacing whatever this app last showed on that channel rather than
  /// stacking beside it. The payload is an encrypted envelope nothing on
  /// this device can open yet, so every shown notification is already
  /// identical and content-free within its own channel; stacking several
  /// copies of the same unlabeled line would add clutter, not information.
  /// It also matches the server's own choice to collapse a burst of
  /// messages into at most one wake per idle recipient (see `PushSender`)
  /// rather than one push per message.
  Future<void> show(String text, {required LocalAlertChannel channel}) async {
    if (!_isAndroid) return;
    await _ensureReady();
    await _plugin.show(
      channel.notificationId,
      'slim-m',
      text,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
