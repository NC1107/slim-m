// SPDX-License-Identifier: Apache-2.0
/// Mints canvas mutation ops - remove, clear, restore, move - and the undo
/// ledger that reverses them.
///
/// Plain Dart, like `CanvasSync`: nothing here is observed inside a frame,
/// so it stays off Riverpod, and it never reaches back into the widget tree
/// except through [onError].
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_voice_canvas/voice_canvas.dart';

import '../../ids.dart';
import 'canvas_commit_queue.dart';

/// How many gestures [CanvasOpsController] can reverse. About the product,
/// not the memory: a deeper stack that dies on pane close is a promise the
/// UI cannot keep.
@visibleForTesting
const int undoStackDepth = 32;

/// The event frame's own bound (`MAX_REMOVE_IDS_PER_OP` server-side), so a
/// single erase drag never collects more than one op can carry.
@visibleForTesting
const int maxRemoveIdsPerOp = 64;

sealed class _UndoEntry {}

class _DrawEntry extends _UndoEntry {
  _DrawEntry(this.objectIds);

  final List<String> objectIds;
}

class _EraseEntry extends _UndoEntry {
  _EraseEntry(this.opId);

  final String opId;
}

class _MoveEntry extends _UndoEntry {
  _MoveEntry(this.objectId, this.fromX, this.fromY, this.fromW, this.fromH);

  final String objectId;
  final double fromX;
  final double fromY;
  final double fromW;
  final double fromH;
}

/// One select-drag in progress: the object picked up, its bounds when the
/// drag began (for [CanvasOpsController.undo] to restore), and the bounds it
/// currently occupies (updated on every [CanvasOpsController.dragMove]).
class _DragState {
  _DragState(
    this.objectId,
    this.fromX,
    this.fromY,
    this.fromW,
    this.fromH,
    this.anchor,
  ) : x = fromX,
      y = fromY;

  final String objectId;
  final double fromX;
  final double fromY;
  final double fromW;
  final double fromH;

  /// The world point the drag started at, so every later point becomes a
  /// delta from the object's own original position rather than its own.
  final Offset anchor;

  double x;
  double y;
}

/// Reconciles the undo stack, the erase tool, and the clear control against
/// [document] and the server's op stream.
class CanvasOpsController {
  CanvasOpsController({
    required this.channelId,
    required this.client,
    required this.document,
    required this.commits,
    required this.onError,
  });

  final String channelId;
  final api.SlimmApi client;
  final CanvasDocument document;
  final CanvasCommitQueue commits;

  /// A sentence to show once an op this controller submitted fails.
  final void Function(String message) onError;

  final Queue<_UndoEntry> _undoStack = Queue<_UndoEntry>();
  final Set<String> _dragBatch = <String>{};
  _DragState? _drag;

  bool get canUndo => _undoStack.isNotEmpty;

  /// Records a just-drawn gesture's object ids so [undo] can reverse it as
  /// one unit, matching what one continuous stroke split into.
  void recordDraw(List<String> objectIds) {
    if (objectIds.isEmpty) return;
    _pushUndo(_DrawEntry(objectIds));
  }

  /// An id [CanvasCommitQueue.undoPlacement] armed while in flight has now
  /// landed; wired as the queue's `onEraseOnConfirm` callback.
  Future<void> eraseOnConfirm(String id) => _submitRemove([id]);

  /// Reverses the most recent drawn or erased gesture, or does nothing if
  /// there is none.
  Future<void> undo() async {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    switch (entry) {
      case _DrawEntry(:final objectIds):
        await _undoDraw(objectIds);
      case _EraseEntry(:final opId):
        await _restore(opId);
      case _MoveEntry(
        :final objectId,
        :final fromX,
        :final fromY,
        :final fromW,
        :final fromH,
      ):
        await _undoMove(objectId, fromX, fromY, fromW, fromH);
    }
  }

