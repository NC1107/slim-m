// SPDX-License-Identifier: Apache-2.0
/// `CanvasOpenButton` shows for a voice channel and for nothing else, by
/// owner decision (backlog, 2026-08-13): the canvas belongs to talking
/// together. That covers the DM case for free, whose base permissions never
/// grant `USE_CANVAS` (`store/dms.rs`'s `DM_BASE`) so the route always 403s
/// there, and a text channel now hides it too.
///
/// The kind arrives as a plain flag from the header that builds this rather
/// than from a store lookup, so these are pure widget tests with no database
/// and no async resolve - see the widget's own doc comment for why.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/screens/canvas/canvas_open_button.dart';
import 'package:slimm_app/src/screens/canvas/canvas_pane.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  required bool isVoice,
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildTheme(Brightness.light, AppTokens.light),
      home: Scaffold(
        body: CanvasOpenButton(channelId: 'c1', isVoice: isVoice),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows for a voice channel and hides for anything else', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await _pump(tester, container, isVoice: false);
    await tester.pump();
    expect(find.bySemanticsLabel('Open canvas'), findsNothing);

    await _pump(tester, container, isVoice: true);
    await tester.pump();
    expect(find.bySemanticsLabel('Open canvas'), findsOneWidget);
  });

  testWidgets('tapping it opens this channel and tapping again closes it', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await _pump(tester, container, isVoice: true);
    await tester.pump();

    expect(container.read(canvasOpenProvider), isNull);
    await tester.tap(find.bySemanticsLabel('Open canvas'));
    await tester.pump();
    expect(container.read(canvasOpenProvider), 'c1');

    await tester.tap(find.bySemanticsLabel('Open canvas'));
    await tester.pump();
    expect(container.read(canvasOpenProvider), isNull);
  });
}
