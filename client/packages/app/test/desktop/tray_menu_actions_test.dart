// SPDX-License-Identifier: Apache-2.0
/// Which rows the tray menu shows: Show/Hide and Quit always, Mute
/// microphone and Leave call only while a call is actually live - the
/// owner's own answer to decision 0012's open question about menu contents.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/tray/tray_menu_actions.dart';

void main() {
  group('trayMenuActions', () {
    test('outside a call, only Show/Hide and Quit appear', () {
      expect(trayMenuActions(inCall: false), [
        TrayMenuActionKind.showHide,
        TrayMenuActionKind.quit,
      ]);
    });

    test('in a call, Mute microphone and Leave call sit between them', () {
      expect(trayMenuActions(inCall: true), [
        TrayMenuActionKind.showHide,
        TrayMenuActionKind.muteMicrophone,
        TrayMenuActionKind.leaveCall,
        TrayMenuActionKind.quit,
      ]);
    });

    test('Quit is always the last row, in or out of a call', () {
      for (final inCall in [true, false]) {
        expect(trayMenuActions(inCall: inCall).last, TrayMenuActionKind.quit);
      }
    });
  });
}
