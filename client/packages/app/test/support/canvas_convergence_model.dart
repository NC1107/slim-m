// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A hand-rolled canonical op-log generator and an independent oracle, built
/// for `canvas_convergence_property_test.dart` rather than for production.
///
/// The generator produces a dense `seq` 1..N sequence over `place`, `move`,
/// `remove`, `clear` and `restore`, in the same shape `canvas_ops` itself
/// would hold: only a real state transition gets a `seq` (a `clear` that
/// touches nothing, or a `restore` whose targets are already all alive, is
/// skipped rather than recorded), matching `submit_canvas_op`'s own
/// "an op row exists only for a real state transition" rule.
///
/// [CanvasLogOracle] replays that log with no dependency on `CanvasDocument`
/// or `CanvasSync` at all, so a bug shared by the generator and the
/// production apply logic could not make both agree by accident.
///
/// One deliberate simplification: once an object has been named by a
/// `restore`, this generator never targets it again with `move` or
/// `remove`. A real deployment does allow that (the server's own row is
/// live again after a restore), but the *client* only ever re-learns of it
/// through a fresh fetch this test harness does not model - see
/// `canvas_sync.dart`'s own doc comment on why a restore never
/// re-materializes a stroke locally. Testing "move a restored-but-unfetched
/// object" would be testing a fetch this generator does not send, not a
/// convergence property.
library;

import 'dart:math' as math;

sealed class CanonOp {
  const CanonOp(this.seq);
  final int seq;
}

class CanonPlace extends CanonOp {
  CanonPlace(super.seq, this.id, this.x, this.y, this.w, this.h) : zIndex = seq;

  final String id;
  final double x;
  final double y;
  final double w;
  final double h;
  final int zIndex;
}

class CanonMove extends CanonOp {
  const CanonMove(
    super.seq,
    this.opId,
    this.objectId,
    this.x,
    this.y,
    this.w,
    this.h,
  );

  final String opId;
  final String objectId;
  final double x;
  final double y;
  final double w;
  final double h;
}

class CanonRemove extends CanonOp {
  const CanonRemove(super.seq, this.opId, this.objectIds);

  final String opId;
  final List<String> objectIds;
}

class CanonClear extends CanonOp {
  const CanonClear(super.seq, this.opId, this.beforeSeq, this.killedIds);

  final String opId;
  final int beforeSeq;
  final List<String> killedIds;
}

class CanonRestore extends CanonOp {
  const CanonRestore(super.seq, this.opId, this.targetOpId, this.objectIds);

  final String opId;
  final String targetOpId;
  final List<String> objectIds;
}

/// A position and size in world units, named rather than positional so a
/// call site reads `entry.value.x` instead of `entry.value.$1`.
typedef CanvasBounds = ({double x, double y, double w, double h});

class _RemovalRecord {
  _RemovalRecord(this.opId, Set<String> targets) : stillDead = targets;

  final String opId;
  final Set<String> stillDead;
}

/// Generates one random, internally-consistent canonical op log, seeded so a
/// failure names a reproducible seed rather than a one-off flake.
class CanvasLogGenerator {
  CanvasLogGenerator(int seed) : _rng = math.Random(seed);

  final math.Random _rng;
  int _seq = 0;
  int _objectCounter = 0;
  int _opCounter = 0;

  final List<String> _alive = [];
  final Map<String, int> _placedSeq = {};
  final Map<String, CanvasBounds> _bounds = {};
  final List<_RemovalRecord> _removals = [];

  /// Produces up to [count] ops (fewer only if the log runs out of legal
  /// moves, which does not happen in practice since `place` is always
  /// legal).
  List<CanonOp> generate(int count) {
    final ops = <CanonOp>[];
    var guard = 0;
    while (ops.length < count && guard < count * 6) {
      guard++;
      final op = _step();
      if (op != null) ops.add(op);
    }
    return ops;
  }

  CanonOp? _step() {
    if (_alive.isEmpty) return _place();
    final roll = _rng.nextInt(10);
    if (roll < 4) return _place();
    if (roll < 6) return _move();
    if (roll < 8) return _remove();
    if (roll == 8) return _clear();
    return _restore() ?? _place();
  }

