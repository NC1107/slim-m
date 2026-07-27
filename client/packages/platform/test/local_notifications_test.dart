// SPDX-License-Identifier: Apache-2.0
/// Tests for the local-notification seam: the versioned channel constants,
/// that a non-Android platform never touches the plugin, and that
/// permission is requested (and only requested) from [requestPermission],
/// never as a side effect of [LocalNotifications.show] - the call FCM's
/// Activity-less background isolate makes for every backgrounded push.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_platform/platform.dart';

/// The channel flutter_local_notifications' Android implementation sends
/// every call over - `initialize`, `createNotificationChannel`,
/// `requestNotificationsPermission`, `show`, all of it - so mocking this one
/// channel is what lets a test drive [LocalNotifications] on a simulated
/// Android without a real device.
const _pluginChannelName = 'dexterous.com/flutter/local_notifications';

void _mockPlugin(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel(_pluginChannelName), handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerAndroidLocalNotificationsPluginForTest);

  group('channel constants', () {
    test('the messages channel id carries an explicit version', () {
      // A version in the id is what makes a later importance change safe:
      // Android forbids editing an existing channel's, so the fix is a new id.
      expect(messagesChannelId, 'messages_v1');
    });
  });

  group('LocalNotifications.show', () {
    test('a non-Android platform never touches the plugin', () async {
      // No mock handler is installed, so a call reaching the plugin would throw
      // MissingPluginException; completing proves the platform gate ran first.
      final notifications = LocalNotifications(isAndroid: false);

      await expectLater(notifications.show('New message'), completes);
    });

    test(
        'never requests notification permission as a side effect - only '
        'requestPermission does, and show is exactly what runs in FCM\'s '
        'Activity-less background isolate for every backgrounded push',
        () async {
      final calledMethods = <String>[];
      _mockPlugin((call) async {
        calledMethods.add(call.method);
        return true;
      });
      addTearDown(() => _mockPlugin(null));

      final notifications = LocalNotifications(isAndroid: true);
      await notifications.show('New message');

      expect(
        calledMethods,
        isNot(contains('requestNotificationsPermission')),
        reason: 'requesting permission from here throws in a background '
            'isolate with no Activity, silently dropping every '
            'backgrounded notification - the entire point of push',
      );
    });
  });

  group('LocalNotifications.requestPermission', () {
    test(
        'is a no-op true on a non-Android platform, touching neither the '
        'plugin nor a requester', () async {
      final requester = _FakePermissionRequester(granted: false);
      final notifications = LocalNotifications(
        isAndroid: false,
        permissionRequester: requester,
      );

      final granted = await notifications.requestPermission();

      expect(granted, isTrue);
      expect(requester.calls, 0);
    });

    test('reports true when the requester grants it', () async {
      _mockPlugin((call) async => true);
      addTearDown(() => _mockPlugin(null));
      final requester = _FakePermissionRequester(granted: true);

      final notifications = LocalNotifications(
        isAndroid: true,
        permissionRequester: requester,
      );
      final granted = await notifications.requestPermission();

      expect(granted, isTrue);
      expect(requester.calls, 1);
    });

    test(
        'reports false when the requester denies it, rather than assuming '
        'a token means notifications will show', () async {
      _mockPlugin((call) async => true);
      addTearDown(() => _mockPlugin(null));
      final requester = _FakePermissionRequester(granted: false);

      final notifications = LocalNotifications(
        isAndroid: true,
        permissionRequester: requester,
      );
      final granted = await notifications.requestPermission();

      expect(granted, isFalse);
      expect(requester.calls, 1);
    });
  });
}

/// An [AndroidPermissionRequester] a test fully controls, standing in for
/// the plugin's own Android implementation.
class _FakePermissionRequester implements AndroidPermissionRequester {
  _FakePermissionRequester({required this.granted});

  final bool granted;
  int calls = 0;

  @override
  Future<bool> requestNotificationsPermission() async {
    calls++;
    return granted;
  }
}
