// SPDX-License-Identifier: Apache-2.0
/// Shows Android's local, content-free notification for a data-only push,
/// and owns the versioned channel it displays through.
///
/// Android 8+ (API 26) refuses to show anything without a channel, and a
/// channel's importance is fixed forever once created: the OS silently
/// ignores any later attempt to change it on an existing id. The id here is
/// therefore versioned ("messages_v1"): raising or lowering importance later
/// means minting "messages_v2" and letting this one age out, never editing
/// this one's settings in place.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'host_platform.dart';

/// This app's one notification channel today. See the library doc for why a
/// future change in importance mints a new, differently-versioned id rather
/// than editing this one.
const messagesChannelId = 'messages_v1';
const messagesChannelName = 'Messages';

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

  static const _channel = AndroidNotificationChannel(
    messagesChannelId,
    messagesChannelName,
    description: 'New messages and mentions.',
    importance: Importance.high,
  );

  /// Creates the channel and initializes the plugin. Both calls are
  /// idempotent on the native side, so calling this more than once -
  /// including once per background isolate, which cannot remember it
  /// already ran - is safe.
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
    await android?.createNotificationChannel(_channel);
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

  /// Shows [text] as this app's one active notification, replacing whatever
  /// this app last showed rather than stacking beside it. The payload is an
  /// encrypted envelope nothing on this device can open yet, so every shown
  /// notification is already identical and content-free; stacking several
  /// copies of the same unlabeled line would add clutter, not information.
  /// It also matches the server's own choice to collapse a burst of messages
  /// into at most one wake per idle recipient (see `PushSender`) rather than
  /// one push per message.
  Future<void> show(String text) async {
    if (!_isAndroid) return;
    await _ensureReady();
    await _plugin.show(
      0,
      'slim-m',
      text,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          messagesChannelId,
          messagesChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
