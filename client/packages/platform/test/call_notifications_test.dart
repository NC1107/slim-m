// SPDX-License-Identifier: Apache-2.0
/// Tests for the incoming-call notification seam: a non-Android platform
/// never touches the channel, and Android forwards exactly the call id and
/// caller name it was given.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_platform/platform.dart';

const _pluginChannelName = 'top.npcserver.slimm/calls';

void _mockPlugin(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel(_pluginChannelName), handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallNotifications.showIncomingCall', () {
    test('a non-Android platform never touches the channel', () async {
      // No mock is installed, so reaching the channel would throw instead.
      final notifications = CallNotifications(isAndroid: false);

      await expectLater(
        notifications.showIncomingCall(callId: 'call-1', callerName: 'Alice'),
        completes,
      );
    });

    test('forwards the call id and caller name verbatim on Android', () async {
      final calls = <MethodCall>[];
      _mockPlugin((call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => _mockPlugin(null));

      final notifications = CallNotifications(isAndroid: true);
      await notifications.showIncomingCall(
          callId: 'call-42', callerName: 'Bob');

      expect(calls, hasLength(1));
      expect(calls.single.method, 'showIncomingCall');
      expect(
          calls.single.arguments, {'callId': 'call-42', 'callerName': 'Bob'});
    });

    test(
        'a platform exception is swallowed, not thrown onto the background '
        'isolate', () async {
      _mockPlugin((call) async {
        throw PlatformException(code: 'ERR', message: 'native side blew up');
      });
      addTearDown(() => _mockPlugin(null));

      final notifications = CallNotifications(isAndroid: true);
      await expectLater(
        notifications.showIncomingCall(callId: 'call-1', callerName: 'Ada'),
        completes,
      );
    });

    test('a missing native plugin is swallowed too', () async {
      // No mock handler installed, so the channel answers MissingPluginException.
      final notifications = CallNotifications(isAndroid: true);
      await expectLater(
        notifications.showIncomingCall(callId: 'call-1', callerName: 'Ada'),
        completes,
      );
    });
  });
}
