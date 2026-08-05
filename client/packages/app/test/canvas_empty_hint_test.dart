// SPDX-License-Identifier: Apache-2.0
/// A blank canvas otherwise looks identical to a broken one, or to one still
/// loading: a faint lattice with nothing on it. This is the sighted-only
/// invitation to draw a first mark, which disappears the instant there is
/// something to look at instead.
library;

import 'package:flutter_test/flutter_test.dart';

import 'canvas_pane_harness.dart';

void main() {
  testWidgets('a fresh canvas invites a first mark', (tester) async {
    final fixture = CanvasPaneFixture();
    final container = fixture.container();
    addTearDown(container.dispose);
    addTearDown(fixture.events.close);

    await pumpCanvasPane(tester, container);

    expect(find.text('Nothing on this canvas yet'), findsOneWidget);
  });

  testWidgets('the hint is gone once a stroke lands', (tester) async {
    final fixture = CanvasPaneFixture();
    final container = fixture.container();
    addTearDown(container.dispose);
    addTearDown(fixture.events.close);

    await pumpCanvasPane(tester, container);
    expect(find.text('Nothing on this canvas yet'), findsOneWidget);

    final gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveTo(const Offset(160, 140));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Nothing on this canvas yet'), findsNothing);
  });

  testWidgets(
    'the hint stays hidden behind objects fetched before the pane paints',
    (tester) async {
      final fixture = CanvasPaneFixture()..objects = [canvasObjectJson('a')];
      final container = fixture.container();
      addTearDown(container.dispose);
      addTearDown(fixture.events.close);

      await pumpCanvasPane(tester, container);

      expect(find.text('Nothing on this canvas yet'), findsNothing);
    },
  );
}
