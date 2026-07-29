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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

import 'ui_snapshot_support.dart';

/// The widths that take a different branch, not a catalogue of devices.
///
/// `kCompactWidth` decides touch density and whether the member pane is built
/// at all, so the matrix straddles it rather than sampling one side.
const _viewports = <String, Size>{
  'phone-portrait': Size(390, 844),
  'phone-landscape': Size(844, 390),
  'tablet-portrait': Size(834, 1194),
  'desktop-narrow': Size(900, 600),
  'desktop': Size(1400, 880),
};

/// The surfaces worth a picture: the route, and which viewports to render.
///
/// The two shell surfaces straddle every breakpoint because width changes
/// their structure. The standalone screens keep one phone and one desktop
/// render each: their layout is a single column either way, and 5x2 renders
/// per screen would bury the reviewable ones in near-duplicates.
const _phoneAndDesktop = ['phone-portrait', 'desktop'];

const _surfaces = <String, ({String route, List<String> viewports})>{
  'channel': (
    route: '/channels/c-general',
    viewports: [
      'phone-portrait',
      'phone-landscape',
      'tablet-portrait',
      'desktop-narrow',
      'desktop',
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
    ],
  ),
  'onboarding': (route: '/join', viewports: _phoneAndDesktop),
  'sign-in': (route: '/sign-in', viewports: _phoneAndDesktop),
  'settings': (route: '/settings', viewports: _phoneAndDesktop),
  'space-settings': (route: '/settings/space', viewports: _phoneAndDesktop),
  'voice-settings': (route: '/settings/voice', viewports: _phoneAndDesktop),
  'admin-roles': (route: '/settings/roles', viewports: _phoneAndDesktop),
  'admin-invites': (route: '/settings/invites', viewports: _phoneAndDesktop),
  'admin-reports': (route: '/settings/reports', viewports: _phoneAndDesktop),
  'admin-overwrites': (
    route: '/settings/permissions',
    viewports: _phoneAndDesktop,
  ),
  'admin-emoji': (route: '/settings/emoji', viewports: _phoneAndDesktop),
};

void main() {
  setUpAll(loadRealFonts);

  for (final theme in const ['dark', 'light']) {
    for (final surface in _surfaces.entries) {
      for (final viewportName in surface.value.viewports) {
        final viewport = _viewports[viewportName]!;
        testWidgets(
          '${surface.key} at $viewportName ($theme) fits its viewport',
          (tester) async {
            tester.view.physicalSize = viewport;
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            final fixture = await fixtureContainer();
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
                    routerConfig: fixtureRouter(surface.value.route),
                  ),
                ),
              ),
            );
            // Two pumps settle on-mount entrance animations (a ticker's first frame is its own t=0) without pumpAndSettle, which would hang on the states that show a perpetual spinner.
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 350));

            await writeSnapshot(tester, '${surface.key}-$viewportName-$theme');

            // pumpWidget already rethrows an overflow as a test failure, so
            // reaching here with no exception is the assertion.
            expect(tester.takeException(), isNull);

            await teardownFixture(tester, fixture.container, fixture.db);
          },
        );
      }
    }
  }
}
