// SPDX-License-Identifier: Apache-2.0
/// What a canvas surface holds: the spatial index, the camera, and the side
/// table [CanvasScene] deliberately does not carry.
///
/// A [ChangeNotifier] rather than anything Riverpod-shaped, and that is a
/// correctness property rather than a preference: a provider's value is not
/// observable until the event loop turns, so a stream physically cannot
/// deliver inside the frame that produced it. Painters take this as their
/// `repaint` listenable and no widget rebuilds when the camera moves.
library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'canvas_scene.dart';
import 'canvas_stroke.dart';

export 'canvas_stroke.dart';

part 'canvas_document_selection.dart';

/// The document: index, camera, strokes, and dedupe by id.
class CanvasDocument extends ChangeNotifier {
  CanvasDocument();

  final CanvasScene scene = CanvasScene();

  /// Null past a removal or a clear: the slot address stays reserved
  /// ([UniformGrid] never renumbers) but the stroke itself is freed, which is
  /// the largest memory win available since a `Path` and its points dominate
  /// this package's footprint.
  final List<CanvasStroke?> _strokes = <CanvasStroke?>[];
  final Map<String, int> _slotById = <String, int>{};
  final List<int> _order = <int>[];

  /// Ids the server has told this document to drop, so a viewport read still
  /// in flight when the removal landed cannot resurrect them. The order
  /// queue is what makes eviction FIFO once [maxRemovedIdsTracked] is
  /// reached, since no read in flight can name more live ids than the
  /// channel's own ceiling.
  final Set<String> _removedIds = <String>{};
  final Queue<String> _removedOrder = Queue<String>();

  Camera _camera = const Camera();
  Size _viewport = Size.zero;

  /// Bumped whenever the set of objects changes, never when the camera moves,
  /// so an announcement can be rebuilt on content without firing at pan rate.
  final ValueNotifier<int> objectCount = ValueNotifier<int>(0);

  /// The one object currently selected for a resize or reorder, or null.
  /// A document-level notifier rather than caller-held state, the same
  /// reason [objectCount] is: the selection painter needs to repaint on a
  /// change here with no widget rebuild in between, the render-loop rule
  /// this whole package exists to keep.
  final ValueNotifier<String?> selectedObjectId = ValueNotifier<String?>(null);

  /// The one object this client's own pointer is currently dragging or
  /// resizing, or null - a narrower, shorter-lived thing than
  /// [selectedObjectId], which stays set for as long as the Move tool holds
  /// a selection. `StrokePainter` reads this to decide which image earns
  /// the app layer's `AppShadows.float` treatment (named here only, this
  /// package carries no design-system dependency, so the shadow itself
  /// arrives as a plain value), a shadow only while an object is literally
  /// off the plane rather than for as long as it merely sits selected.
  final ValueNotifier<String?> elevatedObjectId = ValueNotifier<String?>(null);

  Camera get camera => _camera;
  Size get viewport => _viewport;

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

  /// Slots the last cull kept, in paint order.
  ///
  /// Sorted here rather than taken as the cull emits them: [UniformGrid]
  /// answers in cell order on one branch and slot order on the other, and it
  /// switches between them on zoom, so painting the raw cull would re-layer
  /// overlapping ink as somebody zoomed across the adaptive threshold. The
  /// server pays a sort for `(z_index, seq)` and this is where that answer is
  /// honoured rather than thrown away.
  List<int> get paintOrder {
    _order
      ..clear()
      ..addAll(scene.visible.where((slot) => _strokes[slot]?.alive ?? false));
    _order.sort((a, b) => _strokes[a]!.zIndex.compareTo(_strokes[b]!.zIndex));
    return _order;
  }

  /// Adds a stroke, or returns the slot it already occupies, or refuses one
  /// this document has already been told to drop.
  ///
  /// Dedupe by id is what makes every fetch path safe to repeat: place is
  /// idempotent server-side, so a duplicate from a pan, a live frame or a
  /// reconnect is a no-op here rather than a second mark. The
  /// [_removedIds] check is what stops a viewport read that was already in
  /// flight when a removal landed from resurrecting it, permanently, with
  /// nothing later re-delivering the erase.
  int? applyPlaced(CanvasStrokeInput input) {
    if (_removedIds.contains(input.id)) return null;
    final known = _slotById[input.id];
    if (known != null) {
      final existing = _strokes[known];
      // A duplicate naming a slot this document has since freed is refused.
      if (existing == null) return null;
      existing
        ..zIndex = input.zIndex
        ..seq = input.seq;
      return known;
    }
    final path = Path();
    final points = Float32List(input.points.length);
    for (var i = 0; i + 1 < input.points.length; i += 2) {
      final px = input.points[i];
      final py = input.points[i + 1];
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
      points[i] = px + input.x;
      points[i + 1] = py + input.y;
    }
    if (input.points.length == 2) {
      path.lineTo(input.points[0], input.points[1]);
    }
    final slot = scene.add(
      input.x,
      input.y,
      input.x + input.w,
      input.y + input.h,
    );
    // `scene.add` hands out a dense slot in lockstep with `_strokes`.
    _strokes.add(
      CanvasStroke(
        id: input.id,
        x: input.x,
        y: input.y,
        path: path,
        points: points,
        width: input.width,
        colorKey: input.colorKey,
        zIndex: input.zIndex,
        seq: input.seq,
        authorId: input.authorId,
        kind: input.kind,
        w: input.w,
        h: input.h,
        attachmentId: input.attachmentId,
        text: input.text,
        shapeKind: input.shapeKind,
      ),
    );
    _slotById[input.id] = slot;
    objectCount.value = objectCount.value + 1;
    return slot;
  }

