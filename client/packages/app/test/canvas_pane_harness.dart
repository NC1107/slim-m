// SPDX-License-Identifier: Apache-2.0
/// Shared fixtures for the two suites that pump a [CanvasPane]: its fetch,
/// live-frame and drag behaviour (`canvas_pane_test.dart`) and its erase,
/// undo and clear controls (`canvas_pane_ops_test.dart`).
///
/// Not a `_test.dart` file, so `flutter test` does not try to run it. It
/// exists because both suites need the same fake canvas API, the same
/// signed-in session and the same way to pump the pane, none of which
/// either suite is actually about.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/live_events.dart';
import 'package:slimm_app/src/providers/sync_controller.dart';
import 'package:slimm_app/src/screens/canvas/canvas_pane.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

class NoopSyncController extends SyncController {
  NoopSyncController(super.ref);

  @override
  Future<void> start() async {}
}

const testTokens = api.TokenPair(
  userId: 'me',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

Map<String, dynamic> canvasObjectJson(
  String id, {
  double x = 10,
  int seq = 1,
  String authorId = 'me',
}) => {
  'id': id,
  'kind': 'stroke',
  'z_index': seq,
  'x': x,
  'y': 10.0,
  'w': 20.0,
  'h': 20.0,
  'props': {
    'points': [0.0, 0.0, 20.0, 20.0],
    'width': 3.0,
    'color': 'annotation',
  },
  'author_id': authorId,
  'seq': seq,
  'created_at': 0,
};

http.Response jsonResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

class CanvasPaneFixture {
  CanvasPaneFixture({
    this.viewportStatus = 200,
    this.hasMore = false,
    this.mePermissions = 0,
  });

  final StreamController<api.ServerEvent> events =
      StreamController<api.ServerEvent>.broadcast();

  final int viewportStatus;
  final bool hasMore;

  /// The signed-in member's own permission bitmask, as `GET /me` answers it.
  final int mePermissions;
  final List<Map<String, dynamic>> posted = [];
  List<Map<String, dynamic>> objects = [];

  /// Every `GET .../canvas/objects` the pane sent, in order. A count rather
  /// than a bare int so a test can tell "one, twice as many as needed" from
  /// "the same fetch racing itself and never stopping".
  int viewportGets = 0;

  /// Every `GET .../canvas/ops` the pane sent: every viewport fetch runs a
  /// catch-up afterward, so this file's own tests only need the default
  /// answer below to keep paging correct - it is not itself under test here.
  int opsGets = 0;

  /// Every `POST .../canvas/ops` (remove, clear, restore) the pane sent.
  final List<Map<String, dynamic>> postedOps = [];
  var _opSeq = 0;

  ProviderContainer container() => ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: testTokens)),
      syncControllerProvider.overrideWith(NoopSyncController.new),
      liveEventsProvider.overrideWithValue(events.stream),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/me')) {
              return jsonResponse({
                'id': 'me',
                'username': 'me',
                'display_name': 'Me',
                'created_at': 0,
                'permissions': mePermissions,
              });
            }
            if (request.url.path.endsWith('/canvas/ops') &&
                request.method == 'POST') {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              postedOps.add(body);
              _opSeq++;
              return http.Response(
                jsonEncode({
                  'op': {
                    'id': 'server-op-$_opSeq',
                    'seq': _opSeq,
                    'kind': body['kind'],
                    'affected': 1,
                    'created_at': 0,
                  },
                  'fresh': true,
                }),
                201,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path.endsWith('/canvas/ops')) {
              opsGets++;
              // Echoes the cursor back as the latest seq, so this fixture never answers `reset` or reports a gap.
              final afterSeq = int.parse(
                request.url.queryParameters['after_seq']!,
              );
              return jsonResponse({
                'ops': <Object>[],
                'latest_seq': afterSeq,
                'has_more': false,
                'reset': false,
              });
            }
            if (!request.url.path.endsWith('/canvas/objects')) {
              return jsonResponse(<Object>[]);
            }
            if (request.method == 'POST') {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              posted.add(body);
              return http.Response(
                jsonEncode({
                  ...canvasObjectJson(body['id'] as String),
                  'x': body['x'],
                  'y': body['y'],
                  'w': body['w'],
                  'h': body['h'],
                  'props': body['props'],
                }),
                201,
                headers: {'content-type': 'application/json'},
              );
            }
            viewportGets++;
            if (viewportStatus != 200) {
              return http.Response(
                jsonEncode({'error': 'no'}),
                viewportStatus,
                headers: {'content-type': 'application/json'},
              );
            }
            return jsonResponse({
              'objects': objects,
              'has_more': hasMore,
              'latest_seq': objects.length,
            });
          }),
        );
        ref.onDispose(client.close);
        return client;
      }),
    ],
  );
}

Future<void> pumpCanvasPane(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        home: const Scaffold(body: CanvasPane(channelId: 'c1')),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

CanvasDocument surfaceDocument(WidgetTester tester) {
  final surface = tester.widget<CanvasSurface>(find.byType(CanvasSurface));
  return surface.document;
}

/// The screen point for a [world] coordinate, given the surface's default
/// camera (`Camera(x: 0, y: 0, zoom: 1)`, which nothing in either suite
/// moves): world and local surface coordinates coincide, so this only has
/// to add the surface's own on-screen origin.
Offset screenFor(WidgetTester tester, Offset world) =>
    tester.getTopLeft(find.byType(CanvasSurface)) + world;
