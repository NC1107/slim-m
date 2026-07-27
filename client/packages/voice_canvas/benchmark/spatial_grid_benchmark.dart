// SPDX-License-Identifier: Apache-2.0
/// Phase 5 spike: does uniform-grid viewport culling fit a 60fps frame at the
/// roadmap's soft caps, and is it worth having over a linear scan.
///
/// Run with `dart run benchmark/spatial_grid_benchmark.dart`, or AOT-compile
/// first for numbers that resemble a Flutter release build. `--json` emits a
/// machine-readable record instead of the table.
library;

import 'dart:convert';
import 'dart:io';

import 'package:slimm_voice_canvas/spatial_grid.dart';

import 'harness.dart';

const _counts = <int>[1000, 5000, 10000, 20000, 30000, 40000, 50000, 100000];
const _cellSizes = <double>[256, 512, 1024, 2048, 4096, 8192, 16384];

bool _quiet = false;

void main(List<String> args) {
  final asJson = args.contains('--json');
  _quiet = asJson;
  final results = <BenchResult>[];
  final notes = <String, Object>{};

  results.addAll(_scaling(notes));
  results.addAll(_shapes(notes));
  results.addAll(_zoom(notes));
  results.addAll(_cellSweep(notes));
  results.addAll(_buildCost());

  if (asJson) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object>{
        'harness': 'voice_canvas spatial grid spike',
        'dart': Platform.version,
        'results': results.map((r) => r.toJson()).toList(),
        'notes': notes,
      }),
    );
    return;
  }
  stdout.writeln('checksum ${checksum & 0xffff}');
  for (final entry in notes.entries) {
    stdout.writeln('note ${entry.key}: ${entry.value}');
  }
}

/// Throughput at the roadmap counts, grid against the linear-scan control,
/// with a viewport over the busiest part of a realistic world.
List<BenchResult> _scaling(Map<String, Object> notes) {
  final out = <BenchResult>[];
  for (final count in _counts) {
    final grid = buildWorld(
      count: count,
      cellSize: 2048,
      shape: WorldShape.hotspot,
    );
    final cull = CullResult();
    final vp = viewportAt(0, 0, 1);
    grid.queryGrid(vp[0], vp[1], vp[2], vp[3], cull);
    notes['scaling_n${count}_visible'] = cull.slots.length;
    notes['scaling_n${count}_candidates'] = cull.candidates;
    notes['scaling_n${count}_cells'] = cull.cellsVisited;
    notes['scaling_n${count}_occupied_cells'] = grid.occupiedCells;

    out.add(
      _row('grid   n=$count hotspot zoom=1', () {
        grid.queryGrid(vp[0], vp[1], vp[2], vp[3], cull);
        return cull.slots.length;
      }),
    );
    out.add(
      _row('linear n=$count hotspot zoom=1', () {
        grid.queryLinear(vp[0], vp[1], vp[2], vp[3], cull);
        return cull.slots.length;
      }),
    );
  }
  return out;
}

/// The bad cases: one overloaded bucket, and objects far larger than a cell.
List<BenchResult> _shapes(Map<String, Object> notes) {
  final out = <BenchResult>[];
  for (final shape in WorldShape.values) {
    for (final count in const <int>[5000, 20000]) {
      final grid = buildWorld(count: count, cellSize: 2048, shape: shape);
      final cull = CullResult();
      final vp = viewportAt(0, 0, 1);
      grid.queryGrid(vp[0], vp[1], vp[2], vp[3], cull);
      final key = '${shape.name}_n$count';
      notes['${key}_visible'] = cull.slots.length;
      notes['${key}_candidates'] = cull.candidates;
      notes['${key}_dup_factor'] = double.parse(
        (grid.bucketEntries / grid.length).toStringAsFixed(2),
      );

      out.add(
        _row('grid   n=$count ${shape.name} zoom=1', () {
          grid.queryGrid(vp[0], vp[1], vp[2], vp[3], cull);
          return cull.slots.length;
        }),
      );
    }
  }
  return out;
}

