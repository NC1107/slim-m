// SPDX-License-Identifier: Apache-2.0
/// `AppIconButton`'s own hover fill (`surfaceRaised`) used to paint
/// unconditionally, which visibly clashed when an enclosing control (a
/// channel row's kebab, say) already carries its own hover/selection tint -
/// most visibly a selection fill, which the button's plain hover box sat on
/// top of uncoordinated. `suppressOwnHoverFill` opts a caller like that out
/// of the button's own colour change; this pins both the default (unchanged)
/// and the opt-out.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _pump(WidgetTester tester, Widget child, {AppTokens? tokens}) {
  final t = tokens ?? AppTokens.light;
  return tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light, t),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets(
    'suppressOwnHoverFill keeps the fill transparent under a real hover, '
    'where the default still shows surfaceRaised',
    (tester) async {
      const tokens = AppTokens.light;
      // A mobile-emulated test target only reports traditional highlighting once a mouse connects.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;

      Future<Color?> fillAfterHover({required bool suppress}) async {
        await _pump(
          tester,
          AppIconButton(
            icon: AppIcons.settings,
            semanticLabel: 'x',
            onPressed: () {},
            suppressOwnHoverFill: suppress,
          ),
          tokens: tokens,
        );
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        await tester.pump();
        await gesture.moveTo(tester.getCenter(find.byType(AppIconButton)));
        await tester.pumpAndSettle();
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(AppIconButton),
            matching: find.byType(Container),
          ),
        );
        final color = (container.decoration as BoxDecoration).color;
        await gesture.removePointer();
        await tester.pump();
        return color;
      }

      expect(await fillAfterHover(suppress: false), tokens.surfaceRaised);
      expect(await fillAfterHover(suppress: true), Colors.transparent);

      debugDefaultTargetPlatformOverride = null;
    },
  );
}
