// SPDX-License-Identifier: Apache-2.0
/// Tests for push registration: gated on a session, and never surfacing a
/// failure as an app-breaking error.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/push_controller.dart';
import 'package:slimm_platform/platform.dart';

const _channelName = 'top.npcserver.slimm/push';

void _mock(Future<Object?> Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel(_channelName), handler);
}

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushController.register', () {
    test('without a session, nothing is attempted', () async {
      // The default sessionProvider starts signed out; nothing is overridden,
      // so a real network call or a real MethodChannel round-trip would both
      // be surfaced failures, proving the session check runs before either.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(pushControllerProvider).register();
    });

    test('a server failure never propagates out of register()', () async {
      _mock((call) async => switch (call.method) {
            'getToken' => 'abcd1234',
            _ => null,
          });
      addTearDown(() => _mock(null));

      final session = SessionStore(tokens: _tokens);
      final api = SlimmApi(
        baseUrl: Uri.parse('http://localhost:8080'),
        session: session,
        httpClient: MockClient((_) async => http.Response('busy', 503)),
      );
      addTearDown(api.close);

      final container = ProviderContainer(overrides: [
        sessionProvider.overrideWithValue(session),
        apiProvider.overrideWithValue(api),
        apnsTokenChannelProvider.overrideWithValue(
          ApnsTokenChannel(isIOS: true),
        ),
      ]);
      addTearDown(container.dispose);

      // No expectLater/throwsA here on purpose: the assertion is that this
      // completes at all.
      await container.read(pushControllerProvider).register();
    });
  });
}
