// SPDX-License-Identifier: Apache-2.0
/// Whether a registration carries `include_content`, split out of
/// `push_controller_test.dart` to keep that file at its allowlisted size
/// (`scripts/file-budget-allow.txt`) rather than growing it further.
///
/// Fixtures are a small, deliberate duplicate of that file's own
/// `_container`/`_mock`/`_tokens` rather than a shared import: Dart privacy
/// is per-file, so a leading-underscore helper in one test file is not
/// reachable from a sibling, the same constraint CLAUDE.md already records
/// for cross-package test fixtures.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/push_content_preview_settings.dart';
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

ProviderContainer _container({
  required http.Client httpClient,
  SessionStore? session,
  ApnsTokenChannel? channel,
}) {
  return ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      if (session != null) sessionProvider.overrideWithValue(session),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: httpClient,
        );
        ref.onDispose(api.close);
        return api;
      }),
      if (channel != null) apnsTokenChannelProvider.overrideWithValue(channel),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('push content preview', () {
    test('registration sends include_content: false by default', () async {
      Map<String, dynamic>? sentBody;
      _mock(
        (call) async => switch (call.method) {
          'getToken' => 'abcd1234',
          _ => null,
        },
      );
      addTearDown(() => _mock(null));

      final session = SessionStore(tokens: _tokens);
      final container = _container(
        session: session,
        httpClient: MockClient((request) async {
          if (request.method == 'PUT' && request.url.path == '/push') {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          }
          return http.Response('', 204);
        }),
        channel: ApnsTokenChannel(isIOS: true),
      );
      addTearDown(container.dispose);

      await container.read(pushControllerProvider.notifier).register();

      expect(sentBody, isNotNull);
      expect(sentBody!['include_content'], isFalse);
    });

    test('turning the preview setting on before registering sends '
        'include_content: true', () async {
      Map<String, dynamic>? sentBody;
      _mock(
        (call) async => switch (call.method) {
          'getToken' => 'abcd1234',
          _ => null,
        },
      );
      addTearDown(() => _mock(null));

      final session = SessionStore(tokens: _tokens);
      final container = _container(
        session: session,
        httpClient: MockClient((request) async {
          if (request.method == 'PUT' && request.url.path == '/push') {
            sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          }
          return http.Response('', 204);
        }),
        channel: ApnsTokenChannel(isIOS: true),
      );
      addTearDown(container.dispose);

      await container
          .read(pushContentPreviewSettingsProvider.notifier)
          .setEnabled(true);
      await container.read(pushControllerProvider.notifier).register();

      expect(sentBody, isNotNull);
      expect(sentBody!['include_content'], isTrue);
    });

    test('flipping the setting after an initial registration reaches the '
        'server on the next register() call, not the value it started '
        'with', () async {
      final requests = <Map<String, dynamic>>[];
      _mock(
        (call) async => switch (call.method) {
          'getToken' => 'abcd1234',
          _ => null,
        },
      );
      addTearDown(() => _mock(null));

      final session = SessionStore(tokens: _tokens);
      final container = _container(
        session: session,
        httpClient: MockClient((request) async {
          if (request.method == 'PUT' && request.url.path == '/push') {
            requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          }
          return http.Response('', 204);
        }),
        channel: ApnsTokenChannel(isIOS: true),
      );
      addTearDown(container.dispose);

      await container.read(pushControllerProvider.notifier).register();
      expect(requests, hasLength(1));
      expect(requests[0]['include_content'], isFalse);

      await container
          .read(pushContentPreviewSettingsProvider.notifier)
          .setEnabled(true);
      await container.read(pushControllerProvider.notifier).register();

      expect(requests, hasLength(2));
      expect(requests[1]['include_content'], isTrue);
    });
  });
}
