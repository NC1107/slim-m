// SPDX-License-Identifier: Apache-2.0
/// [WindowGeometryStore.read] healing a persisted splash-sized geometry back
/// to [WindowGeometry.fallback] - the read-time half of the fix for the
/// client-v0.58.0 regression that let a splash-sized geometry get persisted
/// in the first place. No window, no platform channel: `shared_preferences`
/// is mocked in-memory, the same as every other test in this directory that
/// touches a [WindowGeometryStore].
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/desktop/window_geometry.dart';
import 'package:slimm_app/src/desktop/window_geometry_store.dart';

Future<WindowGeometryStore> _storeWithRaw(String raw) async {
  SharedPreferences.setMockInitialValues({windowGeometryPreferenceKey: raw});
  return WindowGeometryStore(await SharedPreferences.getInstance());
}

void main() {
  group('WindowGeometryStore.read healing', () {
    test('the owner\'s own corrupted preferences.json value heals to the '
        'fallback geometry, not the persisted 380x508', () async {
      // Copied verbatim from the bug report: a real shared_preferences.json value pulled off client-v0.58.0.
      const ownerRaw =
          '{"windowedSize":{"width":380.0,"height":508.0},'
          '"position":{"x":45.0,"y":45.0,"width":380.0,"height":508.0},'
          '"runState":"maximized"}';
      final store = await _storeWithRaw(ownerRaw);

      final healed = store.read();

      expect(healed, isNotNull);
      expect(healed!.windowedSize, WindowGeometry.fallback.windowedSize);
      expect(healed.position, isNull);
      expect(healed.runState, WindowRunState.windowed);
    });

    test('a legitimate saved geometry round-trips untouched', () async {
      const geometry = WindowGeometry(
        windowedSize: WindowSize(width: 1440, height: 900),
        position: WindowRect(x: 60, y: 30, width: 1440, height: 900),
        runState: WindowRunState.windowed,
      );
      final store = await _storeWithRaw(jsonEncode(geometry.toJson()));

      final read = store.read();

      expect(read, isNotNull);
      expect(read!.windowedSize, geometry.windowedSize);
      expect(read.position?.x, geometry.position?.x);
      expect(read.runState, geometry.runState);
    });

    test('a legitimate saved maximized geometry restores maximized, not just a '
        'windowed fallback', () async {
      const geometry = WindowGeometry(
        windowedSize: WindowSize(width: 1400, height: 900),
        runState: WindowRunState.maximized,
      );
      final store = await _storeWithRaw(jsonEncode(geometry.toJson()));

      final read = store.read();

      expect(read?.runState, WindowRunState.maximized);
      expect(read?.windowedSize, geometry.windowedSize);
    });

    test('nothing saved yet still reads as null, not the fallback', () async {
      SharedPreferences.setMockInitialValues({});
      final store = WindowGeometryStore(await SharedPreferences.getInstance());

      expect(store.read(), isNull);
    });

    test('a corrupt, undecodable blob still reads as null', () async {
      final store = await _storeWithRaw('not json at all');

      expect(store.read(), isNull);
    });
  });
}
