// SPDX-License-Identifier: Apache-2.0
/// Turns an incoming data-only FCM message into the same fixed, content-free
/// local notification on Android, whenever the app is backgrounded or not
/// running at all - never while it is in the foreground, see
/// [firebaseMessagingBackgroundHandler]'s doc for why.
///
/// The relay never sends a `notification` field for Android (see
/// `slim-m-relay/internal/fcm/fcm.go`), so nothing shows up on its own; this
/// file is what builds it. This runs in FCM's own background isolate - a
/// fresh Dart VM with no widget tree, no Riverpod container, no signed-in
/// session, nothing but what this file constructs for itself - so nothing
/// here may depend on `providers.dart` or any other app state.
library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:slimm_platform/platform.dart';

/// Mirrors the relay's own `genericAlert` map (see
/// `slim-m-relay/internal/apns/apns.go`): only the two kinds a person should
/// actually be alerted about get a fixed, sender-and-content-free line.
/// "call" rings through its own path and "wake" is a deliberately silent
/// background sync hint - both stay unshown here exactly as they do on iOS,
/// where only `message` and `mention` carry a plaintext `aps.alert` at all.
const _genericAlerts = {
  'message': 'New message',
  'mention': 'You were mentioned',
};

/// The fixed, content-free text to show for a push of this `kind`, or null
/// if `kind` should stay silent (or is missing/unrecognised, which the same
/// way forward). A plain function, rather than inlined where it is used, so
/// the kind-to-text mapping has a unit test that needs neither a plugin nor
/// an Android device.
String? genericAlertTextFor(String? kind) => _genericAlerts[kind];

/// The background isolate entry point FCM invokes when a data message
/// arrives while the app is backgrounded or fully killed - the only two
/// states this ever needs to show anything for. FCM only calls its
/// foreground counterpart, `onMessage`, while the app is genuinely open, and
/// by then the same message is already visible through the live WebSocket
/// the app keeps while foregrounded (see `sync_controller.dart`): stacking a
/// heads-up notification on top of that would tell the user about the exact
/// screen already in front of them, including the (fairly common) case where
/// the server's own foreground signal has gone stale - it is reported only
/// on lifecycle transitions and treated as stale after a minute (see
/// `PushController._reportLifecycle`) - and sent a push despite the device
/// never having left the app. So nothing here listens for `onMessage` at
/// all; this is the whole story.
///
/// Must stay a top-level function with exactly this signature:
/// firebase_messaging spawns a fresh isolate and calls it by reference, so an
/// instance method (which implicitly captures `this`) cannot be registered
/// here, and `@pragma('vm:entry-point')` is what keeps the tree-shaker from
/// removing a function nothing in this isolate visibly calls.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final text = genericAlertTextFor(message.data['kind']);
  if (text == null) return;
  await LocalNotifications().show(text);
}
