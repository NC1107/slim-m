// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The desktop live-message notifier turns an incoming socket message into an
/// OS notification, but only for someone else's message that arrives while the
/// window is not in the foreground. Own messages, a focused window, and a
/// muted channel are each silent; the mute half leans on [isMuted]'s own
/// coverage and is exercised here through the real overrides controller.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/channel_notification_overrides_controller.dart';
import 'package:slimm_app/src/providers/desktop_message_notifier.dart';
import 'package:slimm_app/src/providers/live_events.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/push_controller.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_platform/platform.dart';

class _FakeNotifications implements LocalNotifications {
  final shown = <String>[];

  @override
  Future<void> show(String text, {required LocalAlertChannel channel}) async =>
      shown.add(text);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _tokens = api.TokenPair(
  userId: 'me',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

api.Message _message({
  required String id,
  required String authorId,
  String? authorDisplayName,
  required String channelId,
}) => api.Message(
  id: id,
  channelId: channelId,
  authorId: authorId,
  authorDisplayName: authorDisplayName ?? authorId,
  seq: 1,
  content: 'hi',
  createdAt: 0,
  editedAt: null,
);

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

class _Setup {
  _Setup(this.container, this.events, this.notifications, this.db);

  final ProviderContainer container;
  final StreamController<api.ServerEvent> events;
  final _FakeNotifications notifications;
  final SlimmDatabase db;

  Future<void> dispose() async {
    container.dispose();
    await events.close();
    await db.close();
  }
}

Future<_Setup> _wire() async {
  final db = SlimmDatabase(NativeDatabase.memory());
  final store = MessageStore(db);
  await store.upsertChannels([
    const api.Channel(
      id: 'group-1',
      name: 'general',
      kind: 'text',
      createdAt: 0,
    ),
  ]);

  final events = StreamController<api.ServerEvent>.broadcast();
  final notifications = _FakeNotifications();

  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      storeProvider.overrideWith((ref) async => store),
      liveEventsProvider.overrideWithValue(events.stream),
      localNotificationsProvider.overrideWithValue(notifications),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            if (request.url.path.startsWith(
                  '/notification-preferences/channels/',
                ) &&
                request.method == 'PUT') {
              final channelId = request.url.pathSegments.last;
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              return _json({
                'channel_id': channelId,
                'preference': body['preference'],
              });
            }
            return _json(const <Object>[]);
          }),
        );
        ref.onDispose(client.close);
        return client;
      }),
    ],
  );
  await container.read(channelNotificationOverridesProvider.notifier).refresh();
  container.read(desktopMessageNotifierProvider);

  return _Setup(container, events, notifications, db);
}

Future<void> _settle(_Setup setup) async {
  setup.events.add(
    api.MessageCreated(
      _message(id: 'flush', authorId: 'me', channelId: 'group-1'),
    ),
  );
  await Future<void>.delayed(Duration.zero);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('backgrounded, another author: shows a named notification', () async {
    if (!isDesktopHost) return;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final setup = await _wire();

    setup.events.add(
      api.MessageCreated(
        _message(
          id: 'm1',
          authorId: 'alice',
          authorDisplayName: 'Alice',
          channelId: 'group-1',
        ),
      ),
    );
    await _settle(setup);

    expect(setup.notifications.shown, ['New message from Alice']);
    await setup.dispose();
  });

  test('own message is never notified back to me', () async {
    if (!isDesktopHost) return;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final setup = await _wire();

    setup.events.add(
      api.MessageCreated(
        _message(id: 'm1', authorId: 'me', channelId: 'group-1'),
      ),
    );
    await _settle(setup);

    expect(setup.notifications.shown, isEmpty);
    await setup.dispose();
  });

  test('a focused window shows nothing', () async {
    if (!isDesktopHost) return;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final setup = await _wire();

    setup.events.add(
      api.MessageCreated(
        _message(id: 'm1', authorId: 'alice', channelId: 'group-1'),
      ),
    );
    await _settle(setup);

    expect(setup.notifications.shown, isEmpty);
    await setup.dispose();
  });

  test('a muted channel stays silent', () async {
    if (!isDesktopHost) return;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final setup = await _wire();
    await setup.container
        .read(channelNotificationOverridesProvider.notifier)
        .mute('group-1');

    setup.events.add(
      api.MessageCreated(
        _message(id: 'm1', authorId: 'alice', channelId: 'group-1'),
      ),
    );
    await _settle(setup);

    expect(setup.notifications.shown, isEmpty);
    await setup.dispose();
  });
}
