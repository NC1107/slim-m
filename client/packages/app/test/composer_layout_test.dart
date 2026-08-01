// SPDX-License-Identifier: Apache-2.0
/// The action icons beside the composer's text field must stay pinned to
/// the top of the bar as a multi-line message grows it, not drift toward
/// the middle. Covers both the compact (phone, folded `+` sheet) and wide
/// (desktop, inline poll/code) layouts, since both share the same Row.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_design_system/design_system.dart';

import 'composer_harness.dart';

const _barKey = Key('composer-action-bar');

void main() {
  late TextEditingController controller;
  late Sends sends;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    controller = TextEditingController();
    sends = Sends();
  });

  tearDown(() => controller.dispose());

  /// Fills the field with enough newlines to grow the bar well past a
  /// single line's height, then asserts every action icon's vertical
  /// centre sits in the upper portion of the bar rather than at its
  /// midpoint.
  Future<void> expectIconsPinnedToTop(
    WidgetTester tester, {
    required TargetPlatform platform,
    required Size windowSize,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = windowSize;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      composerHarness(controller: controller, sends: sends, platform: platform),
    );

    controller.text = 'one\ntwo\nthree\nfour\nfive';
    await tester.pump();

    final bar = tester.getRect(find.byKey(_barKey));
    final buttons = find.byType(AppIconButton);
    expect(buttons, findsWidgets);

    for (final element in buttons.evaluate()) {
      final iconCenterY = tester.getCenter(find.byWidget(element.widget)).dy;
      final fraction = (iconCenterY - bar.top) / bar.height;
      expect(
        fraction,
        lessThan(0.35),
        reason:
            'an icon centred in the bar would sit near 0.5; pinned to the '
            'top it should sit well above that as the field grows',
      );
    }
  }

  testWidgets(
    'compact layout: icons stay pinned to the top of a grown field',
    (tester) => expectIconsPinnedToTop(
      tester,
      platform: TargetPlatform.iOS,
      windowSize: const Size(390, 844),
    ),
  );

  testWidgets(
    'wide layout: icons stay pinned to the top of a grown field',
    (tester) => expectIconsPinnedToTop(
      tester,
      platform: TargetPlatform.linux,
      windowSize: const Size(1400, 900),
    ),
  );
}
