// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Which rows the tray menu shows: Show/Hide, Status, Preferences and Quit
/// always, Mute microphone, Deafen and Leave call only while a call is
/// actually live - the owner's own answer to decision 0012's open question
/// about menu contents, and to backlog item 132's follow-up that the menu
/// was otherwise too sparse to be useful.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/tray/tray_menu_actions.dart';

void main() {
  group('trayMenuActions', () {
    test('outside a call: Show/Hide, Status, Preferences and Quit', () {
      expect(trayMenuActions(inCall: false), [
        TrayMenuActionKind.showHide,
        TrayMenuActionKind.presenceStatus,
        TrayMenuActionKind.settings,
        TrayMenuActionKind.quit,
      ]);
    });

    test('in a call, mute and deafen and leave sit before Preferences', () {
      expect(trayMenuActions(inCall: true), [
        TrayMenuActionKind.showHide,
        TrayMenuActionKind.presenceStatus,
        TrayMenuActionKind.muteMicrophone,
        TrayMenuActionKind.toggleDeafen,
        TrayMenuActionKind.leaveCall,
        TrayMenuActionKind.settings,
        TrayMenuActionKind.quit,
      ]);
    });

    test('Status is present whether or not a call is live', () {
      for (final inCall in [true, false]) {
        expect(
          trayMenuActions(inCall: inCall),
          contains(TrayMenuActionKind.presenceStatus),
        );
      }
    });

    test('Preferences is present whether or not a call is live', () {
      for (final inCall in [true, false]) {
        expect(
          trayMenuActions(inCall: inCall),
          contains(TrayMenuActionKind.settings),
        );
      }
    });

    test('mute and deafen only appear while a call is live', () {
      expect(
        trayMenuActions(inCall: false),
        isNot(contains(TrayMenuActionKind.muteMicrophone)),
      );
      expect(
        trayMenuActions(inCall: false),
        isNot(contains(TrayMenuActionKind.toggleDeafen)),
      );
      expect(
        trayMenuActions(inCall: true),
        containsAll([
          TrayMenuActionKind.muteMicrophone,
          TrayMenuActionKind.toggleDeafen,
        ]),
      );
    });

    test('leave call only appears while a call is live', () {
      expect(
        trayMenuActions(inCall: false),
        isNot(contains(TrayMenuActionKind.leaveCall)),
      );
      expect(
        trayMenuActions(inCall: true),
        contains(TrayMenuActionKind.leaveCall),
      );
    });

    test('Quit is always the last row, in or out of a call', () {
      for (final inCall in [true, false]) {
        expect(trayMenuActions(inCall: inCall).last, TrayMenuActionKind.quit);
      }
    });
  });
}
