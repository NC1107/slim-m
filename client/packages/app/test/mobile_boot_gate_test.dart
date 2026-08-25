// SPDX-License-Identifier: Apache-2.0
/// The phone boot splash's decision and its look: it covers a cold launch
/// until the first catch-up lands, holds through the resting `offline` and the
/// `connecting` attempt, and steps aside for the cached home the moment a seen
/// attempt fails - so an offline phone is never trapped on a splash. Desktop is
/// never gated.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/providers/sync_controller.dart';
import 'package:slimm_app/src/widgets/mobile_boot_gate.dart';
import 'package:slimm_design_system/design_system.dart';

void main() {
  group('shouldShowBootSplash', () {
    test('desktop is never covered, whatever the sync state', () {
      expect(
        shouldShowBootSplash(
          isMobile: false,
          synced: false,
          sawConnecting: false,
          status: SyncStatus.connecting,
        ),
        isFalse,
      );
    });

    test('the resting offline before any attempt still shows the splash', () {
      // No flash of the empty home while offline precedes the first connect.
      expect(
        shouldShowBootSplash(
          isMobile: true,
          synced: false,
          sawConnecting: false,
          status: SyncStatus.offline,
        ),
        isTrue,
      );
    });

    test('the connecting attempt shows the splash', () {
      expect(
        shouldShowBootSplash(
          isMobile: true,
          synced: false,
          sawConnecting: true,
          status: SyncStatus.connecting,
        ),
        isTrue,
      );
    });

    test('a seen attempt failing back to offline reveals the home', () {
      expect(
        shouldShowBootSplash(
          isMobile: true,
          synced: false,
          sawConnecting: true,
          status: SyncStatus.offline,
        ),
        isFalse,
      );
    });

    test('once the first catch-up lands the home shows for good', () {
      expect(
        shouldShowBootSplash(
          isMobile: true,
          synced: true,
          sawConnecting: true,
          status: SyncStatus.connecting,
        ),
        isFalse,
      );
    });
  });

  testWidgets('the splash carries the brand mark and a working indicator', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const BootSplashScreen(),
      ),
    );

    expect(find.byType(AppBrandMark), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
