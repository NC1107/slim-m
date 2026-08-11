// SPDX-License-Identifier: Apache-2.0
/// The geometry-clamp math decision 0012 names as fully automatable: whether
/// a saved rectangle still lands on an attached display. No window, no
/// platform channel, plain Dart per the record's own rule.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/window_geometry.dart';

const _primary = DisplayArea(x: 0, y: 0, width: 1920, height: 1080);
const _secondPositionedRight = DisplayArea(
  x: 1920,
  y: 0,
  width: 1920,
  height: 1080,
);

WindowGeometry _windowed({required double x, required double y}) =>
    WindowGeometry(
      windowedSize: const WindowSize(width: 1280, height: 720),
      position: WindowRect(x: x, y: y, width: 1280, height: 720),
    );

void main() {
  group('clampToAttachedDisplays', () {
    test('a rectangle inside an attached display is kept unchanged', () {
      final geometry = _windowed(x: 100, y: 100);

      final clamped = clampToAttachedDisplays(geometry, [_primary]);

      expect(clamped, same(geometry));
    });

    test('a rectangle only overlapping a second display is still kept', () {
      final geometry = _windowed(x: 2000, y: 100);

      final clamped = clampToAttachedDisplays(geometry, [
        _primary,
        _secondPositionedRight,
      ]);

      expect(clamped.position, geometry.position);
    });

    test(
      'a rectangle that overlaps no attached display drops its position',
      () {
        // A monitor unplugged since: nothing attached covers that ground.
        final geometry = _windowed(x: 5000, y: 5000);

        final clamped = clampToAttachedDisplays(geometry, [_primary]);

        expect(clamped.position, isNull);
        expect(
          clamped.windowedSize,
          geometry.windowedSize,
          reason: 'size survives even when position does not',
        );
      },
    );

    test('an empty display list is treated as nothing to validate against', () {
      final geometry = _windowed(x: 100, y: 100);

      final clamped = clampToAttachedDisplays(geometry, const []);

      expect(
        clamped.position,
        isNull,
        reason:
            'a position this call cannot confirm is safe must not be applied',
      );
    });

    test('a geometry with no saved position passes through untouched', () {
      const geometry = WindowGeometry.fallback;

      final clamped = clampToAttachedDisplays(geometry, [_primary]);

      expect(clamped, same(geometry));
    });

    /// A rectangle sitting exactly at a display's own far edge shares no
    /// area with it - `overlaps` must not treat a shared boundary line as
    /// overlap, or a window one pixel off a display would still "fit".
    test(
      'a rectangle exactly abutting a display, not inside it, is dropped',
      () {
        final geometry = _windowed(x: 1920, y: 0);

        final clamped = clampToAttachedDisplays(geometry, [_primary]);

        expect(clamped.position, isNull);
      },
    );
  });

  group('WindowGeometry JSON round trip', () {
    test('a fully windowed geometry survives encode and decode', () {
      final geometry = _windowed(x: 42, y: 7);

      final restored = WindowGeometry.fromJson(geometry.toJson());

      expect(restored.windowedSize, geometry.windowedSize);
      expect(restored.position?.x, geometry.position?.x);
      expect(restored.position?.y, geometry.position?.y);
      expect(restored.runState, geometry.runState);
    });

    test('a maximized geometry keeps its windowed size for later restore', () {
      final geometry = _windowed(
        x: 10,
        y: 10,
      ).copyWith(runState: WindowRunState.maximized);

      final restored = WindowGeometry.fromJson(geometry.toJson());

      expect(restored.runState, WindowRunState.maximized);
      expect(restored.windowedSize, geometry.windowedSize);
    });

    test('an unrecognised run state decodes as windowed, not a crash', () {
      final json = _windowed(x: 0, y: 0).toJson();
      json['runState'] = 'levitating';

      final restored = WindowGeometry.fromJson(json);

      expect(restored.runState, WindowRunState.windowed);
    });

    test('a null position round-trips as null, not a missing key throwing', () {
      const geometry = WindowGeometry.fallback;

      final restored = WindowGeometry.fromJson(geometry.toJson());

      expect(restored.position, isNull);
    });
  });
}
