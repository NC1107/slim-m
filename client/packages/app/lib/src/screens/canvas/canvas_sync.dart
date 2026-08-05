// SPDX-License-Identifier: Apache-2.0
/// Reconciles a channel's canvas op stream against the local document.
///
/// The canvas has no durable local state - `CanvasDocument` lives in the
/// mounted pane and dies with it - so "the pane was closed" and "the client
/// was offline" are the same state, and the recovery for both is already a
/// cold viewport read. What this closes is the narrower case: the pane
/// stayed open across a drop, or a live frame arrived out of order, or the
/// server started emitting an op kind this client has never heard of.
///
/// Deliberately plain Dart, holding no `Ref` and no `BuildContext`: staying
/// off Riverpod is what lets a live frame apply inside the frame that
/// produced it, the same reason `CanvasDocument` is a bare `ChangeNotifier`
/// rather than a provider. `CanvasPane` owns the socket subscription and the
/// `syncControllerProvider` listener and calls into this class; this class
/// never reaches back into the widget tree except through the two callbacks
/// it is handed.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_voice_canvas/voice_canvas.dart';

/// Past this many pages, replaying the feed costs no less than a cold
/// viewport re-read, and the re-read is strictly better: it also drops
/// everything outside the caller's own region.
@visibleForTesting
const int maxCatchUpPages = 25;

/// A hard reset costs one viewport read; without a floor, a server emitting
/// an op kind this client cannot parse turns every stale client into a
/// refetch loop.
@visibleForTesting
const Duration hardResetFloor = Duration(seconds: 5);

/// Converts a wire object into what the document needs to paint a stroke or
/// an image, or null for a kind this client does not draw. Shared between a
/// viewport page, a live placement, and a `place` op read off the catch-up
/// feed, so the three paths cannot silently disagree on what counts as
/// paintable.
CanvasStrokeInput? canvasStrokeInputFrom(api.CanvasObject object) {
  return switch (object.kind) {
    'stroke' => _strokeInputFrom(object),
    'image' => _imageInputFrom(object),
    _ => null,
  };
}

CanvasStrokeInput? _strokeInputFrom(api.CanvasObject object) {
  final raw = object.props['points'];
  if (raw is! List) return null;
  return CanvasStrokeInput(
    id: object.id,
    seq: object.seq,
    zIndex: object.zIndex,
    x: object.x,
    y: object.y,
    w: object.w,
    h: object.h,
    points: raw.whereType<num>().map((n) => n.toDouble()).toList(),
    width: (object.props['width'] as num?)?.toDouble() ?? 3,
    colorKey: object.props['color'] as String? ?? 'annotation',
    authorId: object.authorId,
  );
}

/// `props.attachment` is the one field this client actually reads; the rest
/// of an image's props (`content_type`, the natural pixel size) are only
/// ever written, not read back, since the box on the wire already says how
/// large to paint it.
CanvasStrokeInput? _imageInputFrom(api.CanvasObject object) {
  final attachment = object.props['attachment'];
  if (attachment is! String) return null;
  return CanvasStrokeInput(
    id: object.id,
    seq: object.seq,
    zIndex: object.zIndex,
    x: object.x,
    y: object.y,
    w: object.w,
    h: object.h,
    points: const [],
    width: 0,
    colorKey: '',
    authorId: object.authorId,
    kind: CanvasObjectKind.image,
    attachmentId: attachment,
  );
}

/// Reconciles [document] against one channel's canvas op stream.
class CanvasSync {
  CanvasSync({
    required this.channelId,
    required this.client,
    required this.document,
    required this.coldFetch,
    required this.forgetFetchedRegion,
    this.onObjectPlaced,
  });

  final String channelId;
  final api.SlimmApi client;
  final CanvasDocument document;

  /// Fires for every object a catch-up `place` op actually applies, so the
  /// pane's image hydrator sees an arrival off this path exactly as it does
  /// a viewport page or a live frame. Optional and defaulted to nothing
  /// rather than required, since most of this class's own tests have no
  /// opinion about hydration at all.
  final void Function(api.CanvasObject object)? onObjectPlaced;

  /// The pane's own cold viewport fetch, reused rather than duplicated here:
  /// it alone knows the padded region and owns the pane's fetched-region
  /// cache. Called by a hard reset, and by nothing else.
  final Future<void> Function() coldFetch;

  /// Drops the pane's fetched-region cache, so the next camera move
  /// refetches rather than trusting a region that no longer means what it
  /// did. Called by a restore (a local resurrect is not attempted; only a
  /// fetch can bring the object's payload back) and by a hard reset.
  final VoidCallback forgetFetchedRegion;

  int? _asOfSeq;
  DateTime? _lastReset;
  bool _catchingUp = false;
  bool _disposed = false;

  /// The highest op this document reflects, or null before the first
  /// viewport read has landed.
  ///
  /// Also the clear control's fencing token: sending this back as
  /// `before_seq` says "clear everything already reflected in what I've
  /// seen," so a lost response retried cannot wipe ink drawn in the
  /// interval it was in flight.
  int? get asOfSeq => _asOfSeq;

  void dispose() => _disposed = true;

  /// Seeds the cursor from a viewport read's own `latestSeq`, but only the
  /// first time.
  ///
  /// A region refetch while the pane stays open must never move this
  /// forward: an erase at seq 50 in region one, then a pan to region two
  /// whose own read answers at seq 60, would otherwise leave the cursor past
  /// the very op that says region one's object is gone, with nothing left to
  /// ever apply it.
  void seedFromViewport(int latestSeq) => _asOfSeq ??= latestSeq;

