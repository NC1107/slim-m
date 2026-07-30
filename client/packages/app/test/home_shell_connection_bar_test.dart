// SPDX-License-Identifier: Apache-2.0
/// `RailConnectionBar` lived only inside `ChannelRail`, which a compact
/// layout with a channel open never mounts, so the one route a phone user
/// spends all their time on never reported the socket dropping.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/sync_controller.dart';
import 'package:slimm_app/src/widgets/channel_rail_frame.dart';
import 'package:slimm_design_system/design_system.dart';

import 'ui_snapshot_support.dart';

/// Stands in for the real [SyncController]: `start` opens a websocket to a
/// server that is not there, so it is overridden to a no-op, and [status]
/// fixes the value the bar reads.
class _FixedSyncController extends SyncController {
  _FixedSyncController(super.ref, SyncStatus status) {
    state = status;
  }

  @override
  Future<void> start() async {}
}

Future<void> _expectOffline(WidgetTester tester, Size size) async {
  final fixture = await fixtureContainer(
    extraOverrides: [
      syncControllerProvider.overrideWith(
        (ref) => _FixedSyncController(ref, SyncStatus.offline),
      ),
    ],
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: fixture.container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.dark, AppTokens.dark),
        routerConfig: fixtureRouter('/channels/c-general'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));

  expect(find.byType(RailConnectionBar), findsOneWidget);
  expect(find.text('Offline, retrying'), findsOneWidget);

  await teardownFixture(tester, fixture.container, fixture.db);
}

void main() {
  setUpAll(loadRealFonts);

  testWidgets('the connection bar appears on a compact layout when offline', (
    tester,
  ) async {
    await _expectOffline(tester, const Size(390, 844));
  });

  testWidgets('the connection bar appears on a wide layout when offline', (
    tester,
  ) async {
    await _expectOffline(tester, const Size(1400, 880));
  });
}