/// Zooming out is where a grid stops being an optimisation, because the cell
/// count it must probe grows with world area while the object count does not.
List<BenchResult> _zoom(Map<String, Object> notes) {
  final out = <BenchResult>[];
  final grid = buildWorld(
    count: 20000,
    cellSize: 2048,
    shape: WorldShape.hotspot,
  );
  final cull = CullResult();
  for (final zoom in const <double>[1.0, 0.1, 0.01, 0.001]) {
    final vp = viewportAt(0, 0, zoom);
    grid.queryGrid(vp[0], vp[1], vp[2], vp[3], cull);
    notes['zoom${zoom}_cells'] = cull.cellsVisited;
    notes['zoom${zoom}_visible'] = cull.slots.length;

    out.add(
      _row('grid     n=20000 hotspot zoom=$zoom', () {
        grid.queryGrid(vp[0], vp[1], vp[2], vp[3], cull);
        return cull.slots.length;
      }),
    );
    out.add(
      _row('adaptive n=20000 hotspot zoom=$zoom', () {
        grid.query(vp[0], vp[1], vp[2], vp[3], cull);
        return cull.slots.length;
      }),
    );
  }

  // Zoomed out far enough to frame the whole bounded world. The raw grid is
  // not measured here; at 2048px cells it would probe 23.8M cells per frame.
  final fit = <double>[
    -kWorldSpan / 2,
    -kWorldSpan / 2,
    kWorldSpan / 2,
    kWorldSpan / 2
  ];
  final span = (kWorldSpan / 2048).ceil();
  notes['fit_world_grid_cells_analytic'] = span * span;
  out.add(
    _row('adaptive n=20000 hotspot fit-whole-world', () {
      grid.query(fit[0], fit[1], fit[2], fit[3], cull);
      return cull.slots.length;
    }),
  );
  notes['fit_world_visible'] = cull.slots.length;
  return out;
}

/// How much getting the cell size wrong actually costs, at the Linux soft cap.
List<BenchResult> _cellSweep(Map<String, Object> notes) {
  final out = <BenchResult>[];
  for (final cellSize in _cellSizes) {
    final grid = buildWorld(
      count: 20000,
      cellSize: cellSize,
      shape: WorldShape.hotspot,
    );
    final cull = CullResult();
    final vp = viewportAt(0, 0, 1);
    grid.queryGrid(vp[0], vp[1], vp[2], vp[3], cull);
    final key = 'cell${cellSize.toInt()}';
    notes['${key}_candidates'] = cull.candidates;
    notes['${key}_visible'] = cull.slots.length;
    notes['${key}_cells'] = cull.cellsVisited;
    notes['${key}_occupied'] = grid.occupiedCells;
    notes['${key}_dup_factor'] = double.parse(
      (grid.bucketEntries / grid.length).toStringAsFixed(2),
    );

    out.add(
      _row('grid   n=20000 hotspot cell=${cellSize.toInt()}', () {
        grid.queryGrid(vp[0], vp[1], vp[2], vp[3], cull);
        return cull.slots.length;
      }),
    );
  }
  return out;
}

/// Indexing cost, which is the other half of the cell-size tradeoff: a smaller
/// cell culls no worse but spreads every object over more buckets.
List<BenchResult> _buildCost() {
  final out = <BenchResult>[];
  for (final cellSize in _cellSizes) {
    final boxes = generateBoxes(
      count: 20000,
      cellSize: cellSize,
      shape: WorldShape.hotspot,
    );
    out.add(
      _row(
        'build  n=20000 hotspot cell=${cellSize.toInt()}',
        () => indexBoxes(boxes, cellSize).length,
        floor: const Duration(milliseconds: 60),
      ),
    );
  }
  return out;
}

BenchResult _row(String name, int Function() body, {Duration? floor}) {
  final result =
      floor == null ? bench(name, body) : bench(name, body, floor: floor);
  if (!_quiet) {
    stdout.writeln(result);
  }
  return result;
}
