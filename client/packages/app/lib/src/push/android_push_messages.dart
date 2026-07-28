// SPDX-License-Identifier: Apache-2.0
/// Turns an incoming data-only FCM message into the same fixed, content-free
/// local notification on Android, whenever the app is backgrounded or not
/// running at all - never while it is in the foreground, see
/// [firebaseMessagingBackgroundHandler]'s doc for why. A `call` kind gets
/// Android's incoming-call notification (`CallNotifications`) instead; every
/// other alerting kind gets the plain one (`LocalNotifications`).
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

import '../ids.dart';

/// Mirrors the relay's own `genericAlert` map (see
/// `slim-m-relay/internal/apns/apns.go`): only the two kinds a person should
/// actually be alerted about get a fixed, sender-and-content-free line.
/// "call" rings through its own path (below) and "wake" is a deliberately
/// silent background sync hint - both stay unshown here exactly as they do
/// on iOS, where only `message` and `mention` carry a plaintext `aps.alert`.
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

/// The caller name shown when a `call` push does not name one - the content-
/// free envelope carries none today, so this is the honest label rather than
/// a guess, matching `VoipCallHandler.unknownCaller` on iOS.
const unknownCaller = 'Incoming call';

/// The caller name to show for a `call` push's [data], distinguishing a
/// present-but-unusable field from a genuinely missing one exactly as
/// [callIdFor] does, so garbage input degrades to [unknownCaller] rather
/// than throwing out of the background isolate.
String callerNameFor(Map<String, dynamic> data) {
  final raw = data['caller'];
  return raw is String && raw.isNotEmpty ? raw : unknownCaller;
}

/// The call identity to show the notification under: [data]'s own `call_id`
/// when it is a usable string, so a repeat push for the same call replaces
/// the notification already on screen rather than stacking a second one, and
/// a freshly generated id otherwise - never a dropped call, mirroring
/// `VoipCallHandler.callId(from:)`'s same fallback on iOS.
String callIdFor(Map<String, dynamic> data) {
  final raw = data['call_id'];
  return raw is String && raw.isNotEmpty ? raw : newMessageId();
}

/// What one push should do to this device's notification shade: nothing, the
/// plain content-free alert, or the incoming-call notification.
sealed class PushAction {
  const PushAction();
}

/// Nothing to show: a silent kind, or one this build does not recognise.
class PushActionNone extends PushAction {
  const PushActionNone();
}

/// Show [text] as the plain, content-free notification.
class PushActionGenericAlert extends PushAction {
  const PushActionGenericAlert(this.text);
  final String text;
}

/// Show, or replace, the incoming-call notification for [callId].
class PushActionIncomingCall extends PushAction {
  const PushActionIncomingCall({
    required this.callId,
    required this.callerName,
  });
  final String callId;
  final String callerName;
}

/// Decides what a push's [data] should do, before anything native is ever
/// touched - so the whole kind-to-action decision, including the branch a
/// `call` kind takes, has a unit test that needs neither a plugin nor an
/// Android device, the same reason [genericAlertTextFor] is its own function.
PushAction actionFor(Map<String, dynamic> data) {
  if (data['kind'] == 'call') {
    return PushActionIncomingCall(
      callId: callIdFor(data),
      callerName: callerNameFor(data),
    );
  }
  final text = genericAlertTextFor(data['kind']);
  return text == null ? const PushActionNone() : PushActionGenericAlert(text);
}

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
  switch (actionFor(message.data)) {
    case PushActionNone():
      return;
    case PushActionGenericAlert(:final text):
      await LocalNotifications().show(text);
    case PushActionIncomingCall(:final callId, :final callerName):
      await CallNotifications().showIncomingCall(
        callId: callId,
        callerName: callerName,
      );
  }
}
