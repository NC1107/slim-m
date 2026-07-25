// SPDX-License-Identifier: Apache-2.0
/// Tests for push registration: gated on a session, tracked as an honest
/// status rather than swallowed silence, and retried on resume and on a
/// session already signed in when the controller is created (a restored
/// session never passes through the sign-in screen that would otherwise
/// have kicked it off).
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

/// A container wired the way the app is: a real session and key store, with
/// only the network and the native push channel swapped for test doubles.
ProviderContainer _container({
  required http.Client httpClient,
  SessionStore? session,
  ApnsTokenChannel? channel,
}) {
  return ProviderContainer(overrides: [
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
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushController.register', () {
    test('without a session, nothing is attempted', () async {
      // The default sessionProvider starts signed out; nothing is overridden,
      // so a real network call or a real MethodChannel round-trip would both
      // be surfaced failures, proving the session check runs before either.
      final container = _container(
        httpClient: MockClient((_) async => http.Response('unused', 500)),
      );
      addTearDown(container.dispose);

      await container.read(pushControllerProvider.notifier).register();
      expect(container.read(pushControllerProvider), PushStatus.notSignedIn);
    });

    test('a server failure never propagates out of register()', () async {
      _mock((call) async => switch (call.method) {
            'getToken' => 'abcd1234',
            _ => null,
          });
      addTearDown(() => _mock(null));

      final session = SessionStore(tokens: _tokens);
      final container = _container(
        session: session,
        httpClient: MockClient((_) async => http.Response('busy', 503)),
        channel: ApnsTokenChannel(isIOS: true),
      );
      addTearDown(container.dispose);

      // No expectLater/throwsA here on purpose: the assertion is that this
      // completes at all.
      await container.read(pushControllerProvider.notifier).register();
      expect(container.read(pushControllerProvider), PushStatus.serverError);
    });
  });

  group('push status transitions', () {
    test('unsupported platform is reported, not a silent no-token', () async {
      final session = SessionStore(tokens: _tokens);
      final container = _container(
        session: session,
        httpClient: MockClient((_) async => http.Response('unused', 500)),
        channel: ApnsTokenChannel(isIOS: false),
      );
      addTearDown(container.dispose);

      await container.read(pushControllerProvider.notifier).register();
      expect(
        container.read(pushControllerProvider),
        PushStatus.unsupportedPlatform,
      );
    });

    test('no answer at all is reported as still waiting, not a silent no-op',
        () async {
      // No mock handler is installed, so the channel throws
      // MissingPluginException exactly as a genuine timeout would eventually
      // resolve, without this test having to wait one out.
      _mock(null);
      final session = SessionStore(tokens: _tokens);
      final container = _container(
        session: session,
        httpClient: MockClient((_) async => http.Response('unused', 500)),
        channel: ApnsTokenChannel(isIOS: true),
      );
      addTearDown(container.dispose);

      await container.read(pushControllerProvider.notifier).register();
      expect(container.read(pushControllerProvider), PushStatus.noTokenYet);
    });

    test('a native registration failure is reported, not swallowed', () async {
      _mock((call) async => switch (call.method) {
            'getRegistrationError' => 'denied',
            _ => null,
          });
      addTearDown(() => _mock(null));

      final session = SessionStore(tokens: _tokens);
      final container = _container(
        session: session,
        httpClient: MockClient((_) async => http.Response('unused', 500)),
        channel: ApnsTokenChannel(isIOS: true),
      );
      addTearDown(container.dispose);

      await container.read(pushControllerProvider.notifier).register();
      expect(
        container.read(pushControllerProvider),
        PushStatus.registrationFailed,
      );
    });

    test('a token accepted by the server ends up registered', () async {
      _mock((call) async => switch (call.method) {
            'getToken' => 'abcd1234',
            _ => null,
          });
      addTearDown(() => _mock(null));

      final session = SessionStore(tokens: _tokens);
      final container = _container(
        session: session,
        httpClient: MockClient((_) async => http.Response('', 204)),
        channel: ApnsTokenChannel(isIOS: true),
      );
      addTearDown(container.dispose);

      await container.read(pushControllerProvider.notifier).register();
      expect(container.read(pushControllerProvider), PushStatus.registered);
    });

    test(
        'a session already signed in when the controller is created '
        'registers without an explicit call', () async {
      // Stands in for a session restored on launch: nothing on the sign-in
      // screen ever ran, so the only thing that can start registration is the
      // controller noticing it was constructed already signed in.
      _mock((call) async => switch (call.method) {
            'getToken' => 'abcd1234',
            _ => null,
          });
      addTearDown(() => _mock(null));

      final session = SessionStore(tokens: _tokens);
      final container = _container(
        session: session,
        httpClient: MockClient((_) async => http.Response('', 204)),
        channel: ApnsTokenChannel(isIOS: true),
      );
      addTearDown(container.dispose);

      // Touching the provider is what constructs the controller; nothing
      // else here calls register() at all.
      container.read(pushControllerProvider.notifier);
      await pumpEventQueue();

      expect(container.read(pushControllerProvider), PushStatus.registered);
    });

    test('resuming retries when not yet registered', () async {
      _mock(null);
      final session = SessionStore(tokens: _tokens);
      final container = _container(
        session: session,
        httpClient: MockClient((_) async => http.Response('', 204)),
        channel: ApnsTokenChannel(isIOS: true),
      );
      addTearDown(container.dispose);

      // No handler yet, so the first attempt lands on "still waiting".
      final controller = container.read(pushControllerProvider.notifier);
      await controller.register();
      expect(container.read(pushControllerProvider), PushStatus.noTokenYet);

      // The token arrives before the next attempt, the way a slow permission
      // prompt resolves while the app sits backgrounded.
      _mock((call) async => switch (call.method) {
            'getToken' => 'abcd1234',
            _ => null,
          });
      addTearDown(() => _mock(null));

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(container.read(pushControllerProvider), PushStatus.registered);
    });

    test('resuming does not retry once already registered', () async {
      var registerPushCalls = 0;
      _mock((call) async => switch (call.method) {
            'getToken' => 'abcd1234',
            _ => null,
          });
      addTearDown(() => _mock(null));

      // Starts signed out, so touching the notifier below does not also fire
      // the constructor's own already-signed-in registration attempt
      // alongside this test's: signing in afterwards is the single, clean
      // trigger this test counts against.
      final session = SessionStore();
      final container = _container(
        session: session,
        httpClient: MockClient((request) async {
          if (request.method == 'PUT' && request.url.path == '/push') {
            registerPushCalls++;
          }
          return http.Response('', 204);
        }),
        channel: ApnsTokenChannel(isIOS: true),
      );
      addTearDown(container.dispose);

      final controller = container.read(pushControllerProvider.notifier);
      session.set(_tokens);
      await pumpEventQueue();
      expect(container.read(pushControllerProvider), PushStatus.registered);
      expect(registerPushCalls, 1);

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();

      // Already registered, so resuming must not re-hit the server.
      expect(registerPushCalls, 1);
    });

    test('signing out resets status to notSignedIn', () async {
      _mock((call) async => switch (call.method) {
            'getToken' => 'abcd1234',
            _ => null,
          });
      addTearDown(() => _mock(null));

      final session = SessionStore(tokens: _tokens);
      final container = _container(
        session: session,
        httpClient: MockClient((_) async => http.Response('', 204)),
        channel: ApnsTokenChannel(isIOS: true),
      );
      addTearDown(container.dispose);

      await container.read(pushControllerProvider.notifier).register();
      expect(container.read(pushControllerProvider), PushStatus.registered);

      session.clear();
      await pumpEventQueue();

      expect(container.read(pushControllerProvider), PushStatus.notSignedIn);
    });

    test(
        'a routine token rotation does not re-run registration: only the '
        'signed-out/signed-in edge does', () async {
      var getTokenCalls = 0;
      _mock((call) async => switch (call.method) {
            'getToken' => () {
                getTokenCalls++;
                return 'abcd1234';
              }(),
            _ => null,
          });
      addTearDown(() => _mock(null));

      final session = SessionStore(tokens: _tokens);
      final container = _container(
        session: session,
        httpClient: MockClient((_) async => http.Response('', 204)),
        channel: ApnsTokenChannel(isIOS: true),
      );
      addTearDown(container.dispose);

      await container.read(pushControllerProvider.notifier).register();
      expect(container.read(pushControllerProvider), PushStatus.registered);
      expect(getTokenCalls, 1);

      // The server rotates access tokens well inside a live session, not
      // just at sign-in and sign-out; a non-null token pair replacing another
      // non-null one is that same rotation, not a new sign-in.
      session.set(const TokenPair(
        userId: 'user-1',
        accessToken: 'access-2',
        refreshToken: 'refresh-2',
        accessExpiresAt: 0,
      ));
      await pumpEventQueue();

      expect(getTokenCalls, 1,
          reason: 'a token rotation is not a sign-in edge; it must not '
              'restart APNs registration');
    });

    test(
        'two concurrent register() calls share one attempt, not two racing '
        'to register a keypair', () async {
      var registerPushCalls = 0;
      _mock((call) async => switch (call.method) {
            'getToken' => 'abcd1234',
            _ => null,
          });
      addTearDown(() => _mock(null));

      // Already signed in at construction, so touching the notifier below
      // also fires the constructor's own already-signed-in attempt: a third,
      // uncoordinated caller alongside the two explicit ones.
      final session = SessionStore(tokens: _tokens);
      final container = _container(
        session: session,
        httpClient: MockClient((request) async {
          if (request.method == 'PUT' && request.url.path == '/push') {
            registerPushCalls++;
          }
          return http.Response('', 204);
        }),
        channel: ApnsTokenChannel(isIOS: true),
      );
      addTearDown(container.dispose);

      final controller = container.read(pushControllerProvider.notifier);
      final first = controller.register();
      final second = controller.register();
      await Future.wait([first, second]);
      await pumpEventQueue();

      expect(registerPushCalls, 1,
          reason: 'two concurrent first registrations can each mint their '
              'own device keypair and race to tell the server which is '
              'current, leaving the loser\'s private half discarded locally '
              'while the server still holds its public half');
    });
  });

  group('PushController.unregister', () {
    test(
        'a key-store failure while dropping the push key still completes '
        'and reaches notSignedIn, rather than aborting sign-out mid-way',
        () async {
      final session = SessionStore(tokens: _tokens);
      final container = ProviderContainer(overrides: [
        keyStoreProvider.overrideWithValue(_DeleteFailingKeyStore()),
        sessionProvider.overrideWithValue(session),
        apiProvider.overrideWith((ref) {
          final api = SlimmApi(
            baseUrl: Uri.parse('http://localhost:8080'),
            session: ref.watch(sessionProvider),
            httpClient: MockClient((_) async => http.Response('', 204)),
          );
          ref.onDispose(api.close);
          return api;
        }),
      ]);
      addTearDown(container.dispose);

      final controller = container.read(pushControllerProvider.notifier);
      // main.dart's sign-out sequence has no try/catch around this call:
      // unregister() itself must never throw.
      await expectLater(controller.unregister(), completes);
      expect(container.read(pushControllerProvider), PushStatus.notSignedIn);
    });
  });
}

/// A key store whose [delete] always fails, standing in for a storage-layer
/// failure partway through sign-out.
class _DeleteFailingKeyStore implements KeyStore {
  final _inner = InMemoryKeyStore();

  @override
  Future<KeyHandle> put(String name, String secret) => _inner.put(name, secret);

  @override
  Future<String?> read(KeyHandle handle) => _inner.read(handle);

  @override
  Future<void> delete(KeyHandle handle) async =>
      throw StateError('key store unavailable');

  @override
  Future<void> clear() => _inner.clear();

  @override
  Future<List<int>> sign(KeyHandle handle, List<int> payload) =>
      _inner.sign(handle, payload);
}
