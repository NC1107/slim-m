// SPDX-License-Identifier: Apache-2.0
part of 'canvas_document.dart';

/// The document's read-only spatial-index queries: the slot a live object
/// occupies, whether one is known or alive, and the per-kind live counts the
/// accessibility summary reads. Split from `canvas_document.dart` for the line
/// budget, as an `extension` in a `part of` file so it keeps access to the
/// private slot table without exposing it - the shape `CanvasDocumentSelection`
/// already uses.
extension CanvasDocumentQueries on CanvasDocument {
  /// The stroke at [slot]. Only safe on a slot [paintOrder] just handed back;
  /// a slot from an arbitrary cull may have since been removed or killed, and
  /// [strokeIfAlive] is the one to use there.
  CanvasStroke strokeAt(int slot) => _strokes[slot]!;

  /// The stroke at [slot], or null if it was never a real object, has been
  /// removed, or failed to land.
  CanvasStroke? strokeIfAlive(int slot) {
    final stroke = _strokes[slot];
    return (stroke != null && stroke.alive) ? stroke : null;
  }

  /// The slot [id] currently occupies, or null if it is unknown or no longer
  /// alive. The companion to [strokeAt], which takes a slot: together they
  /// let a caller holding an id reach the object without this document
  /// handing out its own map.
  int? slotOf(String id) {
    final slot = _slotById[id];
    if (slot == null) return null;
    return (_strokes[slot]?.alive ?? false) ? slot : null;
  }

  bool knows(String id) => _slotById.containsKey(id);

  /// True if [id] names a stroke this document currently shows as alive: it
  /// landed (or was drawn locally) and has not since been killed or removed.
  ///
  /// The distinction undo needs: a gesture's placement may have already
  /// failed for good by the time somebody undoes it, and a failed one needs
  /// no further removal, unlike a genuinely committed one.
  bool isAlive(String id) {
    final slot = _slotById[id];
    return slot != null && (_strokes[slot]?.alive ?? false);
  }

  /// Live object counts by kind, across the whole document rather than only
  /// what the last cull kept - the one query the accessibility summary
  /// needs and nothing else here does, so it is a scan rather than a
  /// maintained counter. Cheap even at the channel's own object ceiling (the
  /// server itself measured a plain scan at 20,000 rows as 1.56ms), and it
  /// is only ever asked for when a screen-reader user opens the activity
  /// panel, never once per frame the way [objectCount] is.
  ({int strokes, int images, int notes, int shapes}) get liveCountsByKind {
    var strokes = 0;
    var images = 0;
    var notes = 0;
    var shapes = 0;
    for (final stroke in _strokes) {
      if (stroke == null || !stroke.alive) continue;
      switch (stroke.kind) {
        case CanvasObjectKind.image:
          images++;
        case CanvasObjectKind.note:
          notes++;
        case CanvasObjectKind.shape:
          shapes++;
        case CanvasObjectKind.stroke:
          strokes++;
      }
    }
    return (strokes: strokes, images: images, notes: notes, shapes: shapes);
  }
}