  /// The bounds a live object currently occupies, or null if [id] is unknown
  /// or has been removed. What [moveObject]'s caller needs to compute a drag
  /// delta, and what an undo needs to restore a move's own original box.
  ({double x, double y, double w, double h})? objectBounds(String id) {
    final slot = _slotById[id];
    final stroke = slot == null ? null : _strokes[slot];
    if (stroke == null || !stroke.alive) return null;
    return (x: stroke.x, y: stroke.y, w: stroke.w, h: stroke.h);
  }

  /// Repositions a live object to a new box, reindexing the spatial grid
  /// slot it occupies - a stroke's own points move with it, so a moved
  /// stroke still hit-tests against its drawn shape rather than its old one.
  /// Returns false if [id] is unknown or has been removed.
  ///
  /// The grid never updates a slot in place ([UniformGrid] has no such
  /// operation), so this frees the old slot and inserts a fresh one, the same
  /// remove-then-add [_freeSlot] and [applyPlaced] already do separately.
  bool moveObject(String id, double x, double y, double w, double h) {
    final slot = _slotById[id];
    if (slot == null) return false;
    final stroke = _strokes[slot];
    if (stroke == null || !stroke.alive) return false;
    final dx = x - stroke.x;
    final dy = y - stroke.y;
    final points = Float32List(stroke.points.length);
    for (var i = 0; i < stroke.points.length; i++) {
      points[i] = stroke.points[i] + (i.isEven ? dx : dy);
    }
    scene.remove(slot);
    final newSlot = scene.add(x, y, x + w, y + h);
    _strokes.add(
      CanvasStroke(
        id: stroke.id,
        x: x,
        y: y,
        path: stroke.path.shift(Offset(dx, dy)),
        points: points,
        width: stroke.width,
        colorKey: stroke.colorKey,
        zIndex: stroke.zIndex,
        seq: stroke.seq,
        authorId: stroke.authorId,
        kind: stroke.kind,
        w: w,
        h: h,
        attachmentId: stroke.attachmentId,
        image: stroke.image,
        imageLoadFailed: stroke.imageLoadFailed,
        text: stroke.text,
        shapeKind: stroke.shapeKind,
      ),
    );
    assert(newSlot == _strokes.length - 1, 'scene.add must stay dense');
    _strokes[slot] = null;
    _slotById[id] = newSlot;
    return true;
  }

  /// Attaches a decoded bitmap to a live [CanvasObjectKind.image] object.
  ///
  /// [image] is disposed immediately, rather than attached, if [id] is no
  /// longer alive by the time its decode finishes - the race between a fetch
  /// in flight and a removal landing first - since nothing else would ever
  /// free bytes nobody can reach again.
  void setImageBitmap(String id, ui.Image image) {
    final slot = _slotById[id];
    final stroke = slot == null ? null : _strokes[slot];
    if (stroke == null || !stroke.alive) {
      image.dispose();
      return;
    }
    stroke.image = image;
    stroke.imageLoadFailed = false;
    notifyListeners();
  }

  /// Marks a live [CanvasObjectKind.image] object as one whose bytes could
  /// not be fetched or decoded, so the painter draws a placeholder instead
  /// of leaving it blank. A no-op if [id] is unknown, dead, or already
  /// carries a bitmap - a hydration failure racing behind a fetch that
  /// already landed must not blank out a real image.
  void markImageLoadFailed(String id) {
    final slot = _slotById[id];
    final stroke = slot == null ? null : _strokes[slot];
    if (stroke == null || !stroke.alive || stroke.image != null) return;
    stroke.imageLoadFailed = true;
    notifyListeners();
  }

  /// Detaches and disposes a live object's decoded bitmap, if it holds one,
  /// without removing the object itself.
  ///
  /// The one caller is the app layer's bounded decode cache: evicting an
  /// off-budget bitmap has to free the memory without forgetting the
  /// object, which would need a real removal op nobody sent. The object
  /// simply stops painting until it is fetched and hydrated again, the same
  /// as one still waiting on its first decode.
  void evictImageBitmap(String id) {
    final slot = _slotById[id];
    final stroke = slot == null ? null : _strokes[slot];
    final image = stroke?.image;
    if (image == null) return;
    stroke!.image = null;
    image.dispose();
    notifyListeners();
  }

