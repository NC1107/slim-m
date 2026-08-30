// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tests for the CallKit lifecycle bridge: a non-iOS platform never touches
/// the channel, an iOS one forwards the right calls, and an `endCall` from
/// the native side surfaces as [CallLifecycleChannel.endCallRequests].
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_platform/platform.dart';

const _pluginChannelName = 'top.npcserver.slimm/call_lifecycle';

void _mockPlugin(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel(_pluginChannelName),
    handler,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallLifecycleChannel', () {
    test('a non-iOS platform never touches the channel', () async {
      // A recording mock: "does it throw" cannot tell a guard from a swallowed exception.
      final calls = <MethodCall>[];
      _mockPlugin((call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => _mockPlugin(null));

      final lifecycle = CallLifecycleChannel(isIOS: false);
      await lifecycle.callStarted(callId: 'call-1', displayName: 'Voice call');
      await lifecycle.callConnected();
      await lifecycle.callEnded();

      expect(calls, isEmpty);
    });

    test('forwards callStarted with the call id and display name', () async {
      final calls = <MethodCall>[];
      _mockPlugin((call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => _mockPlugin(null));

      final lifecycle = CallLifecycleChannel(isIOS: true);
      await lifecycle.callStarted(
          callId: 'channel-1', displayName: 'Voice call');

      expect(calls, hasLength(1));
      expect(calls.single.method, 'callStarted');
      expect(calls.single.arguments, {
        'callId': 'channel-1',
        'displayName': 'Voice call',
      });
    });

    test('forwards callConnected and callEnded with no arguments', () async {
      final calls = <MethodCall>[];
      _mockPlugin((call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => _mockPlugin(null));

      final lifecycle = CallLifecycleChannel(isIOS: true);
      await lifecycle.callConnected();
      await lifecycle.callEnded();

      expect(calls.map((c) => c.method), ['callConnected', 'callEnded']);
    });

    test('a platform exception from the channel is swallowed', () async {
      _mockPlugin((call) async {
        throw PlatformException(code: 'nope');
      });
      addTearDown(() => _mockPlugin(null));

      final lifecycle = CallLifecycleChannel(isIOS: true);

      await expectLater(
        lifecycle.callStarted(callId: 'call-1', displayName: 'Voice call'),
        completes,
      );
    });

    test('an endCall from native surfaces as an endCallRequests event',
        () async {
      final lifecycle = CallLifecycleChannel(isIOS: true);
      addTearDown(lifecycle.dispose);

      final events = <void>[];
      final sub = lifecycle.endCallRequests.listen(events.add);
      addTearDown(sub.cancel);

      // Drives the handler the channel itself installed, as native code would.
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        _pluginChannelName,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('endCall'),
        ),
        (_) {},
      );

      expect(events, hasLength(1));
    });
  });
}
