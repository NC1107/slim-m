// SPDX-License-Identifier: Apache-2.0
/// Uniform-grid viewport culling for the Voice Canvas, plus the linear-scan
/// control it has to beat to justify existing.
///
/// Deliberately free of `dart:ui` so the benchmark harness can AOT-compile and
/// run it on the plain Dart VM, where nothing else shares the isolate.
library;

import 'dart:typed_data';

/// Result of a cull, reused across frames so a steady-state pan allocates
/// nothing on the hot path.
class CullResult {
  CullResult() : slots = <int>[];

  final List<int> slots;

  /// Candidates the broad phase produced, before the exact overlap test.
  /// The ratio against [slots] is what says whether a cell size is sane.
  int candidates = 0;

  /// Grid cells the broad phase probed. Blows up when the camera zooms out,
  /// which is the failure mode the adaptive path exists to dodge.
  int cellsVisited = 0;

  void _reset() {
    slots.clear();
    candidates = 0;
    cellsVisited = 0;
  }
}

/// How a query chose to answer.
enum CullStrategy { grid, linear }

/// A sparse uniform grid over an unbounded world.
///
/// Sparse rather than dense because the roadmap's plus-or-minus 5,000,000px
/// world at 2048px cells is 23.8M cells, which no client can hold as an array.
class UniformGrid {
  UniformGrid({required this.cellSize, int capacity = 1024})
      : assert(cellSize > 0, 'cellSize must be positive'),
        _bounds = Float64List(capacity * 4),
        _stamp = Int32List(capacity);

  final double cellSize;

  final Map<int, List<int>> _cells = <int, List<int>>{};
  Float64List _bounds;
  Int32List _stamp;
  int _count = 0;
  int _queryId = 0;

  /// Number of objects indexed.
  int get length => _count;

  /// Occupied cells. Sparse-grid memory is proportional to this, not to world
  /// area, which is the whole reason the grid is a hash map.
  int get occupiedCells => _cells.length;

  /// Total slot entries across all buckets. Divided by [length] this is the
  /// duplication factor an object-larger-than-a-cell world pays.
  int get bucketEntries {
    var total = 0;
    for (final bucket in _cells.values) {
      total += bucket.length;
    }
    return total;
  }

  /// Adds an axis-aligned box and returns its dense slot.
  int insert(double left, double top, double right, double bottom) {
    if (_count == _stamp.length) {
      _grow();
    }
    final slot = _count++;
    final base = slot << 2;
    _bounds[base] = left;
    _bounds[base + 1] = top;
    _bounds[base + 2] = right;
    _bounds[base + 3] = bottom;

    final cx0 = (left / cellSize).floor();
    final cy0 = (top / cellSize).floor();
    final cx1 = (right / cellSize).floor();
    final cy1 = (bottom / cellSize).floor();
    for (var cy = cy0; cy <= cy1; cy++) {
      for (var cx = cx0; cx <= cx1; cx++) {
        (_cells[_key(cx, cy)] ??= <int>[]).add(slot);
      }
    }
    return slot;
  }

  /// Broad phase over grid cells, then an exact overlap test per candidate.
  void queryGrid(
    double left,
    double top,
    double right,
    double bottom,
    CullResult out,
  ) {
    out._reset();
    final stamp = _nextStamp();
    final cx0 = (left / cellSize).floor();
    final cy0 = (top / cellSize).floor();
    final cx1 = (right / cellSize).floor();
    final cy1 = (bottom / cellSize).floor();

    for (var cy = cy0; cy <= cy1; cy++) {
      for (var cx = cx0; cx <= cx1; cx++) {
        out.cellsVisited++;
        final bucket = _cells[_key(cx, cy)];
        if (bucket == null) {
          continue;
        }
        for (var i = 0; i < bucket.length; i++) {
          final slot = bucket[i];
          if (_stamp[slot] == stamp) {
            continue;
          }
          _stamp[slot] = stamp;
          out.candidates++;
          final base = slot << 2;
          if (_bounds[base] > right ||
              _bounds[base + 2] < left ||
              _bounds[base + 1] > bottom ||
              _bounds[base + 3] < top) {
            continue;
          }
          out.slots.add(slot);
        }
      }
    }
  }

  /// The control: every object tested once, straight down two typed arrays.
  void queryLinear(
    double left,
    double top,
    double right,
    double bottom,
    CullResult out,
  ) {
    out._reset();
    out.candidates = _count;
    for (var slot = 0; slot < _count; slot++) {
      final base = slot << 2;
      if (_bounds[base] > right ||
          _bounds[base + 2] < left ||
          _bounds[base + 1] > bottom ||
          _bounds[base + 3] < top) {
        continue;
      }
      out.slots.add(slot);
    }
  }

  /// Picks whichever phase does less work for this viewport.
  ///
  /// Without this a fully zoomed-out camera probes every cell in the world,
  /// which is unboundedly worse than just testing every object once.
  CullStrategy query(
    double left,
    double top,
    double right,
    double bottom,
    CullResult out,
  ) {
    final spanX = (right / cellSize).floor() - (left / cellSize).floor() + 1;
    final spanY = (bottom / cellSize).floor() - (top / cellSize).floor() + 1;
    if (spanX * spanY > _count) {
      queryLinear(left, top, right, bottom, out);
      return CullStrategy.linear;
    }
    queryGrid(left, top, right, bottom, out);
    return CullStrategy.grid;
  }

  int _nextStamp() {
    if (_queryId == 0x7fffffff) {
      _stamp.fillRange(0, _stamp.length, 0);
      _queryId = 0;
    }
    return ++_queryId;
  }

  void _grow() {
    final grown = Float64List(_bounds.length * 2)
      ..setRange(0, _bounds.length, _bounds);
    _bounds = grown;
    final stamps = Int32List(_stamp.length * 2)
      ..setRange(0, _stamp.length, _stamp);
    _stamp = stamps;
  }

  /// Two 32-bit signed cell coordinates packed into one 64-bit VM int, so a
  /// bucket lookup hashes a scalar rather than an allocated point.
  static int _key(int cx, int cy) =>
      (cx & 0xffffffff) << 32 | (cy & 0xffffffff);
}
