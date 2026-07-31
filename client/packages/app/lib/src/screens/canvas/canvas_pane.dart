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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import '../../ids.dart';
import '../../providers/providers.dart';
import '../../providers/live_events.dart';
import 'canvas_bar.dart';
import 'canvas_commit_queue.dart';

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
  Timer? _panDebounce;

  Rect? _fetched;

  /// The view [_onCameraMoved] last examined, regardless of what it decided
  /// to do about it. See that method's doc for why this exists.
  Rect? _lastCameraView;
  bool _loading = true;
  String? _error;
  bool _truncated = false;
  int _localZ = provisionalLocalZIndex;

  @override
  void initState() {
    super.initState();
    _live = ref.read(liveEventsProvider).listen(_onEvent);
    // No fetch here: CanvasSurface's first setViewport call reaches _onCameraMoved below and fetches the real region, not a wasted one against a zero viewport.
    _document.addListener(_onCameraMoved);
  }

  @override
  void dispose() {
    _panDebounce?.cancel();
    _queue?.close();
    unawaited(_live?.cancel());
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
  );

  void _onEvent(api.ServerEvent event) {
    if (event is! api.CanvasObjectPlaced) return;
    if (event.channelId != widget.channelId) return;
    _apply(event.object);
  }

  void _apply(api.CanvasObject object) {
    final input = _toStroke(object);
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
        final input = _toStroke(object);
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

  CanvasStrokeInput? _toStroke(api.CanvasObject object) {
    if (object.kind != 'stroke') return null;
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
    );
  }

  void _onStroke(List<Offset> worldPoints) {
    for (final segment in splitStroke(worldPoints)) {
      final id = newCanvasObjectId();
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
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // No AppBar sits above CanvasBar, so this pane insets itself, or a stroke could start under the notch.
    return Container(
      color: tokens.surfaceBase,
      child: SafeArea(
        child: Column(
          children: [
            CanvasBar(
              channelId: widget.channelId,
              onClose: () => ref.read(canvasOpenProvider.notifier).state = null,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.s12),
                child: AppErrorState(
                  message: _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
              ),
            if (_truncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s12,
                  0,
                  AppSpacing.s12,
                  AppSpacing.s12,
                ),
                child: const AppCallout(
                  child: Text(
                    'Some ink in this region is not shown. Zoom in to see it.',
                  ),
                ),
              ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: _document.objectCount,
                builder: (context, count, child) => Semantics(
                  container: true,
                  label: _loading
                      ? 'Canvas, loading'
                      : 'Canvas, $count objects drawn',
                  child: child,
                ),
                child: CanvasSurface(
                  document: _document,
                  ink: AppCanvasColors.annotation,
                  gridLine: tokens.borderSubtle,
                  onStroke: _onStroke,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
