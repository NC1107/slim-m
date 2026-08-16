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

  int get objectCount => _grid.liveLength;

  /// Slots the last cull kept, in index order.
  ///
  /// Reused between frames rather than reallocated, so the caller must read it
  /// during paint and never retain it.
  List<int> get visible => _cull.slots;

  CullStrategy get strategy => _strategy;
  int get candidates => _cull.candidates;
  int get cellsVisited => _cull.cellsVisited;

  /// Every slot the grid has ever handed out, parked ones included.
  ///
  /// Beside [objectCount], which counts only live ones, because the gap
  /// between the two is what a repeated remove-then-add leaks: a parked slot
  /// costs nothing on the grid branch but is still walked by the linear one,
  /// and it never comes back. A drag that reindexes per pointer event is the
  /// way that gap opens, so this is the number a test watches to prove it
  /// does not.
  int get slotCount => _grid.length;

  /// Adds an object without notifying, so a bulk snapshot load costs one
  /// notification rather than one per object.
  int add(double left, double top, double right, double bottom) =>
      _grid.insert(left, top, right, bottom);

  /// Removes an object without notifying, matching [add]'s batching: a
  /// caller removing several objects at once calls [recull] itself, once,
  /// rather than paying a cull per removed object. `_grid` is private, so
  /// this is the only way to publish a removal through the scene.
  void remove(int slot) => _grid.remove(slot);

  /// Repositions a slot already in the index, keeping its number, without
  /// notifying - the same batching [add] and [remove] keep. See
  /// [UniformGrid.move] for why a drag must not use remove-then-add.
  void move(int slot, double left, double top, double right, double bottom) =>
      _grid.move(slot, left, top, right, bottom);

  /// Empties the index for a document-wide reset, without notifying - the
  /// same reason [add] and [remove] do not.
  ///
  /// [_cull] is cleared too, not only the grid: it caches the last cull's
  /// slots until the next one overwrites them, and after a reset those slots
  /// may no longer be valid indices into anything, so [visible] must not go
  /// on answering with them.
  void reset() {
    _grid.reset();
    _cull.clear();
  }

  /// Culls an arbitrary rectangle into the caller's own [CullResult], never
  /// touching [visible] or repainting. Hit testing needs a cull that does
  /// not disturb what is on screen.
  CullStrategy queryRect(
    double left,
    double top,
    double right,
    double bottom,
    CullResult out,
  ) =>
      _grid.query(left, top, right, bottom, out);

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
