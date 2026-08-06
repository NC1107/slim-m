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
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import '../../ids.dart';
import '../../permissions.dart';
import '../../providers/blocks_controller.dart';
import '../../providers/providers.dart';
import '../../providers/live_events.dart';
import '../../providers/sync_controller.dart';
import '../../providers/user_profiles.dart';
import '../../providers/voice_controller.dart';
import 'canvas_activity_log.dart';
import 'canvas_commit_queue.dart';
import 'canvas_cursor_relay.dart';
import 'canvas_image_hydrator.dart';
import 'canvas_image_paste.dart';
import 'canvas_live_event_dispatch.dart';
import 'canvas_note_sheet.dart';
import 'canvas_ops_controller.dart';
import 'canvas_pane_body.dart';
import 'canvas_quick_placement.dart';
import 'canvas_stroke_preview_relay.dart';
import 'canvas_sync.dart';

part 'canvas_pane_gestures.dart';

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
  final CanvasCursors _cursors = CanvasCursors();
  final RemoteStrokeDrafts _remoteDrafts = RemoteStrokeDrafts();
  late final CanvasActivityLog _activityLog = CanvasActivityLog(
    isBlocked: (userId) => ref.read(blocksProvider).contains(userId),
  );
  StreamSubscription<api.ServerEvent>? _live;
  CanvasCommitQueue? _queue;
  CanvasOpsController? _opsController;
  CanvasCursorRelay? _cursorRelay;
  CanvasStrokePreviewRelay? _strokePreviewRelay;
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
  CanvasShapeKind _shapeKind = CanvasShapeKind.rectangle;
  CanvasImagePaste? _imagePasteHelper;
  CanvasQuickPlacement? _quickPlacementHelper;
  late final CanvasImageHydrator _hydrator = CanvasImageHydrator(
    client: ref.read(apiProvider),
    document: _document,
  );

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
      onObjectPlaced: _hydrator.hydrate,
      onOpApplied: _activityLog.recordOp,
      onHardReset: _activityLog.recordResync,
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
    // This pane is the only content mounted while it exists, so one listener for the whole mount is safe: nothing else here could hold it at the same time.
    _imagePaste.start();
  }

  @override
  void dispose() {
    _hydrator.dispose();
    _imagePasteHelper?.stop();
    _panDebounce?.cancel();
    _queue?.close();
    unawaited(_live?.cancel());
    _syncStatusSubscription?.close();
    _sync.dispose();
    _document.removeListener(_onCameraMoved);
    _document.dispose();
    _cursorRelay?.dispose();
    _cursors.dispose();
    _strokePreviewRelay?.dispose();
    _remoteDrafts.dispose();
    _activityLog.dispose();
    super.dispose();
  }

  CanvasImagePaste get _imagePaste => _imagePasteHelper ??= CanvasImagePaste(
    client: ref.read(apiProvider),
    channelId: widget.channelId,
    document: _document,
    onPlaced: () {
      // A just-pasted image is the one thing worth repositioning immediately.
      if (mounted) setState(() => _tool = CanvasTool.select);
    },
    onError: (message) {
      if (mounted) setState(() => _error = message);
    },
  );

  CanvasQuickPlacement get _quickPlacement =>
      _quickPlacementHelper ??= CanvasQuickPlacement(
        client: ref.read(apiProvider),
        channelId: widget.channelId,
        document: _document,
      );

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

  CanvasCursorRelay get _relay => _cursorRelay ??= CanvasCursorRelay(
    cursors: _cursors,
    paletteSize: AppCanvasColors.cursors.length,
    send: (x, y) => ref
        .read(syncControllerProvider.notifier)
        .notifyCanvasCursor(widget.channelId, x, y),
    resolveLabel: _cursorLabel,
    isBlocked: (userId) => ref.read(blocksProvider).contains(userId),
    selfId: () => ref.read(meProvider).valueOrNull?.id,
  );

  CanvasStrokePreviewRelay get _strokePreview =>
      _strokePreviewRelay ??= CanvasStrokePreviewRelay(
        drafts: _remoteDrafts,
        paletteSize: AppCanvasColors.cursors.length,
        send: (objectId, points, ended) => ref
            .read(syncControllerProvider.notifier)
            .notifyCanvasStrokePreview(
              widget.channelId,
              objectId,
              points,
              ended: ended,
            ),
        isBlocked: (userId) => ref.read(blocksProvider).contains(userId),
        selfId: () => ref.read(meProvider).valueOrNull?.id,
      );

  /// A remote cursor's label as of the last resolved answer, kicking off a
  /// fetch for an id this session has not asked about yet - the same
  /// resolve-then-fall-back order `authorLabel` uses for a message author,
  /// minus the local `authorDisplayName` cache a cursor has no row to carry.
  String _cursorLabel(String userId) {
    final profiles = ref.read(batchProfilesControllerProvider);
    resolveAuthorProfiles(ref, [userId]);
    if (profiles.containsKey(userId)) {
      return profiles[userId]?.displayName ?? 'Deleted user';
    }
    return 'Someone';
  }

  void _onEvent(api.ServerEvent event) => dispatchCanvasLiveEvent(
    event,
    paneChannelId: widget.channelId,
    sync: _sync,
    document: _document,
    relay: () => _relay,
    strokePreviewRelay: () => _strokePreview,
    applyPlacedObject: _apply,
    forgetFetchedRegion: () => _fetched = null,
    activityLog: _activityLog,
  );

  void _apply(api.CanvasObject object) {
    final input = canvasStrokeInputFrom(object);
    if (input == null) return;
    _document
      ..applyPlaced(input)
      ..refresh();
    _hydrator.hydrate(object);
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
        if (input != null) {
          _document.applyPlaced(input);
          _hydrator.hydrate(object);
        }
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

  /// The same bridge [_refresh] is, for a caller that needs the raw
  /// boolean rather than a guarded `setState` - `mounted` itself is
  /// unreachable from `_CanvasPaneGestures` for the same reason [_refresh]
  /// exists at all.
  bool get _mounted => mounted;

  /// `setState` and `mounted` are `@protected` on `State`, so an extension
  /// method - `_CanvasPaneGestures`'s own, in a different file even though
  /// the same library - cannot call either directly; this bridges that gap
  /// from a plain method the analyzer sees as a real member of this class.
  void _refresh([VoidCallback? mutate]) {
    if (mounted) setState(mutate ?? () {});
  }

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
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
            unawaited(_imagePaste.pasteFromKeystroke()),
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () =>
            unawaited(_imagePaste.pasteFromKeystroke()),
        const SingleActivator(LogicalKeyboardKey.delete): _onDeleteKey,
        const SingleActivator(LogicalKeyboardKey.backspace): _onDeleteKey,
      },
      child: Focus(
        autofocus: true,
        child: CanvasPaneBody(
          channelId: widget.channelId,
          onClose: () => ref.read(canvasOpenProvider.notifier).state = null,
          tool: _tool,
          onToolChanged: _onToolChanged,
          canUndo: _ops.canUndo,
          onUndo: () => unawaited(_onUndo()),
          canManage: manageCanvas,
          document: _document,
          onClear: _onClear,
          onPasteImage: () => unawaited(_imagePaste.pasteFromButton()),
          onRecenter: _onRecenter,
          error: _error,
          onDismissError: () => setState(() => _error = null),
          truncated: _truncated,
          loading: _loading,
          onStroke: _onStroke,
          onErase: _onErase,
          onEraseEnd: () => unawaited(_onEraseEnd()),
          onSelectStart: _onSelectStart,
          onSelectDrag: _onSelectDrag,
          onSelectEnd: () => unawaited(_onSelectEnd()),
          onNotePlace: (world) => unawaited(_onNotePlace(world)),
          onShapePlace: (world) => unawaited(_onShapePlace(world)),
          shapeKind: _shapeKind,
          onShapeKindChanged: (kind) => setState(() => _shapeKind = kind),
          onBringToFront: (id) => unawaited(_onBringToFront(id)),
          onSendToBack: (id) => unawaited(_onSendToBack(id)),
          onDeleteSelected: (id) => unawaited(_onDeleteSelected(id)),
          cursors: _cursors,
          cursorColors: AppCanvasColors.cursors,
          onPointerMoved: _onPointerMoved,
          remoteDrafts: _remoteDrafts,
          onDraftPoint: _strokePreview.reportLocalDraftPoint,
          onDraftEnded: _strokePreview.endLocalDraft,
          callParticipants: _callParticipants(),
          cameraViewFor: ref
              .read(voiceControllerProvider.notifier)
              .cameraViewFor,
          activityLog: _activityLog,
        ),
      ),
    );
  }
}
