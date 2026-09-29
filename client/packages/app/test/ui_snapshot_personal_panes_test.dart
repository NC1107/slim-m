// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Every personal settings pane, opened by tapping its nav row the way a
/// person does, at the phone and desktop widths in both themes.
///
/// `/settings` alone only ever renders the first pane, which is how the other
/// eight went unlooked-at by the snapshot matrix.
library;

import 'package:flutter_test/flutter_test.dart';

import 'ui_snapshot_support.dart';

const _panes = <String, String>{
  'profile': 'Profile',
  'account-devices': 'Account & devices',
  'appearance': 'Appearance',
  'performance': 'Performance',
  'notifications': 'Notifications',
  'voice': 'Voice & screen share',
  'blocked': 'Blocked',
  'report-status': 'Report status',
  'about': 'About slim-m',
};

void main() {
  setUpAll(loadRealFonts);

  for (final theme in const ['dark', 'light']) {
    for (final pane in _panes.entries) {
      for (final viewport in phoneAndDesktop) {
        testWidgets('settings pane ${pane.key} at $viewport ($theme)', (
          tester,
        ) async {
          await renderSurface(
            tester,
            '/settings',
            viewport,
            theme,
            'settings-pane-${pane.key}-$viewport-$theme',
            afterSettle: (tester) async {
              await tester.tap(find.text(pane.value).first);
              await tester.pump();
            },
          );
        });
      }
    }
  }
}
