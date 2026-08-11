// SPDX-License-Identifier: Apache-2.0
/// The first-time-only tray notice: shows once per resolved [CloseAction],
/// decision 0012's owner-supplied answer for Alt+F4/the X button both
/// closing to something with no way to tell them apart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/desktop/close_behavior.dart';
import 'package:slimm_app/src/desktop/first_run_tray_notice.dart';

void main() {
  group('FirstRunTrayNotice', () {
    test('a fresh install has not been shown either outcome yet', () async {
      SharedPreferences.setMockInitialValues({});
      final notice = FirstRunTrayNotice(await SharedPreferences.getInstance());

      expect(notice.hasBeenShown(CloseAction.hideToTray), isFalse);
      expect(notice.hasBeenShown(CloseAction.minimizeToTaskbar), isFalse);
    });

    test('markShown is what flips it, and it stays flipped', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notice = FirstRunTrayNotice(prefs);

      await notice.markShown(CloseAction.hideToTray);

      expect(notice.hasBeenShown(CloseAction.hideToTray), isTrue);
      expect(
        FirstRunTrayNotice(prefs).hasBeenShown(CloseAction.hideToTray),
        isTrue,
        reason: 'a second instance over the same store sees the same answer',
      );
    });

    test(
      'seeing the tray outcome does not mark the taskbar outcome as shown, '
      'or a later machine that loses its tray host would never be told',
      () async {
        SharedPreferences.setMockInitialValues({});
        final notice = FirstRunTrayNotice(
          await SharedPreferences.getInstance(),
        );

        await notice.markShown(CloseAction.hideToTray);

        expect(notice.hasBeenShown(CloseAction.hideToTray), isTrue);
        expect(notice.hasBeenShown(CloseAction.minimizeToTaskbar), isFalse);
      },
    );

    test('an install that already saw one outcome stays marked across a '
        'restart', () async {
      SharedPreferences.setMockInitialValues({
        firstRunTrayNoticeShownKey(CloseAction.minimizeToTaskbar): true,
      });
      final notice = FirstRunTrayNotice(await SharedPreferences.getInstance());

      expect(notice.hasBeenShown(CloseAction.minimizeToTaskbar), isTrue);
      expect(notice.hasBeenShown(CloseAction.hideToTray), isFalse);
    });
  });
}
