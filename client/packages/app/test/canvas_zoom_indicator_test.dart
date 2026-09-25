// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [CanvasZoomIndicator]: the one on-screen zoom-percentage readout, driven
/// straight off [CanvasDocument.camera].
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/canvas/canvas_zoom_indicator.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.dark, AppTokens.dark),
  home: Scaffold(
    body: SizedBox(width: 400, height: 400, child: Stack(children: [child])),
  ),
);

void main() {
  testWidgets('reads 100% at the default camera', (tester) async {
    final document = CanvasDocument();
    addTearDown(document.dispose);

    await tester.pumpWidget(
      _wrap(CanvasZoomIndicator(document: document, tokens: AppTokens.dark)),
    );

    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('updates live as the camera zooms, with no rebuild needed', (
    tester,
  ) async {
    final document = CanvasDocument();
    addTearDown(document.dispose);
    document.setViewport(const Size(400, 400));

    await tester.pumpWidget(
      _wrap(CanvasZoomIndicator(document: document, tokens: AppTokens.dark)),
    );
    expect(find.text('100%'), findsOneWidget);

    document.setCamera(const Camera(zoom: 2));
    await tester.pump();

    expect(find.text('200%'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
  });

  testWidgets('never intercepts a pointer meant for the surface below', (
    tester,
  ) async {
    final document = CanvasDocument();
    addTearDown(document.dispose);

    await tester.pumpWidget(
      _wrap(CanvasZoomIndicator(document: document, tokens: AppTokens.dark)),
    );

    final ignore = tester.widget<IgnorePointer>(
      find.descendant(
        of: find.byType(CanvasZoomIndicator),
        matching: find.byType(IgnorePointer),
      ),
    );
    expect(ignore.ignoring, isTrue);
  });
}
