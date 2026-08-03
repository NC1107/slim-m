// SPDX-License-Identifier: Apache-2.0
/// `SpaceConnectionDot`, the header indicator that replaced the profile
/// footer's own override of a person's presence with the socket's state
/// (owner request, 2026-08-03). Split out of `channel_rail_test.dart`, which
/// is already at its line budget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/sync_controller.dart';
import 'package:slimm_app/src/widgets/channel_rail_frame.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// Stands in for the real [SyncController]; see `channel_rail_test.dart`'s
/// own copy of this same shape for why overriding `start` is enough.
class _StubSyncController extends SyncController {
  _StubSyncController(super.ref, SyncStatus status) {
    state = status;
  }

  @override
  Future<void> start() async {}
}

ProviderContainer _setup(SyncStatus status) => ProviderContainer(
  overrides: [
    keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
    sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
    syncControllerProvider.overrideWith(
      (ref) => _StubSyncController(ref, status),
    ),
    apiProvider.overrideWith((ref) {
      final client = api.SlimmApi(
        baseUrl: Uri.parse('http://localhost:8080'),
        session: ref.watch(sessionProvider),
        httpClient: MockClient(
          (request) async =>
              http.Response('{}', 404, headers: {'content-type': 'json'}),
        ),
      );
      ref.onDispose(client.close);
      return client;
    }),
  ],
);

Future<void> _pumpHeader(WidgetTester tester, ProviderContainer container) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const Scaffold(body: Column(children: [RailHeader()])),
      ),
    ),
  );
}

AppStatusShape _shapeIn(WidgetTester tester) {
  final painter = tester
      .widget<CustomPaint>(
        find.descendant(
          of: find.byType(SpaceConnectionDot),
          matching: find.byType(CustomPaint),
        ),
      )
      .painter;
  return (painter! as AppStatusDotPainter).shape;
}

void main() {
  testWidgets(
    'each connection state has its own shape, not just its own colour',
    (tester) async {
      // One container, status mutated in place: a fresh one per status left a timer pending.
      final setup = _setup(SyncStatus.live);
      addTearDown(setup.dispose);
      final controller = setup.read(syncControllerProvider.notifier);
      await _pumpHeader(tester, setup);
      await tester.pumpAndSettle();

      final shapes = <SyncStatus, AppStatusShape>{};
      for (final status in SyncStatus.values) {
        controller.state = status;
        await tester.pump();
        shapes[status] = _shapeIn(tester);
      }

      expect(
        shapes.values.toSet(),
        hasLength(SyncStatus.values.length),
        reason:
            'colour alone must never carry connection state, the same '
            'invariant AppStatusDot already holds for presence',
      );
    },
  );

  testWidgets('names the connection, never a person\'s presence', (
    tester,
  ) async {
    final setup = _setup(SyncStatus.offline);
    addTearDown(setup.dispose);
    await _pumpHeader(tester, setup);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Offline, retrying'), findsOneWidget);
    // AppStatusDot's own baked-in label would instead say "Offline" here.
    expect(find.bySemanticsLabel('Offline'), findsNothing);
  });
}
