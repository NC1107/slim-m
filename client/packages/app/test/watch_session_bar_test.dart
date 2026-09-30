// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The room's watch position on the call surface: read from REST alone,
/// advanced by the clock while playing, corrected by a tick, and gone when the
/// bot stops ticking. See
/// docs/decisions/0050-watch-party-sync-authority-and-direct-play.md.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/live_events.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/watch_room.dart';
import 'package:slimm_app/src/widgets/watch_session_bar.dart';
import 'package:slimm_design_system/design_system.dart';

final _start = DateTime.utc(2026, 9, 30, 20);

Map<String, Object?> _session({bool playing = true, int position = 5025000}) =>
    {
      'channel_id': 'call-1',
      'bot_user_id': 'jelly',
      'item_id': 'item-1',
      'title': 'A Film',
      'duration_ms': 7200000,
      'playing': playing,
      'position_ms': position,
      'sampled_at_ms': 10000,
      'epoch': 1,
      'controller_user_id': null,
      'server_time_ms': 12000,
    };

class _Rig {
  _Rig(this.events);

  final StreamController<api.ServerEvent> events;
  int reads = 0;
}

Future<_Rig> _pump(
  WidgetTester tester, {
  required Map<String, Object?>? session,
  double width = 360,
}) async {
  final events = StreamController<api.ServerEvent>.broadcast();
  addTearDown(events.close);
  var clock = _start;
  final rig = _Rig(events);
  final container = ProviderContainer(
    overrides: [
      liveEventsProvider.overrideWithValue(events.stream),
      watchClockProvider.overrideWithValue(() => clock),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: api.SessionStore(
            tokens: const api.TokenPair(
              userId: 'u1',
              accessToken: 'a',
              refreshToken: 'r',
              accessExpiresAt: 4102444800000,
            ),
          ),
          httpClient: MockClient((http.Request request) async {
            rig.reads++;
            return http.Response(
              jsonEncode(session ?? {'error': 'no watch session'}),
              session == null ? 404 : 200,
              headers: {'content-type': 'application/json'},
            );
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
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: const WatchSessionBar(channelId: 'call-1'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  _advance = (d) => clock = clock.add(d);
  return rig;
}

late DateTime Function(Duration) _advance;

void main() {
  test('formatWatchTime shows hours only when there are some', () {
    expect(formatWatchTime(const Duration(seconds: 7)), '0:07');
    expect(formatWatchTime(const Duration(minutes: 3, seconds: 7)), '3:07');
    expect(
      formatWatchTime(const Duration(hours: 1, minutes: 23, seconds: 45)),
      '1:23:45',
    );
  });

  testWidgets('a joiner reads the room position from REST alone', (
    tester,
  ) async {
    await _pump(tester, session: _session());
    expect(find.text('A Film'), findsOneWidget);
    // 5025s sampled 2s before the read, playing: 1:23:47 of 2:00:00.
    expect(find.text('1:23:47 / 2:00:00'), findsOneWidget);
    expect(find.byIcon(AppIcons.play), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Watching A Film, playing')),
      findsOneWidget,
    );
  });

  testWidgets('a paused room holds its position and says so', (tester) async {
    await _pump(tester, session: _session(playing: false));
    expect(find.text('1:23:45 / 2:00:00'), findsOneWidget);
    expect(find.byIcon(AppIcons.pause), findsOneWidget);
  });

  testWidgets('nothing is drawn when nothing is playing', (tester) async {
    await _pump(tester, session: null);
    expect(find.text('A Film'), findsNothing);
    expect(find.byType(Container), findsNothing);
  });

  testWidgets('a tick moves the readout and a pause freezes it', (
    tester,
  ) async {
    final rig = await _pump(tester, session: _session());
    rig.events.add(
      const api.WatchTick(
        channelId: 'call-1',
        itemId: 'item-1',
        playing: false,
        positionMs: 6000000,
        sampledAtMs: 1,
        epoch: 1,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('1:40:00 / 2:00:00'), findsOneWidget);
    expect(find.byIcon(AppIcons.pause), findsOneWidget);
    expect(rig.reads, 1, reason: 'same epoch needs no re-read');
  });

  testWidgets('a new epoch re-reads the session for the new title', (
    tester,
  ) async {
    final rig = await _pump(tester, session: _session());
    rig.events.add(
      const api.WatchTick(
        channelId: 'call-1',
        itemId: 'item-1',
        playing: true,
        positionMs: 1000,
        sampledAtMs: 1,
        epoch: 2,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(rig.reads, 2);
  });

  testWidgets('a room that stopped ticking is treated as over', (tester) async {
    await _pump(tester, session: _session());
    _advance(watchRoomStaleAfter + const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('A Film'), findsNothing);
  });

  testWidgets('a phone width ellipsizes the title instead of overflowing', (
    tester,
  ) async {
    await _pump(tester, session: _session()..['title'] = 'T' * 200, width: 280);
    expect(tester.takeException(), isNull);
  });
}
