// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The phone boot splash's decision and its look: it covers a cold launch
/// until the first catch-up lands, holds through the resting `offline` and
/// the first `connecting` attempt, and steps aside for good the moment that
/// first attempt fails - so an offline phone is never trapped on a splash,
/// and never sees it come back on a later retry either. Desktop is never
/// gated.
///
/// The widget-level group below is the regression test for the real bug: on
/// Linux, `flutter test` reports [isDesktopHost] true for every build, so
/// `MobileBootGate`'s mobile branch never ran under an ordinary widget test
/// - only the pure [shouldShowBootSplash] truth table above it did, which is
/// exactly how a wrong pure-function expectation shipped unnoticed.
/// [MobileBootGate.isDesktopOverride] exists purely to give a test a way in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
          hasFailedSinceLive: false,
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
          hasFailedSinceLive: false,
        ),
        isTrue,
      );
    });

    test('once the first attempt has failed, the splash stays down through '
        'every later retry', () {
      // The fixed case: a latch, so a later retry's own connecting/offline flip cannot re-arm it.
      expect(
        shouldShowBootSplash(
          isMobile: true,
          synced: false,
          hasFailedSinceLive: true,
        ),
        isFalse,
      );
    });

    test('once the first catch-up lands the home shows for good', () {
      expect(
        shouldShowBootSplash(
          isMobile: true,
          synced: true,
          hasFailedSinceLive: false,
        ),
        isFalse,
      );
    });
  });

  group('MobileBootGate, mobile branch actually taken', () {
    ProviderContainer setup() {
      final container = ProviderContainer();
      return container;
    }

    Future<void> pumpGate(WidgetTester tester, ProviderContainer container) {
      return tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildTheme(Brightness.light, AppTokens.light),
            home: const MobileBootGate(
              isDesktopOverride: false,
              child: Text('home'),
            ),
          ),
        ),
      );
    }

    testWidgets('without the override, this host still reads as desktop and the '
        'splash never appears at all', (tester) async {
      // Proves the trap: on this Linux host, MobileBootGate's own logic runs only if a test asks for the mobile branch explicitly.
      final container = setup();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildTheme(Brightness.light, AppTokens.light),
            home: const MobileBootGate(child: Text('home')),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(BootSplashScreen), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a cold launch with no signal yet shows the splash', (
      tester,
    ) async {
      final container = setup();
      addTearDown(container.dispose);
      await pumpGate(tester, container);
      await tester.pump();

      expect(find.byType(BootSplashScreen), findsOneWidget);
      expect(find.text('home'), findsNothing);
    });

    testWidgets('the server unreachable from launch: the splash appears once and '
        'stays down through several connecting/offline retries', (tester) async {
      final container = setup();
      addTearDown(container.dispose);
      await pumpGate(tester, container);
      await tester.pump();
      expect(
        find.byType(BootSplashScreen),
        findsOneWidget,
        reason: 'resting offline, before the first attempt, still covers',
      );

      // The first attempt fails: SyncController.start's catch block makes exactly this one write.
      container.read(hasFailedSinceLiveProvider.notifier).state = true;
      await tester.pump();
      expect(
        find.byType(BootSplashScreen),
        findsNothing,
        reason: 'the app is revealed the moment the first attempt fails',
      );

      // Several more retries: the latch stays set, unlike the old plain-status read that flickered here.
      for (var attempt = 0; attempt < 4; attempt++) {
        container.read(hasFailedSinceLiveProvider.notifier).state = true;
        await tester.pump();
        expect(
          find.byType(BootSplashScreen),
          findsNothing,
          reason: 'retry $attempt must not re-cover the app',
        );
      }
    });

    testWidgets(
      'a successful first sync keeps the home up even if hasFailedSinceLive '
      'is set later, since a reconnect after that can only drop, not re-splash',
      (tester) async {
        final container = setup();
        addTearDown(container.dispose);
        await pumpGate(tester, container);

        container.read(initialSyncCompleteProvider.notifier).state = true;
        await tester.pump();
        expect(find.byType(BootSplashScreen), findsNothing);
        expect(find.text('home'), findsOneWidget);

        // A later drop's own failed reconnect would relatch this, and still must not bring the splash back.
        container.read(hasFailedSinceLiveProvider.notifier).state = true;
        await tester.pump();
        expect(find.byType(BootSplashScreen), findsNothing);
      },
    );
  });
}
