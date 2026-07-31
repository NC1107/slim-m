// SPDX-License-Identifier: Apache-2.0
/// [loadRealFonts] used to guard the Lucide lookup with `existsSync()` and
/// silently skip it when the file could not be found, so a wrong pub cache
/// path meant the icon font never loaded and nothing in the run said so: the
/// CI overflow gate would measure a layout with every glyph an empty square
/// as though it were the real thing that ships.
library;

import 'package:flutter_test/flutter_test.dart';

import 'ui_snapshot_support.dart';

void main() {
  test('a Lucide font that cannot be found fails the fixture, rather than '
      'silently leaving every icon unloaded', () {
    expect(
      () => loadRealFonts(pubCacheOverride: '/definitely/not/a/pub/cache'),
      throwsA(anything),
    );
  });
}