  /// Cancels or arms anything of [objectIds] still in the placement queue,
  /// and removes the rest - already committed, since a killed (never-landed)
  /// id needs nothing further - with one ordinary op.
  Future<void> _undoDraw(List<String> objectIds) async {
    final immediate = <String>[];
    for (final id in objectIds) {
      switch (commits.undoPlacement(id)) {
        case UndoPlacementOutcome.cancelled:
          document.kill(id);
        case UndoPlacementOutcome.armed:
          document.removeObject(id);
        case UndoPlacementOutcome.unresolved:
          if (document.isAlive(id)) {
            document.removeObject(id);
            immediate.add(id);
          }
      }
    }
    document.refresh();
    if (immediate.isNotEmpty) await _submitRemove(immediate);
  }

  /// Erases the topmost stroke under [world] the caller is allowed to
  /// erase - their own ink always, or anybody's with [manageCanvas] - and
  /// removes it from view at once. Scoped at hit-test time so a drag
  /// visibly picks up nothing it cannot touch, rather than sending a
  /// request the server would refuse anyway. Fires on pointer-down and every
  /// move; [endErase] is what submits the whole drag as one op.
  void onErasePoint(
    Offset world, {
    required bool manageCanvas,
    required String? selfId,
  }) {
    if (_dragBatch.length >= maxRemoveIdsPerOp) return;
    final id = hitTestStroke(
      document,
      world,
      allowed: (stroke) =>
          manageCanvas ||
          (stroke.authorId != null && stroke.authorId == selfId),
    );
    if (id == null || !_dragBatch.add(id)) return;
    document.removeObject(id);
    document.refresh();
  }

  /// Submits whatever the drag collected as one op, so undoing an erase
  /// drag is atomic. Every id here was alive at hit-test time and has
  /// already been removed from view; this only decides whether that also
  /// needs cancelling from the placement queue - a self-drawn id not yet
  /// confirmed - or an ordinary op, which is everything else.
  Future<void> endErase() async {
    if (_dragBatch.isEmpty) return;
    final ids = _dragBatch.toList(growable: false);
    _dragBatch.clear();
    final immediate = <String>[
      for (final id in ids)
        if (commits.undoPlacement(id) == UndoPlacementOutcome.unresolved) id,
    ];
    if (immediate.isEmpty) return;
    final opId = await _submitRemove(immediate);
    if (opId != null) _pushUndo(_EraseEntry(opId));
  }

  /// Picks up the topmost live image under [world] the caller may move -
  /// their own, or anybody's with [manageCanvas] - and remembers its
  /// original bounds so [dragMove] can preview the move locally and
  /// [undo] can reverse it. A no-op, silently, if nothing movable is there:
  /// the same "scope at hit-test time" choice [onErasePoint] already makes.
  void beginMove(
    Offset world, {
    required bool manageCanvas,
    required String? selfId,
  }) {
    final id = hitTestImageAt(
      document,
      world,
      allowed: (stroke) =>
          manageCanvas ||
          (stroke.authorId != null && stroke.authorId == selfId),
    );
    if (id == null) return;
    final bounds = document.objectBounds(id);
    if (bounds == null) return;
    _drag = _DragState(id, bounds.x, bounds.y, bounds.w, bounds.h, world);
  }

  /// Moves whatever [beginMove] picked up so its drag delta from [world]
  /// matches the object's own displacement, and previews the new position
  /// locally. Does nothing if nothing is being dragged.
  void dragMove(Offset world) {
    final drag = _drag;
    if (drag == null) return;
    drag.x = drag.fromX + (world.dx - drag.anchor.dx);
    drag.y = drag.fromY + (world.dy - drag.anchor.dy);
    document.moveObject(drag.objectId, drag.x, drag.y, drag.fromW, drag.fromH);
    document.refresh();
  }

