// SPDX-License-Identifier: Apache-2.0
/// Tests for the APNs token bridge: the hex-format contract, platform gating,
/// and every ordering the native side can arrive in.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_platform/platform.dart';

const _channelName = 'top.npcserver.slimm/push';

void _mock(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel(_channelName), handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hexEncodeToken', () {
    test('lowercase, zero-padded, and unseparated', () {
      // 0x0f and 0x00 catch the classic off-by-one padding bug; a naive
      // toRadixString without padLeft would emit "f" and "" instead of "0f"
      // and "00".
      expect(hexEncodeToken([0x00, 0x0f, 0xff, 0xa1]), '000fffa1');
    });

    test('an empty token is an empty string, not an error', () {
      expect(hexEncodeToken(const []), '');
    });
  });

  group('ApnsTokenChannel', () {
    test('a non-iOS platform never touches the channel', () async {
      var touched = false;
      _mock((call) async {
        touched = true;
        return null;
      });
      addTearDown(() => _mock(null));

      final result = await ApnsTokenChannel(isIOS: false).token();

      expect(result, isNull);
      expect(touched, isFalse);
    });

    test('a token already cached natively is returned immediately', () async {
      _mock((call) async => switch (call.method) {
            'getToken' => 'abcd1234',
            _ => null,
          });
      addTearDown(() => _mock(null));

      final result = await ApnsTokenChannel(isIOS: true).token();

      expect(result, 'abcd1234');
    });

    test('a cached registration failure resolves to null without waiting',
        () async {
      _mock((call) async => switch (call.method) {
            'getRegistrationError' => 'denied',
            _ => null,
          });
      addTearDown(() => _mock(null));

      final result = await ApnsTokenChannel(isIOS: true)
          .token(timeout: const Duration(seconds: 30));

      expect(result, isNull);
    });

    test('nothing arriving within the timeout resolves to null, not a hang',
        () async {
      _mock((call) async => null);
      addTearDown(() => _mock(null));

      final result = await ApnsTokenChannel(isIOS: true)
          .token(timeout: const Duration(milliseconds: 20));

      expect(result, isNull);
    });

    test('a token arriving mid-probe is not dropped', () async {
      // The native side can deliver the token in the gap between the getToken
      // and getRegistrationError round trips. With no completer installed yet
      // that delivery lands nowhere, and the subsequent wait times out having
      // already been handed the answer - the device then registers for push
      // and never tells the server, which fails as silence rather than error.
      late Future<void> deliver;
      _mock((call) async {
        switch (call.method) {
          case 'getToken':
            return null;
          case 'getRegistrationError':
            // Simulate the token landing while this reply is in flight.
            deliver = TestDefaultBinaryMessengerBinding
                .instance.defaultBinaryMessenger
                .handlePlatformMessage(
              _channelName,
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('onToken', 'abc123'),
              ),
              (_) {},
            );
            return null;
        }
        return null;
      });
      addTearDown(() => _mock(null));

      final channel = ApnsTokenChannel(isIOS: true);
      final token = await channel.token(
        timeout: const Duration(milliseconds: 300),
      );
      await deliver;
      expect(token, 'abc123');
    });
  });
}
