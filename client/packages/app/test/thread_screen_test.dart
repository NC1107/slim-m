// SPDX-License-Identifier: Apache-2.0
/// Regression test for the stacked-header bug: `ThreadScreen` wraps
/// `ChannelScreen` in its own `AppBar`, and `ChannelScreen` used to build a
/// second `ChannelHeader` underneath it at any width that shows both panes -
/// two bars where there should be one. Covers both layouts, since the same
/// wrapper drives compact and expanded and only expanded was reported.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/channel_search_controller.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/sync_controller.dart';
import 'package:slimm_app/src/screens/thread_screen.dart';
import 'package:slimm_app/src/widgets/channel_header.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

/// See `channel_screen_test.dart`'s own copy for why: the real
/// `SyncController` opens a websocket to a server that does not exist here.
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

/// Pumps a [ThreadScreen] for channel `c1`, a thread (`parentMessageId` set),
/// reached by pushing it over a marker screen so the back button has
/// somewhere real to return to - the same shape a "Reply in thread" push
/// produces in the app. Returns the container so a test can read provider
/// state the widget tree itself does not surface, e.g. that a control kept
/// in the header acted on the thread's own channel id and nothing else.
Future<ProviderContainer> _pumpThread(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final db = SlimmDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final store = MessageStore(db);
  await store.upsertChannels([
    const api.Channel(
      id: 'c1',
      name: '',
      kind: 'text',
      createdAt: 0,
      parentMessageId: 'parent-1',
    ),
  ]);

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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ThreadScreen(channelId: 'c1'),
                  ),
                ),
                child: const Text('open thread'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open thread'));
  // A bounded pump count, not pumpAndSettle: AppIconButton's ripple keeps requesting a frame.
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return container;
}

/// Unmounts before the framework's own teardown does: `ChannelScreen`'s
/// `StreamBuilder`s cancel their drift query streams on dispose, and drift
/// defers that cleanup by one event loop turn on a zero-duration `Timer`,
/// which the "no pending timers" check would otherwise catch as a false
/// failure unrelated to what the test covers.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

void main() {
  for (final entry in {
    'compact': const Size(500, 800),
    'expanded': const Size(1400, 900),
  }.entries) {
    testWidgets('a thread shows exactly one header, at ${entry.key} width', (
      tester,
    ) async {
      await _pumpThread(tester, entry.value);

      expect(
        find.byType(ChannelHeader),
        findsNothing,
        reason:
            'ChannelScreen must not build its own header for a thread '
            "channel; ThreadScreen's AppBar is the only one",
      );
      expect(
        find.text('Thread'),
        findsOneWidget,
        reason: 'exactly one bar, carrying exactly one title',
      );

      await _settle(tester);
    });

    testWidgets(
      'a thread header has a working back affordance, at ${entry.key} width',
      (tester) async {
        await _pumpThread(tester, entry.value);

        final back = find.byTooltip('Back to the conversation');
        expect(back, findsOneWidget);
        await tester.tap(back);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(
          find.text('open thread'),
          findsOneWidget,
          reason:
              'tapping back must return to the screen the thread opened '
              'from',
        );

        await _settle(tester);
      },
    );

    testWidgets(
      'a thread header carries only the back affordance, the title, and '
      'search, at ${entry.key} width',
      (tester) async {
        await _pumpThread(tester, entry.value);

        expect(
          find.bySemanticsLabel('Pinned messages'),
          findsNothing,
          reason:
              'a thread has no browsing surface for a pinned set to be '
              'rediscovered later; pin is not inherited from the channel '
              'header',
        );
        expect(
          find.bySemanticsLabel('Open canvas'),
          findsNothing,
          reason:
              'a canvas button inside a thread was flagged as an unwanted '
              'surface by the 2026-08-02 security review',
        );
        expect(
          find.bySemanticsLabel('Toggle member list'),
          findsNothing,
          reason:
              'this toggle drives a global memberPaneVisibleProvider that '
              "HomeShell reads for the parent channel underneath, not the "
              'thread - the reported bug of a thread control acting on the '
              'channel behind it',
        );
        expect(
          find.bySemanticsLabel('Toggle channel list'),
          findsNothing,
          reason:
              'the same global-state shape as the member toggle, over '
              'channelRailVisibleProvider',
        );
        expect(
          find.bySemanticsLabel('Call'),
          findsNothing,
          reason: 'a thread is not a DM call surface',
        );
        expect(
          find.bySemanticsLabel('Search messages'),
          findsOneWidget,
          reason: "search is the one action a thread's header keeps",
        );

        await _settle(tester);
      },
    );

    testWidgets(
      'a thread header search acts on the thread, never the parent channel, '
      'at ${entry.key} width',
      (tester) async {
        final container = await _pumpThread(tester, entry.value);

        await tester.tap(find.bySemanticsLabel('Search messages'));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }

        expect(
          container.read(channelSearchProvider('c1')).open,
          isTrue,
          reason: "the thread's own search state must open",
        );
        expect(
          container.read(channelSearchProvider('parent-channel')).open,
          isFalse,
          reason:
              'channelSearchProvider is keyed per channel id, so opening '
              "search in the thread must not touch the parent channel's "
              'copy of the same provider',
        );

        await _settle(tester);
      },
    );
  }

  testWidgets(
    'the thread app bar carries a bottom border, as the phone one does',
    (tester) async {
      await _pumpThread(tester, const Size(900, 700));

      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(
        bar.shape,
        isA<Border>(),
        reason:
            'this bar shares surfaceBase with the transcript at zero elevation, '
            'so without a border there is no boundary between the two',
      );

      await _settle(tester);
    },
  );
}
