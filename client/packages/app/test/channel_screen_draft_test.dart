// SPDX-License-Identifier: Apache-2.0
/// A per-channel draft survives switching away and back, even though
/// `ChannelScreen` has no key (see `channel_read_marker.dart`'s doc comment)
/// and the same `TextEditingController` is what a channel switch reuses or
/// discards, never the same channel's own words.
///
/// Mirrors `jump_to_latest_channel_switch_test.dart`'s own technique of
/// rebuilding `ChannelScreen(channelId: ...)` directly at the same tree
/// position, since that is exactly the shape a real channel switch takes.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/channel_drafts.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/sync_controller.dart';
import 'package:slimm_app/src/screens/channel_screen.dart';
import 'package:slimm_app/src/widgets/composer.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

class _NoopSyncController extends SyncController {
  _NoopSyncController(super.ref);

  @override
  Future<void> start() async {}
}

const _tokens = api.TokenPair(
  userId: 'bob',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

Map<String, dynamic> _meJson() => {
  'id': 'bob',
  'username': 'bob',
  'display_name': 'Bob',
  'created_at': 0,
  'permissions': 0,
};

http.Response _emptyJsonList() => http.Response(
  jsonEncode([]),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _sentJson(String id, String content) => {
  'id': id,
  'channel_id': 'c1',
  'author_id': 'bob',
  'author_display_name': 'Bob',
  'seq': 1,
  'content': content,
  'created_at': 1000,
  'edited_at': null,
};

class _Harness {
  _Harness({required this.container, required this.posted});

  final ProviderContainer container;
  final List<String> posted;
}

Future<_Harness> _mount(WidgetTester tester, {required String initial}) async {
  tester.view.physicalSize = const Size(500, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = SlimmDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final store = MessageStore(db);
  await store.upsertChannels([
    const api.Channel(id: 'c1', name: 'general', kind: 'text', createdAt: 0),
    const api.Channel(id: 'c2', name: 'random', kind: 'text', createdAt: 0),
  ]);

  final posted = <String>[];
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      storeProvider.overrideWith((ref) async => store),
      syncControllerProvider.overrideWith((ref) => _NoopSyncController(ref)),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            if (request.method == 'GET' && request.url.path == '/me') {
              return http.Response(
                jsonEncode(_meJson()),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.method == 'POST' &&
                request.url.path == '/channels/c1/messages') {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              posted.add(body['content'] as String);
              return http.Response(
                jsonEncode(
                  _sentJson(body['id'] as String, body['content'] as String),
                ),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.method == 'PUT' && request.url.path.endsWith('/read')) {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                jsonEncode({'last_read_seq': body['seq'], 'unread': 0}),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return _emptyJsonList();
          }),
        );
        ref.onDispose(client.close);
        return client;
      }),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(body: ChannelScreen(channelId: initial)),
      ),
    ),
  );
  await _flush(tester);

  return _Harness(container: container, posted: posted);
}

/// A bounded pump count, not `pumpAndSettle`: see `channel_screen_test.dart`
/// and `jump_to_latest_channel_switch_test.dart` for why settling never
/// returns in this environment.
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _switchTo(
  WidgetTester tester,
  ProviderContainer container,
  String channelId,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(body: ChannelScreen(channelId: channelId)),
      ),
    ),
  );
  await _flush(tester);
}

Finder get _composerField => find.descendant(
  of: find.byType(Composer),
  matching: find.byType(TextField),
);

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

void main() {
  testWidgets('typed but unsent text survives switching to another channel '
      'and back', (tester) async {
    final h = await _mount(tester, initial: 'c1');

    await tester.enterText(_composerField, 'a message for c1');
    await tester.pump();

    await _switchTo(tester, h.container, 'c2');
    expect(
      tester.widget<TextField>(_composerField).controller!.text,
      isEmpty,
      reason:
          'a channel opened for the first time must not show a draft '
          'typed in a different one',
    );

    await _switchTo(tester, h.container, 'c1');
    expect(
      tester.widget<TextField>(_composerField).controller!.text,
      'a message for c1',
      reason: 'the words typed before switching away must still be there',
    );

    await _unmount(tester);
  });

  testWidgets('sending clears the draft', (tester) async {
    final h = await _mount(tester, initial: 'c1');

    await tester.enterText(_composerField, 'send me');
    await tester.pump();
    // A round trip first, so the drafts map genuinely holds this text too.
    await _switchTo(tester, h.container, 'c2');
    await _switchTo(tester, h.container, 'c1');

    final composer = tester.widget<Composer>(find.byType(Composer));
    await composer.onSend(const <String>[]);
    await _flush(tester);

    expect(h.posted, ['send me']);
    expect(
      h.container.read(channelDraftsProvider).draftFor('c1'),
      isEmpty,
      reason: 'a sent message must not reappear as a draft on the next visit',
    );

    await _switchTo(tester, h.container, 'c2');
    await _switchTo(tester, h.container, 'c1');
    expect(tester.widget<TextField>(_composerField).controller!.text, isEmpty);

    await _unmount(tester);
  });

  testWidgets(
    'a channel torn down and reopened (rather than reusing its State) still '
    'restores its draft, because the draft lives outside ChannelScreen',
    (tester) async {
      final h = await _mount(tester, initial: 'c1');

      await tester.enterText(_composerField, 'saved on teardown');
      await tester.pump();

      // Simulates a path that destroys ChannelScreen's State outright (voice, a DM call, canvas).
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            theme: buildTheme(Brightness.light, AppTokens.light),
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      await _flush(tester);

      await _switchTo(tester, h.container, 'c1');
      expect(
        tester.widget<TextField>(_composerField).controller!.text,
        'saved on teardown',
      );

      await _unmount(tester);
    },
  );
}
