// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `dangerGhost` against `danger`, which it exists to sit beside rather than
/// replace. `danger` states the consequence at rest with a standing
/// `dangerBorder`; a title bar's close button drew that outline permanently,
/// which read as a red box around the X rather than as a warning, since its
/// position in the bar already says what it does. This pins that
/// `dangerGhost` is indistinguishable from its neighbours until hover, and
/// that `danger` itself is unchanged.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

const _tokens = AppTokens.light;

Future<void> _pump(WidgetTester tester, AppIconButtonVariant variant) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light, _tokens),
      home: Scaffold(
        body: Center(
          child: AppIconButton(
            icon: AppIcons.windowClose,
            semanticLabel: 'Close',
            variant: variant,
            onPressed: () {},
          ),
        ),
      ),
    ),
  );
}

BoxDecoration _decoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(AppIconButton),
      matching: find.byType(Container),
    ),
  );
  return container.decoration! as BoxDecoration;
}

Color? _ink(WidgetTester tester) => tester
    .widget<Icon>(
      find.descendant(
        of: find.byType(AppIconButton),
        matching: find.byType(Icon),
      ),
    )
    .color;

void main() {
  testWidgets('dangerGhost carries no border, and reddens only on hover', (
    tester,
  ) async {
    // A mobile-emulated test target only reports traditional highlighting once a mouse connects.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await _pump(tester, AppIconButtonVariant.dangerGhost);

    expect(
      _decoration(tester).border,
      isNull,
      reason: 'at rest it has to match the minimize and maximize beside it',
    );
    expect(_ink(tester), _tokens.textSecondary);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(AppIconButton)));
    await tester.pumpAndSettle();

    expect(_ink(tester), _tokens.dangerText, reason: 'hover states it');
    expect(
      _decoration(tester).border,
      isNull,
      reason: 'hover reddens the glyph, it does not draw the box back',
    );

    await gesture.removePointer();
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('danger still states itself at rest', (tester) async {
    await _pump(tester, AppIconButtonVariant.danger);

    expect(
      _decoration(tester).border,
      Border.all(color: _tokens.dangerBorder),
      reason: 'the variant dangerGhost was added beside, not in place of',
    );
    expect(_ink(tester), _tokens.dangerText);
  });
}
