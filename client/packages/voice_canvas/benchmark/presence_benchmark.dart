// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Phase 6 spike: what camera-bubble placement and viewport hysteresis cost,
/// per recomputation, at participant counts this product targets and well
/// past them.
///
/// This does not - cannot, without a real SFU and a real device - measure
/// what a `VideoTrackRenderer` costs to composite. What it answers is the one
/// question this package can settle on its own: whether the pure bookkeeping
/// that decides which bubbles to mount is itself cheap enough to run on
/// every camera pan, which it has to be regardless of how many of those
/// bubbles turn out to hold a live video texture.
///
/// Hosted by `flutter test`, the same reason `hot_path_benchmark.dart` is:
/// `Rect` and friends are `dart:ui` types, which the plain Dart VM `dart run`
/// harness the other benchmarks use cannot load.
/// Run with `flutter test benchmark/presence_benchmark.dart`.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'harness.dart';

/// 2-8 is the product's own stated call size (STRATEGY.md); the rest is
/// margin well past anything a self-hosted friend group's canvas would hold.
const _counts = <int>[2, 8, 20, 50, 200];

void main() {
  test('camera-bubble placement and hysteresis cost', () {
    final results = <BenchResult>[..._layout(), ..._visibility()];
    debugPrint('checksum ${checksum & 0xffff}');
    for (final r in results) {
      debugPrint(r.toString());
    }
  });
}

List<BenchResult> _layout() {
  const layout = CanvasPresenceLayout();
  final out = <BenchResult>[];
  for (final count in _counts) {
    final ids = List.generate(count, (i) => 'participant-$i');
    out.add(
      bench('arrange, $count participants', () {
        final placed = layout.arrange(ids);
        return placed.length;
      }),
    );
  }
  return out;
}

/// A panning camera: every recomputation shifts the viewport a little, so
/// bubbles cross the hysteresis bands rather than sitting still - the case
/// that actually exercises the two-threshold logic rather than answering the
/// same cached membership every time.
List<BenchResult> _visibility() {
  const layout = CanvasPresenceLayout();
  final out = <BenchResult>[];
  final rng = Random(20260805);
  for (final count in _counts) {
    final ids = List.generate(count, (i) => 'participant-$i');
    final bubbles = layout.arrange(ids);
    final visibility = CanvasPresenceVisibility();
    var x = 0.0;
    out.add(
      bench('viewport hysteresis, $count participants', () {
        x += rng.nextDouble() * 40 - 20;
        final viewport = Rect.fromLTWH(x, 0, 1000, 1000);
        return visibility.update(viewport, bubbles).length;
      }),
    );
  }
  return out;
}
