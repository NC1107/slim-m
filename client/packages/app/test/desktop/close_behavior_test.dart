// SPDX-License-Identifier: Apache-2.0
/// The close-vs-minimise router, decision 0012: what the close affordance
/// does on each platform, asserted for every combination rather than the
/// one this dev box happens to run.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/close_behavior.dart';

void main() {
  group('resolveCloseAction', () {
    test('macOS always hides, tray availability irrelevant', () {
      for (final trayAvailable in [true, false]) {
        expect(
          resolveCloseAction(
            platform: DesktopPlatform.macOS,
            trayAvailable: trayAvailable,
          ),
          CloseAction.hideToTray,
        );
      }
    });

    test('Windows always hides, tray availability irrelevant', () {
      for (final trayAvailable in [true, false]) {
        expect(
          resolveCloseAction(
            platform: DesktopPlatform.windows,
            trayAvailable: trayAvailable,
          ),
          CloseAction.hideToTray,
        );
      }
    });

    test('Linux with a registered tray host hides to it', () {
      expect(
        resolveCloseAction(
          platform: DesktopPlatform.linux,
          trayAvailable: true,
        ),
        CloseAction.hideToTray,
      );
    });

    test('Linux with no tray host falls back to an ordinary minimise, '
        'never a hide with no way back', () {
      expect(
        resolveCloseAction(
          platform: DesktopPlatform.linux,
          trayAvailable: false,
        ),
        CloseAction.minimizeToTaskbar,
      );
    });
  });
}
