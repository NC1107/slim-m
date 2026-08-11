// SPDX-License-Identifier: Apache-2.0
/// The first-time-only tray notice: shows once, never again, decision
/// 0012's owner-supplied answer for Alt+F4/the X button both minimising
/// with no way to tell them apart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/desktop/first_run_tray_notice.dart';

void main() {
  group('FirstRunTrayNotice', () {
    test('a fresh install has not been shown the notice yet', () async {
      SharedPreferences.setMockInitialValues({});
      final notice = FirstRunTrayNotice(await SharedPreferences.getInstance());

      expect(notice.hasBeenShown, isFalse);
    });

    test('markShown is what flips it, and it stays flipped', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notice = FirstRunTrayNotice(prefs);

      await notice.markShown();

      expect(notice.hasBeenShown, isTrue);
      expect(
        FirstRunTrayNotice(prefs).hasBeenShown,
        isTrue,
        reason: 'a second instance over the same store sees the same answer',
      );
    });

    test(
      'an install that already saw it stays marked across a restart',
      () async {
        SharedPreferences.setMockInitialValues({
          firstRunTrayNoticeShownKey: true,
        });
        final notice = FirstRunTrayNotice(
          await SharedPreferences.getInstance(),
        );

        expect(notice.hasBeenShown, isTrue);
      },
    );
  });
}