  CanonOp _place() {
    final id = 'o${_objectCounter++}';
    _seq++;
    final x = _rng.nextDouble() * 2000 - 1000;
    final y = _rng.nextDouble() * 2000 - 1000;
    final w = 5.0 + _rng.nextDouble() * 40;
    final h = 5.0 + _rng.nextDouble() * 40;
    _alive.add(id);
    _placedSeq[id] = _seq;
    _bounds[id] = (x: x, y: y, w: w, h: h);
    return CanonPlace(_seq, id, x, y, w, h);
  }

  CanonOp _move() {
    final id = _alive[_rng.nextInt(_alive.length)];
    _seq++;
    final was = _bounds[id]!;
    final next = (
      x: was.x + (_rng.nextDouble() * 200 - 100),
      y: was.y + (_rng.nextDouble() * 200 - 100),
      w: was.w,
      h: was.h,
    );
    _bounds[id] = next;
    return CanonMove(
      _seq,
      'mv${_opCounter++}',
      id,
      next.x,
      next.y,
      next.w,
      next.h,
    );
  }

  CanonOp _remove() {
    final count = 1 + _rng.nextInt(math.min(2, _alive.length));
    final targets = <String>{};
    while (targets.length < count) {
      targets.add(_alive[_rng.nextInt(_alive.length)]);
    }
    for (final id in targets) {
      _alive.remove(id);
    }
    _seq++;
    final opId = 'rm${_opCounter++}';
    _removals.add(_RemovalRecord(opId, targets));
    return CanonRemove(_seq, opId, targets.toList());
  }

  CanonOp? _clear() {
    final seqs = _placedSeq.values.toList()..sort();
    final beforeSeq = seqs[_rng.nextInt(seqs.length)];
    final killed = _alive
        .where((id) => _placedSeq[id]! <= beforeSeq)
        .toList(growable: false);
    if (killed.isEmpty) return null;
    for (final id in killed) {
      _alive.remove(id);
    }
    _seq++;
    final opId = 'cl${_opCounter++}';
    _removals.add(_RemovalRecord(opId, killed.toSet()));
    return CanonClear(_seq, opId, beforeSeq, killed);
  }

  /// Restores everything one still-dead removal touched, in one op - the
  /// same all-or-nothing shape `apply_restore` takes server-side. Retires
  /// every id it names: see the file's own doc comment on why.
  CanonOp? _restore() {
    final eligible = _removals.where((r) => r.stillDead.isNotEmpty).toList();
    if (eligible.isEmpty) return null;
    final record = eligible[_rng.nextInt(eligible.length)];
    final ids = record.stillDead.toList(growable: false);
    record.stillDead.clear();
    _seq++;
    return CanonRestore(_seq, 're${_opCounter++}', record.opId, ids);
  }
}

/// The reference outcome of replaying a canonical log, computed with no
/// reference to `CanvasDocument` or `CanvasSync`.
class CanvasLogOracle {
  final Map<String, CanvasBounds> alive = {};
  final Set<String> tombstoned = {};
  final Map<String, int> placementSeq = {};

  /// Replays [ops] in order (the log is already dense and ordered, the same
  /// guarantee a real channel's `canvas_ops` carries).
  CanvasLogOracle.replay(List<CanonOp> ops) {
    for (final op in ops) {
      switch (op) {
        case CanonPlace(:final id, :final x, :final y, :final w, :final h):
          alive[id] = (x: x, y: y, w: w, h: h);
          placementSeq[id] = op.seq;
        case CanonMove(:final objectId, :final x, :final y, :final w, :final h):
          if (alive.containsKey(objectId)) {
            alive[objectId] = (x: x, y: y, w: w, h: h);
          }
        case CanonRemove(:final objectIds):
          for (final id in objectIds) {
            alive.remove(id);
            tombstoned.add(id);
          }
        case CanonClear(:final killedIds):
          for (final id in killedIds) {
            alive.remove(id);
            tombstoned.add(id);
          }
        case CanonRestore(:final objectIds):
          // Not re-added to `alive`: a restore lifts the tombstone only.
          for (final id in objectIds) {
            tombstoned.remove(id);
          }
      }
    }
  }
}
