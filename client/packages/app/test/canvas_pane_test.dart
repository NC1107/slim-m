// SPDX-License-Identifier: Apache-2.0
/// The canvas pane: it fetches on open, applies live frames for its own
/// channel and nobody else's, commits a drag, and says so when the server
/// refuses rather than rendering an empty board.
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
import 'package:slimm_app/src/screens/canvas/canvas_bar.dart';
import 'package:slimm_app/src/screens/canvas/canvas_pane.dart';
import 'package:slimm_app/src/widgets/channel_header.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

class _NoopSyncController extends SyncController {
  _NoopSyncController(super.ref);

  @override
  Future<void> start() async {}
}

const _tokens = api.TokenPair(
  userId: 'me',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

Map<String, dynamic> _object(String id, {double x = 10, int seq = 1}) => {
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
  'author_id': 'me',
  'seq': seq,
  'created_at': 0,
};

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

class _Fixture {
  _Fixture({this.viewportStatus = 200, this.hasMore = false});

  final StreamController<api.ServerEvent> events =
      StreamController<api.ServerEvent>.broadcast();

  final int viewportStatus;
  final bool hasMore;
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

  ProviderContainer container() => ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      syncControllerProvider.overrideWith(_NoopSyncController.new),
      liveEventsProvider.overrideWithValue(events.stream),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/canvas/ops')) {
              opsGets++;
              // Echoes the cursor back as the latest seq, so this fixture never answers `reset` or reports a gap.
              final afterSeq = int.parse(
                request.url.queryParameters['after_seq']!,
              );
              return _json({
                'ops': <Object>[],
                'latest_seq': afterSeq,
                'has_more': false,
                'reset': false,
              });
            }
            if (!request.url.path.endsWith('/canvas/objects')) {
              return _json(<Object>[]);
            }
            if (request.method == 'POST') {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              posted.add(body);
              return http.Response(
                jsonEncode({
                  ..._object(body['id'] as String),
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
            return _json({
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

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
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

CanvasDocument _document(WidgetTester tester) {
  final surface = tester.widget<CanvasSurface>(find.byType(CanvasSurface));
  return surface.document;
}

void main() {
  testWidgets('opening the canvas fetches the region and paints it', (
    tester,
  ) async {
    final fixture = _Fixture()..objects = [_object('a'), _object('b', x: 50)];
    final container = fixture.container();
    addTearDown(container.dispose);
    addTearDown(fixture.events.close);

    await _pump(tester, container);
    expect(_document(tester).objectCount.value, 2);
  });

  testWidgets('a live frame for this channel lands, one for another does not', (
    tester,
  ) async {
    final fixture = _Fixture();
    final container = fixture.container();
    addTearDown(container.dispose);
    addTearDown(fixture.events.close);
    await _pump(tester, container);

    final document = _document(tester);
    expect(document.objectCount.value, 0);

    fixture.events
      ..add(
        api.CanvasObjectPlaced(
          channelId: 'other',
          object: api.CanvasObject.fromJson(_object('elsewhere')),
        ),
      )
      ..add(
        api.CanvasObjectPlaced(
          channelId: 'c1',
          object: api.CanvasObject.fromJson(_object('here')),
        ),
      );
    await tester.pump();
    await tester.pump();

    expect(document.objectCount.value, 1);
    expect(document.knows('here'), isTrue);
    expect(document.knows('elsewhere'), isFalse);
  });

  testWidgets('a drag commits a stroke to the server', (tester) async {
    final fixture = _Fixture();
    final container = fixture.container();
    addTearDown(container.dispose);
    addTearDown(fixture.events.close);
    await _pump(tester, container);

    final gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveTo(const Offset(160, 140));
    await gesture.moveTo(const Offset(220, 200));
    await gesture.up();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(fixture.posted, hasLength(1));
    expect(fixture.posted.single['kind'], 'stroke');
    expect(_document(tester).objectCount.value, 1);
  });

  /// The server is the authority on whether this channel has a canvas at all,
  /// and a denial must read as a denial rather than as an empty board.
  testWidgets('a forbidden read says so instead of showing a blank canvas', (
    tester,
  ) async {
    final fixture = _Fixture(viewportStatus: 403);
    final container = fixture.container();
    addTearDown(container.dispose);
    addTearDown(fixture.events.close);
    await _pump(tester, container);
    await tester.pumpAndSettle();

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(
      find.text('The canvas is not available in this channel.'),
      findsOneWidget,
    );
  });

  /// Silently dropping objects is what the strategy forbids: a truncated page
  /// has to say it was truncated.
  testWidgets('a truncated page renders a callout', (tester) async {
    final fixture = _Fixture(hasMore: true)..objects = [_object('a')];
    final container = fixture.container();
    addTearDown(container.dispose);
    addTearDown(fixture.events.close);
    await _pump(tester, container);
    await tester.pumpAndSettle();

    expect(find.byType(AppCallout), findsOneWidget);
  });

  /// Opening the canvas used to fire three requests: one against the
  /// degenerate viewport `initState` fetched before layout, and two more
  /// racing a stale read of `_fetched` inside the fetch's own repaint.
  testWidgets('opening the canvas issues exactly one viewport request', (
    tester,
  ) async {
    final fixture = _Fixture()..objects = [_object('a')];
    final container = fixture.container();
    addTearDown(container.dispose);
    addTearDown(fixture.events.close);

    await _pump(tester, container);
    // Long enough for a wrongly-scheduled debounce to fire, so this cannot pass merely because the clock never advanced far enough to expose one.
    await tester.pump(const Duration(seconds: 1));

    expect(fixture.viewportGets, 1);
  });

  /// The unbounded loop: a truncated page resets `_fetched` to null, and
  /// reading that stale null from inside the fetch's own repaint rescheduled
  /// another fetch for the same, unmoved viewport every 150ms - forever,
  /// since a still-truncated answer can never make `_fetched` non-null.
  testWidgets(
    'a truncated region does not refetch on its own once the camera settles',
    (tester) async {
      final fixture = _Fixture(hasMore: true)..objects = [_object('a')];
      final container = fixture.container();
      addTearDown(container.dispose);
      addTearDown(fixture.events.close);

      await _pump(tester, container);
      // One legitimate follow-up settles here: the truncated callout appearing shrinks CanvasSurface's own viewport, a real (if minor) size change that alone earns one refetch.
      await tester.pump(const Duration(seconds: 1));
      final settled = fixture.viewportGets;

      // Long enough that the old 150ms self-reschedule would have fired a dozen further times with the camera never moving again.
      await tester.pump(const Duration(seconds: 2));
      expect(fixture.viewportGets, settled);

      // A live frame also reaches refresh() and must not restart the loop.
      fixture.events.add(
        api.CanvasObjectPlaced(
          channelId: 'c1',
          object: api.CanvasObject.fromJson(_object('live')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.viewportGets, settled);
    },
  );

  /// The reachability guard. The canvas has no route, so nothing generic can
  /// see it: this is what fails if the header's affordance is ever dropped and
  /// the feature quietly becomes unreachable again.
  testWidgets('the channel header opens the canvas', (tester) async {
    final fixture = _Fixture();
    final container = fixture.container();
    addTearDown(container.dispose);
    addTearDown(fixture.events.close);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark, AppTokens.dark),
          home: const Scaffold(
            body: ChannelHeader(
              channelId: 'c1',
              name: 'general',
              isVoice: false,
              searchOpen: false,
              onToggleSearch: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(container.read(canvasOpenProvider), isNull);
    await tester.tap(find.bySemanticsLabel('Open canvas'));
    await tester.pump();
    expect(container.read(canvasOpenProvider), 'c1');
  });

  /// CanvasBar is the pane's only header (no AppBar sits above it), so
  /// nothing else consumes the notch or the home indicator for it.
  testWidgets(
    'the bar and the drawing surface clear the notch and home indicator',
    (tester) async {
      const topInset = 59.0;
      const bottomInset = 34.0;
      const dpr = 3.0;
      const viewHeight = 932.0;
      final fixture = _Fixture();
      final container = fixture.container();
      addTearDown(container.dispose);
      addTearDown(fixture.events.close);

      tester.view.physicalSize = const Size(390 * dpr, viewHeight * dpr);
      tester.view.devicePixelRatio = dpr;
      tester.view.padding = FakeViewPadding(
        top: topInset * dpr,
        bottom: bottomInset * dpr,
      );
      tester.view.viewPadding = FakeViewPadding(
        top: topInset * dpr,
        bottom: bottomInset * dpr,
      );
      addTearDown(tester.view.reset);

      await _pump(tester, container);

      expect(
        tester.getTopLeft(find.byType(CanvasBar)).dy,
        greaterThanOrEqualTo(topInset),
        reason: 'the bar painted under the status bar before this',
      );
      expect(
        tester.getBottomLeft(find.byType(CanvasSurface)).dy,
        lessThanOrEqualTo(viewHeight - bottomInset),
        reason: 'a stroke could start under the home indicator before this',
      );
    },
  );
}

void _noop() {}
