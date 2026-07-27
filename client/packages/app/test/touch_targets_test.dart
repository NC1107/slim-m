// SPDX-License-Identifier: Apache-2.0
/// The rail's controls at both densities.
///
/// The create-channel affordance is the one this exists for: it was rendered,
/// permitted and functional at 30x30 on a phone, which is under the 44pt
/// platform minimum, and the owner could not find it. The expanded-width half
/// matters just as much: a pointer layout that grew to touch size would be a
/// visible regression against the design, so both ends are asserted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/widgets/channel_rail_sections.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

const Size _phone = Size(390, 844);
const Size _desktop = Size(1400, 900);

Channel _channel(String id, String name) => Channel(
      id: id,
      name: name,
      kind: 'text',
      createdAt: 0,
      cursor: 0,
      lastReadSeq: 0,
    );

Finder _createButton() => find.byWidgetPredicate(
      (w) => w is AppIconButton && w.semanticLabel == 'Create a text channel',
    );

Future<void> _pumpRail(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      home: Scaffold(
        body: TextChannelsSection(
          channels: [_channel('c1', 'general'), _channel('c2', 'random')],
          selectedId: 'c1',
          canManage: true,
        ),
      ),
    ),
  );
}

Iterable<Size> _sizesOf(WidgetTester tester, Finder finder) =>
    finder.evaluate().map((e) => tester.getSize(find.byWidget(e.widget)));

void main() {
  testWidgets('the create-channel button meets 44pt at compact width',
      (tester) async {
    await _pumpRail(tester, _phone);

    expect(_createButton(), findsOneWidget);
    expect(tester.getSize(_createButton()).shortestSide,
        greaterThanOrEqualTo(AppSizes.rowTouch));
  });

  testWidgets('the create-channel button stays pointer-sized when expanded',
      (tester) async {
    await _pumpRail(tester, _desktop);

    expect(_createButton(), findsOneWidget);
    expect(tester.getSize(_createButton()).shortestSide, AppSizes.rowPointer);
  });

  testWidgets('every rail control meets 44pt at compact width', (tester) async {
    await _pumpRail(tester, _phone);

    for (final size in _sizesOf(tester, find.byType(AppIconButton))) {
      expect(size.shortestSide, greaterThanOrEqualTo(AppSizes.rowTouch));
    }
    for (final size in _sizesOf(tester, find.byType(AppListRow))) {
      expect(size.height, greaterThanOrEqualTo(AppSizes.rowTouch));
    }
    // A manage button per channel plus the section's add button: proof the
    // loop above had rows to walk rather than passing vacuously.
    expect(find.byType(AppIconButton), findsNWidgets(3));
    expect(find.byType(AppListRow), findsNWidgets(2));
  });

  testWidgets('no rail control grows when expanded', (tester) async {
    await _pumpRail(tester, _desktop);

    for (final size in _sizesOf(tester, find.byType(AppIconButton))) {
      expect(size.shortestSide, AppSizes.rowPointer);
    }
    for (final size in _sizesOf(tester, find.byType(AppListRow))) {
      expect(size.height, AppSizes.rowPointer);
    }
  });
}