  /// A live frame named [seq] arrived; [apply] materializes its own payload.
  ///
  /// Ignored if already reflected. Applied and the cursor advanced if it is
  /// exactly the next op - sound only because the op stream is dense, so
  /// `seq == cursor + 1` is a real adjacency test rather than a heuristic.
  /// Anything further ahead is a gap, closed by a catch-up rather than
  /// trusted alone: the frame's own payload is not applied in that case,
  /// since the catch-up page that follows carries the same op in order.
  void applyLive(int seq, void Function() apply) {
    final cursor = _asOfSeq;
    if (cursor != null && seq <= cursor) return;
    if (cursor == null || seq == cursor + 1) {
      apply();
      _asOfSeq = seq;
      return;
    }
    unawaited(catchUp());
  }

  /// Reconciles an op the live frame could not carry, without advancing the
  /// cursor past it.
  ///
  /// The one caller is a restore whose frame arrived with no ids, which the
  /// server does when the restored set is larger than a `remove` may name.
  /// Deliberately not [applyLive] with an empty apply: that would move the
  /// cursor past the only op able to clear those tombstones, and no later
  /// frame or cold fetch would ever bring the objects back, since the
  /// document refuses to re-place a tombstoned id. Leaving the cursor where
  /// it is means the feed re-delivers the op with its full list, and any
  /// frame arriving meanwhile reads as a gap and lands here too.
  void deferToFeed() => unawaited(catchUp());

  /// Pages the ops feed from the current cursor, applying every op in order.
  ///
  /// Runs on the first successful viewport read, on every later fetch (cold
  /// or region), on a live-frame gap, and on a reconnect - see the call
  /// sites in `CanvasPane`. Reentrant calls while one is already running are
  /// dropped: nothing is lost, since whatever the second call would have
  /// found either lands via the first call's own page or arrives as its own
  /// later live frame.
  Future<void> catchUp() async {
    if (_disposed || _catchingUp) return;
    _catchingUp = true;
    try {
      for (var page = 0; page < maxCatchUpPages; page++) {
        final result = await _fetchPage(_asOfSeq ?? 0);
        if (_disposed) return;
        if (result == null) return;
        if (result.reset) {
          await _hardReset();
          return;
        }
        for (final op in result.ops) {
          if (!_applyOp(op)) {
            await _hardReset();
            return;
          }
        }
        if (!result.hasMore) {
          final cursor = _asOfSeq;
          _asOfSeq = cursor == null || result.latestSeq > cursor
              ? result.latestSeq
              : cursor;
          document.refresh();
          return;
        }
      }
      await _hardReset();
    } finally {
      _catchingUp = false;
    }
  }

  /// Fetches one page, retrying a rate limit with backoff rather than
  /// surfacing it as a reset: a client catching up during a burst must not
  /// have a 429 turned into a document wipe. Null means every retry was
  /// spent, or some other failure occurred; either way the caller abandons
  /// this attempt rather than resetting, since a future gap or reconnect
  /// tries again.
  Future<api.CanvasOpsPage?> _fetchPage(int afterSeq) async {
    var delay = const Duration(milliseconds: 250);
    for (var attempt = 0; attempt < 3; attempt++) {
      if (_disposed) return null;
      try {
        return await client.canvasOps(channelId, afterSeq: afterSeq);
      } on api.RateLimitedException {
        if (attempt == 2) return null;
        await Future<void>.delayed(delay);
        delay *= 2;
      } on api.ApiException {
        return null;
      }
    }
    return null;
  }

  /// Applies one op read off the catch-up feed. Returns false for a kind
  /// this client does not recognise, so the caller resets rather than
  /// skips it - skipping could mean leaving ink on screen the server has
  /// removed, which is the one failure this whole surface exists to avoid.
  bool _applyOp(api.CanvasOp op) {
    switch (op) {
      case api.CanvasPlaceOp(:final object):
        if (object != null) {
          final input = canvasStrokeInputFrom(object);
          if (input != null) {
            document.applyPlaced(input);
            onObjectPlaced?.call(object);
          }
        }
      case api.CanvasRemoveOp(:final objectIds):
        for (final id in objectIds) {
          document.removeObject(id);
        }
      case api.CanvasClearOp(:final beforeSeq):
        document.clearBelow(beforeSeq);
      case api.CanvasRestoreOp(:final objectIds):
        document.forgetRemoved(objectIds);
        forgetFetchedRegion();
      case api.CanvasMoveOp(
        :final objectId,
        :final x,
        :final y,
        :final w,
        :final h,
      ):
        document.moveObject(objectId, x, y, w, h);
      case api.CanvasReorderOp(:final objectId, :final zIndex):
        document.setZIndex(objectId, zIndex);
      case api.CanvasUnknownOp():
        return false;
    }
    return true;
  }

  /// Empties the document, drops the cursor, and cold-fetches - rate-limited
  /// so a server emitting an unknown kind in a stream cannot turn every
  /// stale client into a refetch loop.
  Future<void> _hardReset() async {
    final now = clock.now();
    final last = _lastReset;
    if (last != null && now.difference(last) < hardResetFloor) return;
    _lastReset = now;
    document.reset();
    forgetFetchedRegion();
    _asOfSeq = null;
    if (_disposed) return;
    await coldFetch();
  }
}