  /// Marks a stroke as never having landed.
  ///
  /// A different thing from [removeObject]: this means "this commit never
  /// landed", not "this was removed", and the grid keeps the slot rather
  /// than freeing it, since a failed commit never occupied a real object's
  /// address the server could later name.
  void kill(String id) {
    final slot = _slotById[id];
    final stroke = slot == null ? null : _strokes[slot];
    if (stroke == null || !stroke.alive) return;
    stroke.alive = false;
    objectCount.value = objectCount.value - 1;
  }

  /// Removes a placed object by id, or records the id as removed even if
  /// this document never held it - the in-flight-viewport-page race the
  /// removal design exists to close.
  ///
  /// A no-op on an id already removed or never placed at all, so a batched
  /// remove op replaying an id twice, or naming one this pane never
  /// fetched, costs nothing.
  void removeObject(String id) {
    _remember(id);
    final slot = _slotById[id];
    if (slot != null) _freeSlot(slot);
  }

  /// Removes every stroke placed at or below [beforeSeq].
  ///
  /// The `0 <` guard spares a locally drawn stroke, which carries `seq: 0`
  /// until the server confirms it - without it, a clear in flight would
  /// erase ink as it is drawn, before its own placement is even known.
  void clearBelow(int beforeSeq) {
    for (var slot = 0; slot < _strokes.length; slot++) {
      final stroke = _strokes[slot];
      if (stroke != null && stroke.seq > 0 && stroke.seq <= beforeSeq) {
        _remember(stroke.id);
        _freeSlot(slot);
      }
    }
  }

  /// Drops ids from the removed-id tombstone set: a restore, which never
  /// re-materializes a stroke locally since its payload was freed on
  /// removal, so only makes a later fetch of the object able to land again.
  ///
  /// The stale `_slotById` entry has to go too, not only the tombstone:
  /// `applyPlaced` refuses a duplicate naming a slot this document has since
  /// freed regardless of whether the id is still tombstoned, so leaving it
  /// behind would make a restored id un-placeable forever even after the
  /// fetch this method exists to let land.
  void forgetRemoved(Iterable<String> ids) {
    final restored = ids.toSet();
    if (restored.isEmpty) return;
    _removedIds.removeAll(restored);
    _removedOrder.removeWhere(restored.contains);
    _slotById.removeWhere((id, _) => restored.contains(id));
  }

  /// Empties this document entirely: every stroke, the removed-id
  /// tombstones, and the spatial index. Used only for a hard reset of the
  /// whole canvas pane, never for an ordinary removal or clear - the camera
  /// is deliberately untouched, so a reset does not also throw the person's
  /// pan and zoom away.
  void reset() {
    _disposeImages();
    _strokes.clear();
    _slotById.clear();
    _order.clear();
    _removedIds.clear();
    _removedOrder.clear();
    scene.reset();
    objectCount.value = 0;
  }

  void _remember(String id) {
    if (!_removedIds.add(id)) return;
    _removedOrder.add(id);
    if (_removedOrder.length > maxRemovedIdsTracked) {
      _removedIds.remove(_removedOrder.removeFirst());
    }
  }

  void _freeSlot(int slot) {
    final stroke = _strokes[slot];
    if (stroke == null) return;
    // A dying selection must not stay offered a resize or reorder action.
    if (selectedObjectId.value == stroke.id) selectedObjectId.value = null;
    if (elevatedObjectId.value == stroke.id) elevatedObjectId.value = null;
    scene.remove(slot);
    stroke.image?.dispose();
    _strokes[slot] = null;
    objectCount.value = objectCount.value - 1;
  }

  void _disposeImages() {
    for (final stroke in _strokes) {
      stroke?.image?.dispose();
    }
  }

  /// Re-culls against the current camera and repaints.
  ///
  /// Separate from [applyPlaced] so a snapshot of several hundred objects
  /// costs one cull and one repaint rather than one of each per object, the
  /// same reason [CanvasScene.add] does not notify.
  void refresh() => _reculled();

  /// Moves the camera, clamped so the view stays inside the bounded world and
  /// the zoom inside the range a viewport read is sized for.
  void setCamera(Camera next) {
    _camera = _clamp(next);
    _reculled();
  }

  void setViewport(Size size) {
    if (size == _viewport) return;
    _viewport = size;
    _camera = _clamp(_camera);
    _reculled();
  }

  /// The world rectangle currently on screen.
  Rect get worldView => Rect.fromLTWH(
        _camera.x,
        _camera.y,
        _viewport.width / _camera.zoom,
        _viewport.height / _camera.zoom,
      );

  Camera _clamp(Camera next) {
    final zoom = next.zoom.clamp(minZoom, maxZoom);
    final w = _viewport.width / zoom;
    final h = _viewport.height / zoom;
    final maxX = math.max(-worldLimit, worldLimit - w);
    final maxY = math.max(-worldLimit, worldLimit - h);
    return Camera(
      x: next.x.clamp(-worldLimit, maxX),
      y: next.y.clamp(-worldLimit, maxY),
      zoom: zoom,
    );
  }

  void _reculled() {
    final view = worldView;
    scene.setViewport(view.left, view.top, view.right, view.bottom);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposeImages();
    objectCount.dispose();
    selectedObjectId.dispose();
    elevatedObjectId.dispose();
    scene.dispose();
    super.dispose();
  }
}
