// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// Push registration, lifecycle reporting, and the caller's own account-wide
/// notification preference: the `push` tag.
///
/// Split out of `client.dart` purely to stay under this repo's line budget;
/// it used to sit directly on [SlimmApi] as a "--- Push ---" section.
extension SlimmApiPush on SlimmApi {
  /// Registers, or replaces, this device's push registration. The server seals
  /// a content-free envelope to [pushPublicKey]; only this device holds the
  /// matching private key, so a device that never registers one gets no push.
  ///
  /// [includeContent] asks the server to seal a short preview (sender,
  /// channel, up to 160 characters of body) inside that same envelope, for a
  /// device that can decrypt it and show it in a notification. Defaults to
  /// false, matching the server's own default: a device that never asks gets
  /// exactly the content-free envelope it always got.
  Future<void> registerPush({
    required String platform,
    required String pushToken,
    String? voipPushToken,
    required String pushPublicKey,
    bool includeContent = false,
  }) =>
      _send(
        'PUT',
        '/push',
        body: {
          'platform': platform,
          'push_token': pushToken,
          'voip_push_token': voipPushToken,
          'push_public_key': pushPublicKey,
          'include_content': includeContent,
        },
        expectNoContent: true,
      );

  /// Clears this device's push registration.
  Future<void> unregisterPush() =>
      _send('DELETE', '/push', expectNoContent: true);

  /// Reports this device's app lifecycle state. Push is triggered from this
  /// self-reported state rather than WebSocket presence, because a suspended
  /// but still-connected socket is not proof the app can show a notification.
  Future<void> reportPushLifecycle({required String state}) => _send(
        'PUT',
        '/push/lifecycle',
        body: {'state': state},
        expectNoContent: true,
      );

  /// Reads the caller's own notification preference. Account-wide, unlike
  /// every other call in this extension: which messages are worth waking any
  /// of this account's devices for, not one device's own registration.
  ///
  /// A [NotFoundException] means this server predates the route, which a
  /// caller must read as "not offered here", never as
  /// [NotificationPreference.everything].
  Future<NotificationPreference> notificationPreference() async {
    final json = await _send('GET', '/push/preference');
    return NotificationPreference.parse(
      (json as Map<String, dynamic>)['preference'] as String,
    );
  }

  /// Sets the caller's own notification preference. Enforced where push
  /// recipients are computed, before a device is ever woken - never a filter
  /// this client applies to a push that has already landed.
  Future<NotificationPreference> setNotificationPreference(
    NotificationPreference preference,
  ) async {
    final json = await _send(
      'PUT',
      '/push/preference',
      body: {'preference': preference.wire},
    );
    return NotificationPreference.parse(
      (json as Map<String, dynamic>)['preference'] as String,
    );
  }
}
