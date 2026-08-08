// SPDX-License-Identifier: Apache-2.0
/// A modal is whatever the window can carry.
///
/// Every modal in the app was a bottom sheet, which is a phone affordance: it
/// sits against the edge a thumb reaches and its drag handle means something
/// to a thumb. On a desktop window one reads as a phone screen pasted along
/// the bottom of a monitor, offers a handle a mouse cannot usefully drag, and
/// gets cut off by an edge it cannot see. The avatar crop sheet was cut off
/// exactly that way and could not be completed at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

const Size _phone = Size(390, 844);
const Size _desktop = Size(1280, 900);

/// The panel itself, not [Dialog], whose own box is the whole padded screen
/// and so is centred and full-width no matter what the panel does.
Finder get _panel => find
    .descendant(of: find.byType(Dialog), matching: find.byType(Material))
    .first;

Future<void> _open(
  WidgetTester tester,
  Size window, {
  double maxWidth = kSheetMaxWidth,
  bool bare = false,
}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAppSheet<void>(
                context,
                maxWidth: maxWidth,
                bare: bare,
                // Greedy on purpose: content that asks for more width than
                // the cap is the only thing that proves the cap binds.
                builder: (_) => const SizedBox(
                  width: 2000,
                  height: 120,
                  child: Center(child: Text('sheet body')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a phone gets a bottom sheet', (tester) async {
    await _open(tester, _phone);

    expect(find.text('sheet body'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'a bottom sheet keeps its content clear of a home indicator, even when '
    'the sheet itself never asked to',
    (tester) async {
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark, AppTokens.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showAppSheet<void>(
                    context,
                    // A caller that never wraps its own content in SafeArea, the common shape.
                    builder: (_) => const Text('sheet body'),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(SafeArea), findsOneWidget);
      final safeArea = tester.widget<SafeArea>(find.byType(SafeArea));
      expect(safeArea.bottom, isTrue);
      expect(safeArea.top, isFalse);
    },
  );

  testWidgets('a desktop window gets a dialog', (tester) async {
    await _open(tester, _desktop);

    expect(find.text('sheet body'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('the dialog does not grow with the monitor', (tester) async {
    await _open(tester, _desktop);

    final box = tester.getRect(_panel);
    expect(box.width, lessThanOrEqualTo(kSheetMaxWidth));
    expect(box.width, lessThan(_desktop.width / 2));
  });

  testWidgets('the dialog is centred, not stuck to an edge', (tester) async {
    await _open(tester, _desktop);

    final box = tester.getRect(_panel);
    expect(box.center.dx, closeTo(_desktop.width / 2, 1));
    expect(box.center.dy, closeTo(_desktop.height / 2, 1));
    // The failure that started this: content past the bottom of the window.
    expect(box.bottom, lessThanOrEqualTo(_desktop.height));
  });

  testWidgets('content that draws its own surface is not double-framed', (
    tester,
  ) async {
    await _open(tester, _desktop, bare: true);

    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(dialog.backgroundColor, Colors.transparent);
    expect(dialog.shape, isNull);
  });
}
