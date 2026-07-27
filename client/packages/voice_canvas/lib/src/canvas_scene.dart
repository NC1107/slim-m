// SPDX-License-Identifier: Apache-2.0
/// The canvas hot path: a plain [ChangeNotifier] that owns the spatial index
/// and drives the paint layer directly.
///
/// This type is the whole of the Phase 5 second bet. It is a `Listenable`, so
/// a `CustomPainter` built with `repaint: scene` repaints without any widget
/// in the tree rebuilding, which is what keeps Riverpod out of the render loop.
library;

import 'package:flutter/foundation.dart';

import 'spatial_grid.dart';

class CanvasScene extends ChangeNotifier {
  CanvasScene({double cellSize = 1024, int capacity = 1024})
      : _grid = UniformGrid(cellSize: cellSize, capacity: capacity);

  final UniformGrid _grid;
  final CullResult _cull = CullResult();

  double _left = 0;
  double _top = 0;
  double _right = 0;
  double _bottom = 0;
  CullStrategy _strategy = CullStrategy.grid;

  int get objectCount => _grid.length;

  /// Slots the last cull kept, in index order.
  ///
  /// Reused between frames rather than reallocated, so the caller must read it
  /// during paint and never retain it.
  List<int> get visible => _cull.slots;

  CullStrategy get strategy => _strategy;
  int get candidates => _cull.candidates;
  int get cellsVisited => _cull.cellsVisited;

  /// Adds an object without notifying, so a bulk snapshot load costs one
  /// notification rather than one per object.
  int add(double left, double top, double right, double bottom) =>
      _grid.insert(left, top, right, bottom);

  /// Moves the camera and re-culls. The pan and zoom hot path.
  void setViewport(double left, double top, double right, double bottom) {
    _left = left;
    _top = top;
    _right = right;
    _bottom = bottom;
    recull();
  }

  /// Re-runs the cull against the current camera and tells the paint layer.
  void recull() {
    _strategy = _grid.query(_left, _top, _right, _bottom, _cull);
    notifyListeners();
  }
}