  /// Commits the drag's final position as one `move` op, or does nothing if
  /// nothing was being dragged or the object never actually moved - picking
  /// an object up and putting it back down costs no request and pushes no
  /// undo entry. The position is already showing locally, from [dragMove]'s
  /// own optimistic updates during the drag; a failure here is what puts it
  /// back, the same "revert what was already shown" shape a failed placement
  /// or restore already uses elsewhere in this file.
  Future<void> endMove() async {
    final drag = _drag;
    _drag = null;
    if (drag == null) return;
    if (drag.x == drag.fromX && drag.y == drag.fromY) return;
    try {
      await client.submitCanvasOp(
        channelId,
        id: newCanvasOpId(),
        kind: 'move',
        objectId: drag.objectId,
        x: drag.x,
        y: drag.y,
        w: drag.fromW,
        h: drag.fromH,
      );
      _pushUndo(
        _MoveEntry(
          drag.objectId,
          drag.fromX,
          drag.fromY,
          drag.fromW,
          drag.fromH,
        ),
      );
    } on api.ApiException {
      document.moveObject(
        drag.objectId,
        drag.fromX,
        drag.fromY,
        drag.fromW,
        drag.fromH,
      );
      document.refresh();
      onError('That could not be moved.');
    }
  }

  /// Reverses a move by submitting the inverse one - there is no dedicated
  /// undo-a-move op, since a move already carries its own destination and
  /// undoing it is just another move, back. Applied locally first, the same
  /// immediate feedback [undo] already gives a reversed draw or erase, with
  /// the object's pre-undo bounds kept so a failure can put it back.
  Future<void> _undoMove(
    String objectId,
    double x,
    double y,
    double w,
    double h,
  ) async {
    final before = document.objectBounds(objectId);
    document.moveObject(objectId, x, y, w, h);
    document.refresh();
    try {
      await client.submitCanvasOp(
        channelId,
        id: newCanvasOpId(),
        kind: 'move',
        objectId: objectId,
        x: x,
        y: y,
        w: w,
        h: h,
      );
    } on api.ApiException {
      if (before != null) {
        document.moveObject(objectId, before.x, before.y, before.w, before.h);
        document.refresh();
      }
      onError('That could not be undone.');
    }
  }

  /// Clears every object placed at or before [beforeSeq] - see
  /// `CanvasSync.asOfSeq` for why that is the right fencing token - and
  /// records the resulting op so [undo] can restore it. Returns whether the
  /// request itself succeeded, so the caller can decide what to show; a
  /// clear that touched nothing still succeeds and pushes no undo entry.
  Future<bool> clear(int beforeSeq) async {
    try {
      final result = await client.submitCanvasOp(
        channelId,
        id: newCanvasOpId(),
        kind: 'clear',
        beforeSeq: beforeSeq,
      );
      if (result.op.affected > 0) {
        document.clearBelow(beforeSeq);
        document.refresh();
        _pushUndo(_EraseEntry(result.op.id));
      }
      return true;
    } on api.ApiException {
      onError('The canvas could not be cleared.');
      return false;
    }
  }

  Future<String?> _submitRemove(List<String> ids) async {
    try {
      final result = await client.submitCanvasOp(
        channelId,
        id: newCanvasOpId(),
        kind: 'remove',
        objectIds: ids,
      );
      return result.op.id;
    } on api.ApiException {
      onError('That stroke could not be erased.');
      return null;
    }
  }

  /// Undoes an erase or a clear. The local resurrect is not attempted - the
  /// removed stroke's payload was freed on removal - so a live
  /// `CanvasObjectsRestored` frame or the next catch-up is what brings the
  /// object back.
  Future<void> _restore(String opId) async {
    try {
      await client.submitCanvasOp(
        channelId,
        id: newCanvasOpId(),
        kind: 'restore',
        targetOp: opId,
      );
    } on api.ApiException {
      onError('That could not be undone.');
    }
  }

  void _pushUndo(_UndoEntry entry) {
    _undoStack.addLast(entry);
    while (_undoStack.length > undoStackDepth) {
      _undoStack.removeFirst();
    }
  }
}
