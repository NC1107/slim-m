// SPDX-License-Identifier: Apache-2.0
/// The real shell, rendered at every resolution the product ships to.
///
/// This is the matrix `design_system`'s golden matrix is not: that one renders
/// a synthetic sample of chrome, so a regression in an actual widget (the
/// rail's manage button drifting out of its row, a reaction chip stretching
/// the width of the pane) is invisible to it.
///
/// Two things run here. The overflow assertions run everywhere including CI.
/// The PNGs are written only under SLIMM_UI_SNAPSHOTS=1, because they exist to
/// be looked at rather than diffed: Skia and font rasterisation differ between
/// this box and a CI runner, so a committed reference would be permanently red.
///
/// Write them with `scripts/ui-snapshots.sh`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/main.dart' show appChromeBuilder;
import 'package:slimm_design_system/design_system.dart';

import 'ui_snapshot_support.dart';

/// The widths that take a different branch, not a catalogue of devices.
///
/// The five named ones are device shapes, kept for general coverage.
/// The rest are pairs straddling one specific pixel a real layout branches
/// on - `kCompactWidth`, `LayoutClass`'s own second boundary, and three more
/// local to `onboarding_shell.dart` and `settings_panes.dart` - a width one
/// round number away from a boundary can sit entirely on one side of it and
/// never prove the other side renders at all.
const _viewports = <String, Size>{
  'phone-portrait': Size(390, 844),
  'phone-landscape': Size(844, 390),
  'tablet-portrait': Size(834, 1194),
  'desktop-narrow': Size(900, 600),
  'desktop': Size(1400, 880),
  // kCompactWidth (design_system/app_metrics.dart): touch density and modal presentation.
  'compact-599': Size(599, 844),
  'compact-600': Size(600, 844),
  // LayoutClass.medium/expanded (routing/breakpoints.dart): the member pane.
  'expanded-999': Size(999, 844),
  'expanded-1000': Size(1000, 844),
  // onboarding_shell's brand-panel floor (900).
  'onboarding-899': Size(899, 844),
  'onboarding-900': Size(900, 844),
  // onboarding_shell's stepper label threshold (420 of content width, window less padding).
  'stepper-467': Size(467, 844),
  'stepper-468': Size(468, 844),
  // settings_panes's two-pane floor (800).
  'settings-799': Size(799, 844),
  'settings-800': Size(800, 844),
};

/// The surfaces worth a picture: the route, and which viewports to render.
///
/// The two shell surfaces straddle every breakpoint they own because width
/// changes their structure. Each standalone screen adds the pair that
/// brackets its *own* breakpoint to a phone and a desktop render, rather than
/// every screen sampling every boundary: a screen with no 800px floor of its
/// own gains nothing from being rendered at 799 and 800.
const _phoneAndDesktop = ['phone-portrait', 'desktop'];
const _compactBracket = ['compact-599', 'compact-600'];

const _surfaces = <String, ({String route, List<String> viewports})>{
  'channel': (
    route: '/channels/c-general',
    viewports: [
      'phone-portrait',
      'phone-landscape',
      'tablet-portrait',
      'desktop-narrow',
      'desktop',
      ..._compactBracket,
      'expanded-999',
      'expanded-1000',
    ],
  ),
  'voice': (
    route: '/channels/c-main',
    viewports: [
      'phone-portrait',
      'phone-landscape',
      'tablet-portrait',
      'desktop-narrow',
      'desktop',
      ..._compactBracket,
      'expanded-999',
      'expanded-1000',
    ],
  ),
  'onboarding': (
    route: '/join',
    viewports: [
      ..._phoneAndDesktop,
      'stepper-467',
      'stepper-468',
      'onboarding-899',
      'onboarding-900',
    ],
  ),
  'sign-in': (
    route: '/sign-in',
    viewports: [..._phoneAndDesktop, 'onboarding-899', 'onboarding-900'],
  ),
  'settings': (
    route: '/settings',
    viewports: [
      ..._phoneAndDesktop,
      ..._compactBracket,
      'settings-799',
      'settings-800',
    ],
  ),
  'space-settings': (
    route: '/settings/space',
    viewports: [
      ..._phoneAndDesktop,
      ..._compactBracket,
      'settings-799',
      'settings-800',
    ],
  ),
  'admin-roles': (
    route: '/settings/roles',
    viewports: [..._phoneAndDesktop, ..._compactBracket],
  ),
  'admin-invites': (
    route: '/settings/invites',
    viewports: [..._phoneAndDesktop, ..._compactBracket],
  ),
  'admin-reports': (
    route: '/settings/reports',
    viewports: [..._phoneAndDesktop, ..._compactBracket],
  ),
  'admin-overwrites': (
    route: '/settings/permissions',
    viewports: [..._phoneAndDesktop, ..._compactBracket],
  ),
  'admin-emoji': (
    route: '/settings/emoji',
    viewports: [..._phoneAndDesktop, ..._compactBracket],
  ),
};

void main() {
  setUpAll(loadRealFonts);

  for (final theme in const ['dark', 'light']) {
    for (final surface in _surfaces.entries) {
      for (final viewportName in surface.value.viewports) {
        final viewport = _viewports[viewportName]!;
        testWidgets('${surface.key} at $viewportName ($theme) fits its viewport', (
          tester,
        ) async {
          tester.view.physicalSize = viewport;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          final fixture = await fixtureContainer();
          final route = surface.value.route;
          final router = fixtureRouter(route);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: fixture.container,
              child: RepaintBoundary(
                key: snapshotBoundary,
                child: MaterialApp.router(
                  debugShowCheckedModeBanner: false,
                  theme: theme == 'dark'
                      ? buildTheme(Brightness.dark, AppTokens.dark)
                      : buildTheme(Brightness.light, AppTokens.light),
                  routerConfig: router,
                  // The same wrapper main.dart ships, so density matches the app.
                  builder: appChromeBuilder,
                ),
              ),
            ),
          );
          if (isModalFixtureRoute(route)) {
            // Settle at the base first, then push: see isModalFixtureRoute's doc.
            await tester.pump();
            unawaited(router.push(route));
          }
          // Two pumps settle on-mount entrance animations (a ticker's first frame is its own t=0) without pumpAndSettle, which would hang on the states that show a perpetual spinner.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));

          await writeSnapshot(tester, '${surface.key}-$viewportName-$theme');

          // pumpWidget already rethrows an overflow as a test failure, so
          // reaching here with no exception is the assertion.
          expect(tester.takeException(), isNull);

          await teardownFixture(tester, fixture.container, fixture.db);
        });
      }
    }
  }
}
