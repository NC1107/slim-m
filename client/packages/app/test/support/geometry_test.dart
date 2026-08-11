// SPDX-License-Identifier: Apache-2.0
/// Proves `geometry.dart`'s helpers read the real `RenderBox` tree rather
/// than a widget's own requested padding, on fixtures small enough that the
/// expected numbers are worked out by hand rather than trusted from a run.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'geometry.dart';

/// 800x600 at dpr 1, matching the test binding's own default - asserted
/// once here so every distance below is a number worked out by hand, not
/// one read off a run and trusted.
const _viewport = Size(800, 600);

Future<void> _pumpBox(
  WidgetTester tester, {
  required Alignment alignment,
  required EdgeInsets padding,
  required Size boxSize,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: padding,
          child: SizedBox(
            key: const Key('probe'),
            width: boxSize.width,
            height: boxSize.height,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('viewportRect matches the default test window exactly', (
    tester,
  ) async {
    expect(viewportRect(tester), Offset.zero & _viewport);
  });

  testWidgets('viewportRect divides physical size by the device pixel ratio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    expect(viewportRect(tester), Offset.zero & const Size(390, 844));
  });

  testWidgets('edgeGap against the viewport reads every edge correctly', (
    tester,
  ) async {
    // A 100x50 box bottom-right, 12px padded on the two sides it touches.
    await _pumpBox(
      tester,
      alignment: Alignment.bottomRight,
      padding: const EdgeInsets.all(12),
      boxSize: const Size(100, 50),
    );

    final probe = find.byKey(const Key('probe'));
    expect(edgeGap(tester, probe, GeometryEdge.bottom), 12);
    expect(edgeGap(tester, probe, GeometryEdge.right), 12);
    expect(edgeGap(tester, probe, GeometryEdge.top), 600 - 50 - 12);
    expect(edgeGap(tester, probe, GeometryEdge.left), 800 - 100 - 12);
  });

  testWidgets('edgeGap against another widget ignores the viewport entirely', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 200,
            child: Stack(
              children: [
                const SizedBox(key: Key('frame')),
                Positioned(
                  left: 20,
                  top: 10,
                  child: Container(
                    key: const Key('probe'),
                    width: 40,
                    height: 30,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final frame = find.ancestor(
      of: find.byKey(const Key('frame')),
      matching: find.byType(Stack),
    );
    final probe = find.byKey(const Key('probe'));

    // The probe sits at (20, 10) sized 40x30 inside a 300x200 frame, far from the outer 800x600 viewport's own edges.
    expect(edgeGap(tester, probe, GeometryEdge.left, from: frame), 20);
    expect(edgeGap(tester, probe, GeometryEdge.top, from: frame), 10);
    expect(edgeGap(tester, probe, GeometryEdge.right, from: frame), 300 - 60);
    expect(edgeGap(tester, probe, GeometryEdge.bottom, from: frame), 200 - 40);
  });

  testWidgets('expectEdgeGap passes within tolerance and fails outside it', (
    tester,
  ) async {
    await _pumpBox(
      tester,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.all(12),
      boxSize: const Size(100, 50),
    );
    final probe = find.byKey(const Key('probe'));

    expectEdgeGap(tester, probe, GeometryEdge.bottom, 12);
    expect(
      () => expectEdgeGap(tester, probe, GeometryEdge.bottom, 20),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('expectClearOfEdge is satisfied at and above the minimum, not '
      'below it', (tester) async {
    await _pumpBox(
      tester,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.all(12),
      boxSize: const Size(100, 50),
    );
    final probe = find.byKey(const Key('probe'));

    expectClearOfEdge(tester, probe, GeometryEdge.bottom, minimum: 12);
    expectClearOfEdge(tester, probe, GeometryEdge.bottom, minimum: 0);
    expect(
      () =>
          expectClearOfEdge(tester, probe, GeometryEdge.bottom, minimum: 12.5),
      throwsA(isA<TestFailure>()),
    );
  });
}
