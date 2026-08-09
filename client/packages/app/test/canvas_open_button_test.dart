// SPDX-License-Identifier: Apache-2.0
/// `CanvasOpenButton` self-gates on the channel's own kind: a DM's base
/// permissions never grant `USE_CANVAS` (`store/dms.rs`'s `DM_BASE`), so the
/// button hides there rather than offering a route that always 403s. Text
/// and voice keep it, and a channel row the local store has not resolved
/// yet keeps it too - see the widget's own doc comment for why hiding by
/// default would be the wrong failure direction.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/canvas/canvas_open_button.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'bob',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  String channelId,
) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildTheme(Brightness.light, AppTokens.light),
      home: Scaffold(body: CanvasOpenButton(channelId: channelId)),
    ),
  ),
);

void main() {
  testWidgets('hides for a DM and shows for a text channel', (tester) async {
    final db = SlimmDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = MessageStore(db);
    await store.upsertChannels([
      const api.Channel(id: 'dm', name: 'Alice', kind: 'dm', createdAt: 0),
      const api.Channel(
        id: 'text',
        name: 'general',
        kind: 'text',
        createdAt: 0,
      ),
    ]);

    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
        storeProvider.overrideWith((ref) async => store),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container, 'dm');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Open canvas'), findsNothing);

    await _pump(tester, container, 'text');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Open canvas'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  });

  testWidgets('shows while the local store has not resolved the channel yet', (
    tester,
  ) async {
    final db = SlimmDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = MessageStore(db);
    // No upsertChannels: unknown to the local store, a fresh-fetch race.

    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
        storeProvider.overrideWith((ref) async => store),
      ],
    );
    addTearDown(container.dispose);

    await _pump(tester, container, 'unknown');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Open canvas'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}
