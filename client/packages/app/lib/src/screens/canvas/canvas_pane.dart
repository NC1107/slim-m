// SPDX-License-Identifier: Apache-2.0
/// The Voice Canvas, as a mode of a channel rather than a route.
///
/// Riverpod fetches, subscribes and mounts; nothing it does is observed inside
/// a frame. The live subscription is a plain `.listen` on the sync
/// controller's broadcast stream, never a `StreamProvider` a widget watches -
/// two shapes of that hang a widget test with a symptom indistinguishable from
/// a slow CI job, and both are already recorded in the project's knowledge
/// base.
///
/// Every refetch is a cold fetch of the padded viewport, and the `previous`
/// rectangle the endpoint offers is deliberately never sent. It is a single
/// rectangle, so a client tracking several fetched regions can only pass their
/// bounding box, which claims coverage of space it never fetched: everything
/// old in the gap is held back from that read and from every later one, and
/// nothing backfills it. Re-delivery costs a duplicate, which id dedupe makes
/// free, and that is the cheaper mistake by a distance.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_voice_canvas/voice_canvas.dart';

import '../../ids.dart';
import '../../permissions.dart';
import '../../providers/providers.dart';
import '../../providers/live_events.dart';
import '../../providers/sync_controller.dart';
import 'canvas_commit_queue.dart';
import 'canvas_ops_controller.dart';
import 'canvas_pane_body.dart';
import 'canvas_sync.dart';

/// The channel whose canvas is open, or null.
///
/// A provider rather than a route: joining a call opens voice and the canvas
/// as one screen (STRATEGY), and a separate navigation step is the alternative
/// that was rejected. The cost is stated rather than discovered: no URL, no
/// deep link, and no browser back to close it.
final canvasOpenProvider = StateProvider<String?>((ref) => null);

