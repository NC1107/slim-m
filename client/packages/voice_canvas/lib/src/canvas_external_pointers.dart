// SPDX-License-Identifier: Apache-2.0
/// How many pointers are down somewhere in the canvas pane's own tree that
/// [CanvasSurface] itself never sees a `PointerDownEvent` for - a presence
/// tile sits in its own opaque layer above the surface (see
/// `canvas_presence_tile.dart`'s own doc), so a second finger landing there
/// is invisible to the surface's own pointer count unless something else
/// reports it. `CanvasSurface`'s grab-pan and pinch-cancellation logic both
/// read this alongside their own count, so a pinch or a middle-button drag
/// behaves the same whichever layer a pointer happened to land on.
library;

/// A plain counter, not a `ChangeNotifier`: every caller reads and writes it
/// synchronously inside a pointer-event handler, never during a build, so
/// nothing here needs to trigger a rebuild.
class CanvasExternalPointers {
  int _count = 0;

  int get count => _count;

  void add() => _count++;

  void remove() {
    if (_count > 0) _count--;
  }
}
