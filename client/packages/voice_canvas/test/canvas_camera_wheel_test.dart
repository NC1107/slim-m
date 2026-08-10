// SPDX-License-Identifier: Apache-2.0
/// [cameraAfterWheelScroll] and [cameraAfterZoom] in isolation, with no
/// widget at all - the pure math [CanvasSurface]'s own gesture layer and a
/// manipulable presence tile both read now, so the invariant belongs at
/// this level rather than only proven once through a widget test's own
/// pointer plumbing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

void main() {
  test(
      'ctrl-modified zoom keeps the world point under a non-origin focal '
      'fixed', () {
    const camera = Camera(x: 137, y: -52, zoom: 1);
    const focal = Offset(210, 340);
    Offset worldUnder(Camera c) =>
        Offset(c.x + focal.dx / c.zoom, c.y + focal.dy / c.zoom);
    final before = worldUnder(camera);

    final after = cameraAfterWheelScroll(
      camera,
      focal: focal,
      dx: 0,
      dy: -40,
      zoomModifier: true,
      horizontalModifier: false,
    );

    expect(after.zoom, greaterThan(1));
    final resolved = worldUnder(after);
    expect(resolved.dx, closeTo(before.dx, 1e-9));
    expect(resolved.dy, closeTo(before.dy, 1e-9));
  });

  test('an unmodified notch pans both axes by the raw delta over zoom', () {
    const camera = Camera(x: 0, y: 0, zoom: 2);
    final after = cameraAfterWheelScroll(
      camera,
      focal: const Offset(400, 300),
      dx: 20,
      dy: 40,
      zoomModifier: false,
      horizontalModifier: false,
    );
    expect(after.x, 10);
    expect(after.y, 20);
    expect(after.zoom, 2);
  });

  test(
      'a shift-modified notch pans horizontally only, from whichever axis '
      'carries the delta', () {
    const camera = Camera(x: 0, y: 0, zoom: 1);
    final fromDy = cameraAfterWheelScroll(
      camera,
      focal: Offset.zero,
      dx: 0,
      dy: 40,
      zoomModifier: false,
      horizontalModifier: true,
    );
    expect(fromDy.x, 40);
    expect(fromDy.y, 0);
  });

  test('zooming past maxZoom clamps rather than overshooting', () {
    const camera = Camera(x: 0, y: 0, zoom: maxZoom);
    final after = cameraAfterZoom(
      camera,
      focal: const Offset(50, 50),
      zoomTarget: maxZoom * 2,
    );
    expect(after.zoom, maxZoom);
  });

  test(
      'requesting the zoom already held is a true no-op, not just a '
      'numerically equal camera', () {
    const camera = Camera(x: 12, y: -8, zoom: maxZoom);
    final after = cameraAfterZoom(
      camera,
      focal: const Offset(50, 50),
      zoomTarget: maxZoom * 2,
    );
    expect(identical(after, camera), isTrue);
  });
}