class CanvasPane extends ConsumerStatefulWidget {
  const CanvasPane({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<CanvasPane> createState() => _CanvasPaneState();
}

class _CanvasPaneState extends ConsumerState<CanvasPane> {
  final CanvasDocument _document = CanvasDocument();
  StreamSubscription<api.ServerEvent>? _live;
  CanvasCommitQueue? _queue;
  CanvasOpsController? _opsController;
  Timer? _panDebounce;
  late final CanvasSync _sync;
  ProviderSubscription<SyncStatus>? _syncStatusSubscription;

  Rect? _fetched;

  /// The view [_onCameraMoved] last examined, regardless of what it decided
  /// to do about it. See that method's doc for why this exists.
  Rect? _lastCameraView;
  bool _loading = true;
  String? _error;
  bool _truncated = false;
  int _localZ = provisionalLocalZIndex;
  CanvasTool _tool = CanvasTool.pen;

  @override
  void initState() {
    super.initState();
    _live = ref.read(liveEventsProvider).listen(_onEvent);
    _sync = CanvasSync(
      channelId: widget.channelId,
      client: ref.read(apiProvider),
      document: _document,
      coldFetch: _fetch,
      forgetFetchedRegion: () => _fetched = null,
    );
    // Registered once here, not in build: a listener re-attached per rebuild would fire a catch-up per rebuild, not per transition into live.
    _syncStatusSubscription = ref.listenManual<SyncStatus>(
      syncControllerProvider,
      (previous, next) {
        if (next == SyncStatus.live) unawaited(_sync.catchUp());
      },
    );
    // No fetch here: CanvasSurface's first setViewport call reaches _onCameraMoved below and fetches the real region, not a wasted one against a zero viewport.
    _document.addListener(_onCameraMoved);
  }

  @override
  void dispose() {
    _panDebounce?.cancel();
    _queue?.close();
    unawaited(_live?.cancel());
    _syncStatusSubscription?.close();
    _sync.dispose();
    _document.removeListener(_onCameraMoved);
    _document.dispose();
    super.dispose();
  }

  CanvasCommitQueue get _commits => _queue ??= CanvasCommitQueue(
    client: ref.read(apiProvider),
    channelId: widget.channelId,
    onPlaced: _apply,
    onFailed: (id, message) {
      _document
        ..kill(id)
        ..refresh();
      if (mounted) setState(() => _error = message);
    },
    onRemoved: (id) {
      _document
        ..removeObject(id)
        ..refresh();
      if (mounted) {
        setState(
          () => _error = 'That stroke was erased while it was being saved.',
        );
      }
    },
    onEraseOnConfirm: (id) => unawaited(_ops.eraseOnConfirm(id)),
  );

  CanvasOpsController get _ops => _opsController ??= CanvasOpsController(
    channelId: widget.channelId,
    client: ref.read(apiProvider),
    document: _document,
    commits: _commits,
    onError: (message) {
      if (mounted) setState(() => _error = message);
    },
  );

  void _onEvent(api.ServerEvent event) {
    switch (event) {
      case api.CanvasObjectPlaced(:final channelId, :final object)
          when channelId == widget.channelId:
        _sync.applyLive(event.seq, () => _apply(object));
      case api.CanvasObjectsRemoved(
            :final channelId,
            :final seq,
            :final objectIds,
          )
          when channelId == widget.channelId:
        _sync.applyLive(seq, () {
          for (final id in objectIds) {
            _document.removeObject(id);
          }
          _document.refresh();
        });
      case api.CanvasCleared(:final channelId, :final seq, :final beforeSeq)
          when channelId == widget.channelId:
        _sync.applyLive(seq, () {
          _document.clearBelow(beforeSeq);
          _document.refresh();
        });
      case api.CanvasObjectsRestored(
            :final channelId,
            :final seq,
            :final objectIds,
          )
          when channelId == widget.channelId:
        _sync.applyLive(seq, () {
          _document.forgetRemoved(objectIds);
          _fetched = null;
        });
      default:
        break;
    }
  }

  void _apply(api.CanvasObject object) {
    final input = canvasStrokeInputFrom(object);
    if (input == null) return;
    _document
      ..applyPlaced(input)
      ..refresh();
  }

  /// A pan re-reads once the camera has settled, never per frame.
  ///
  /// [CanvasDocument]'s listenable fires on any content change too - a fetch
  /// landing, a live frame, a locally drawn stroke - since [CanvasDocument]'s
  /// `refresh()` and a real camera move both end in the same
  /// `notifyListeners()`. Reading [_lastCameraView] is what tells those
  /// apart: a content-only notification reports the same world view as last
  /// examined, so it returns before touching [_fetched] at all. Without that
  /// guard a still-truncated region never becomes "covered", so every one of
  /// those content notifications re-read a null [_fetched] and rescheduled a
  /// fetch for the unmoved viewport - forever, since the answer stays
  /// truncated for the same reason each time.
  void _onCameraMoved() {
    final view = _document.worldView;
    if (view == _lastCameraView) return;
    final isFirstView = _lastCameraView == null;
    _lastCameraView = view;
    final fetched = _fetched;
    if (fetched != null &&
        fetched.contains(view.topLeft) &&
        fetched.contains(view.bottomRight)) {
      return;
    }
    _panDebounce?.cancel();
    if (isFirstView) {
      unawaited(_fetch());
      return;
    }
    _panDebounce = Timer(
      const Duration(milliseconds: 150),
      () => unawaited(_fetch()),
    );
  }

  Rect _padded(Rect view) {
    final wide = view.inflate(view.width.clamp(1, 4000) / 2);
    return Rect.fromLTRB(
      wide.left.clamp(-worldLimit, worldLimit),
      wide.top.clamp(-worldLimit, worldLimit),
      wide.right.clamp(-worldLimit, worldLimit),
      wide.bottom.clamp(-worldLimit, worldLimit),
    );
  }

  Future<void> _fetch() async {
    final region = _padded(_document.worldView);
    if (region.width <= 0 || region.height <= 0) return;
    try {
      final page = await ref
          .read(apiProvider)
          .canvasViewport(
            widget.channelId,
            region: api.CanvasRect(
              minX: region.left,
              minY: region.top,
              maxX: region.right,
              maxY: region.bottom,
            ),
            limit: 2000,
          );
      if (!mounted) return;
      for (final object in page.objects) {
        final input = canvasStrokeInputFrom(object);
        if (input != null) _document.applyPlaced(input);
      }
      // Set before refresh(), not after: refresh() reaches _onCameraMoved synchronously and must see this fetch's own answer, not the value from before it ran.
      setState(() {
        _loading = false;
        _error = null;
        _truncated = page.hasMore;
        // A truncated page is not coverage: recording it would let the next pan skip what this read never returned.
        _fetched = page.hasMore ? null : region;
      });
      _document.refresh();
      _sync.seedFromViewport(page.latestSeq);
      await _sync.catchUp();
    } on api.ForbiddenException {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'The canvas is not available in this channel.';
        });
      }
    } on api.ApiException {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'The canvas could not be loaded.';
        });
      }
    }
  }

  void _onStroke(List<Offset> worldPoints) {
    final selfId = ref.read(meProvider).valueOrNull?.id;
    final ids = <String>[];
    for (final segment in splitStroke(worldPoints)) {
      final id = newCanvasObjectId();
      ids.add(id);
      _document.applyPlaced(
        CanvasStrokeInput(
          id: id,
          seq: 0,
          zIndex: _localZ++,
          x: segment.x,
          y: segment.y,
          w: segment.w,
          h: segment.h,
          points: segment.points,
          width: 3,
          colorKey: 'annotation',
          authorId: selfId,
        ),
      );
      _commits.add(
        CanvasCommit(
          id: id,
          x: segment.x,
          y: segment.y,
          w: segment.w,
          h: segment.h,
          props: {
            'points': segment.points,
            'width': 3.0,
            'color': 'annotation',
          },
        ),
      );
    }
    _document.refresh();
    // recordDraw is what makes undoing this whole gesture one op, not several.
    _ops.recordDraw(ids);
    if (mounted) setState(() {});
  }

  void _onErase(Offset world) {
    final me = ref.read(meProvider).valueOrNull;
    _ops.onErasePoint(
      world,
      manageCanvas: me?.permissions.hasPermission(Perm.manageCanvas) ?? false,
      selfId: me?.id,
    );
  }

  Future<void> _onEraseEnd() async {
    await _ops.endErase();
    if (mounted) setState(() {});
  }

  Future<void> _onUndo() async {
    await _ops.undo();
    if (mounted) setState(() {});
  }

  Future<void> _onClear() => _ops.clear(_sync.asOfSeq ?? 0);

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider).valueOrNull;
    final manageCanvas =
        me?.permissions.hasPermission(Perm.manageCanvas) ?? false;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            unawaited(_onUndo()),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
            unawaited(_onUndo()),
      },
      child: Focus(
        autofocus: true,
        child: CanvasPaneBody(
          channelId: widget.channelId,
          onClose: () => ref.read(canvasOpenProvider.notifier).state = null,
          tool: _tool,
          onToolChanged: (tool) => setState(() => _tool = tool),
          canUndo: _ops.canUndo,
          onUndo: () => unawaited(_onUndo()),
          canManage: manageCanvas,
          document: _document,
          onClear: _onClear,
          error: _error,
          onDismissError: () => setState(() => _error = null),
          truncated: _truncated,
          loading: _loading,
          onStroke: _onStroke,
          onErase: _onErase,
          onEraseEnd: () => unawaited(_onEraseEnd()),
        ),
      ),
    );
  }
}
