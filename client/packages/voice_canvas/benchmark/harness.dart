// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Timing harness and synthetic worlds for the Phase 5 canvas spike.
///
/// Kept separate from the benchmark bodies so the measurement rules live in
/// one place and cannot drift between scenarios.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:slimm_voice_canvas/spatial_grid.dart';

/// Consumes every measured result so the optimizer cannot delete the work.
/// Printed once at the end; the value itself is meaningless.
int checksum = 0;

class BenchResult {
  BenchResult(this.name, this.minNs, this.medianNs, this.batch, this.trials);

  final String name;
  final double minNs;
  final double medianNs;
  final int batch;
  final int trials;

  /// Fraction of a 60fps frame the median run consumes.
  double get frameFraction => medianNs / 16600000.0;

  Map<String, Object> toJson() => <String, Object>{
        'name': name,
        'min_ns': double.parse(minNs.toStringAsFixed(1)),
        'median_ns': double.parse(medianNs.toStringAsFixed(1)),
        'batch': batch,
        'trials': trials,
      };

  @override
  String toString() {
    final us = (medianNs / 1000).toStringAsFixed(3);
    final pct = (frameFraction * 100).toStringAsFixed(3);
    return '${name.padRight(52)} ${us.padLeft(10)} us  ${pct.padLeft(8)}% frame';
  }
}

/// Times [body] with an adaptive batch size, reporting min and median.
///
/// Batch size is grown until one batch spans at least [floor], so the
/// Stopwatch read and the loop bookkeeping stay far below the signal instead
/// of being most of it.
BenchResult bench(
  String name,
  int Function() body, {
  Duration warmup = const Duration(milliseconds: 150),
  Duration floor = const Duration(milliseconds: 25),
  int trials = 9,
}) {
  final warm = Stopwatch()..start();
  var warmOps = 0;
  while (warm.elapsedMicroseconds < warmup.inMicroseconds) {
    checksum ^= body();
    warmOps++;
  }
  warm.stop();

  final perOpNs = warm.elapsedMicroseconds * 1000 / max(warmOps, 1);
  var batch = max(1, (floor.inMicroseconds * 1000 / max(perOpNs, 1)).ceil());
  batch = min(batch, 1 << 22);

  final samples = <double>[];
  for (var t = 0; t < trials; t++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < batch; i++) {
      checksum ^= body();
    }
    sw.stop();
    samples.add(sw.elapsedMicroseconds * 1000 / batch);
  }
  samples.sort();
  return BenchResult(
      name, samples.first, samples[samples.length ~/ 2], batch, trials);
}

/// The full bounded world from the roadmap, plus or minus 5,000,000px.
const double kWorldSpan = 10000000.0;

/// About twenty screens across, which is what a busy shared board looks like
/// before anyone has panned far.
const double kBoardSpan = 51200.0;

/// How a synthetic world places its objects.
enum WorldShape {
  /// Objects spread evenly over a board-sized area. The friendly case.
  uniform,

  /// Every object inside a single grid cell, so one bucket holds them all.
  clustered,

  /// Objects eight cells wide, so each occupies many buckets.
  oversized,

  /// A realistic mix: a dense worked-on region plus a sparse long tail
  /// scattered over the full bounded world.
  hotspot,
}

/// The world span each shape is generated over, chosen so a screen-sized
/// viewport at the origin actually intersects content.
double spanFor(WorldShape shape) => switch (shape) {
      WorldShape.uniform => kBoardSpan,
      WorldShape.clustered => kBoardSpan,
      WorldShape.oversized => kBoardSpan,
      WorldShape.hotspot => kWorldSpan,
    };

/// Generates [count] boxes as flat left/top/right/bottom quads.
///
/// Separate from indexing so a build benchmark measures the index and not the
/// random number generator.
Float64List generateBoxes({
  required int count,
  required double cellSize,
  required WorldShape shape,
  double? worldSize,
  int seed = 20260726,
}) {
  final rng = Random(seed);
  final boxes = Float64List(count * 4);
  final half = (worldSize ?? spanFor(shape)) / 2;

  for (var i = 0; i < count; i++) {
    late double x;
    late double y;
    var w = 64.0 + rng.nextDouble() * 448.0;
    var h = 64.0 + rng.nextDouble() * 448.0;

    switch (shape) {
      case WorldShape.uniform:
        x = -half + rng.nextDouble() * half * 2;
        y = -half + rng.nextDouble() * half * 2;
      case WorldShape.clustered:
        x = rng.nextDouble() * cellSize * 0.5;
        y = rng.nextDouble() * cellSize * 0.5;
        w = 32.0;
        h = 32.0;
      case WorldShape.oversized:
        x = -half + rng.nextDouble() * half * 2;
        y = -half + rng.nextDouble() * half * 2;
        w = cellSize * 8;
        h = cellSize * 8;
      case WorldShape.hotspot:
        if (rng.nextDouble() < 0.8) {
          x = -6000 + rng.nextDouble() * 12000;
          y = -6000 + rng.nextDouble() * 12000;
        } else {
          x = -half + rng.nextDouble() * half * 2;
          y = -half + rng.nextDouble() * half * 2;
        }
    }
    final base = i << 2;
    boxes[base] = x;
    boxes[base + 1] = y;
    boxes[base + 2] = x + w;
    boxes[base + 3] = y + h;
  }
  return boxes;
}

/// Indexes pre-generated [boxes], which is the part a build benchmark times.
UniformGrid indexBoxes(Float64List boxes, double cellSize) {
  final count = boxes.length >> 2;
  final grid = UniformGrid(cellSize: cellSize, capacity: count);
  for (var i = 0; i < count; i++) {
    final base = i << 2;
    grid.insert(boxes[base], boxes[base + 1], boxes[base + 2], boxes[base + 3]);
  }
  return grid;
}

/// Convenience wrapper for the query scenarios, which do not time indexing.
UniformGrid buildWorld({
  required int count,
  required double cellSize,
  required WorldShape shape,
  double? worldSize,
  int seed = 20260726,
}) =>
    indexBoxes(
      generateBoxes(
        count: count,
        cellSize: cellSize,
        shape: shape,
        worldSize: worldSize,
        seed: seed,
      ),
      cellSize,
    );

/// A 2560x1440 desktop viewport, scaled by [zoom]. Zoom 1 is one world pixel
/// per screen pixel; smaller values pull the camera back.
List<double> viewportAt(double cx, double cy, double zoom) {
  final w = 2560 / zoom;
  final h = 1440 / zoom;
  return <double>[cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2];
}
