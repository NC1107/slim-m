// SPDX-License-Identifier: Apache-2.0
/// A settings screen is a screen on a phone and a modal on a desktop.
///
/// These screens took the whole window at every size, which on a monitor meant
/// swallowing 1280 points to show eight rows and hiding the app behind them.
/// A phone still gets the whole window, because that is the point there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/routing/modal_page.dart';
import 'package:slimm_design_system/design_system.dart';

const Size _phone = Size(390, 844);
const Size _desktop = Size(1280, 900);

/// The screen being presented, marked so it can be found whichever way it is.
const Key _screenKey = Key('screen-under-test');

Future<void> _open(WidgetTester tester, Size window) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark, AppTokens.dark),
      navigatorKey: navigator,
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => navigator.currentState!.push(
                modalPage(
                  context,
                  const ColoredBox(
                    key: _screenKey,
                    color: Color(0xFF202020),
                    child: SizedBox.expand(),
                  ),
                ).createRoute(context),
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
  testWidgets('a phone gives the screen the whole window', (tester) async {
    await _open(tester, _phone);

    final box = tester.getRect(find.byKey(_screenKey));
    expect(box.width, _phone.width);
    expect(box.height, _phone.height);
  });

  testWidgets('a desktop window floats it instead', (tester) async {
    await _open(tester, _desktop);

    final box = tester.getRect(find.byKey(_screenKey));
    expect(box.width, lessThanOrEqualTo(kModalMaxWidth));
    expect(box.height, lessThanOrEqualTo(kModalMaxHeight));
    // The complaint that started this: a monitor's worth of window for a list.
    expect(box.width, lessThan(_desktop.width));
    expect(box.height, lessThan(_desktop.height));
  });

  testWidgets('the floating panel is centred', (tester) async {
    await _open(tester, _desktop);

    final box = tester.getRect(find.byKey(_screenKey));
    expect(box.center.dx, closeTo(_desktop.width / 2, 1));
    expect(box.center.dy, closeTo(_desktop.height / 2, 1));
  });

  testWidgets('the app behind it is still there to click beside', (
    tester,
  ) async {
    await _open(tester, _desktop);

    // Not opaque: whatever was on screen stays mounted underneath, which is
    // what makes this read as a modal rather than as a new screen.
    final route = ModalRoute.of(tester.element(find.byKey(_screenKey)))!;
    expect(route.opaque, isFalse);
    expect(route.barrierDismissible, isTrue);
  });
}
