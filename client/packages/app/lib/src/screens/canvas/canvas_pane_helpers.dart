// SPDX-License-Identifier: Apache-2.0
part of 'canvas_pane.dart';

/// The lazily-built helper objects `_CanvasPaneState` hands its child
/// widgets: split out once the floating call dock's own wiring pushed
/// `canvas_pane.dart` to the 500-line hard limit, the same reason
/// `_CanvasPaneGestures` already lives in its own `part of` file rather
/// than as a second class - these all need `_CanvasPaneState`'s own
/// fields. `_cursorLabel`, the one thing `_relay` needs beyond its own
/// constructor arguments, stays in `canvas_pane_gestures.dart` instead of
/// moving here too, since defining it in two `part of` files under
/// different extension names is a duplicate-member error, not a choice.
extension _CanvasPaneHelpers on _CanvasPaneState {
  CanvasImagePaste get _imagePaste => _imagePasteHelper ??= CanvasImagePaste(
    client: ref.read(apiProvider),
    channelId: widget.channelId,
    document: _document,
    onPlaced: _selectPlaced,
    onError: (message) => _refresh(() => _error = message),
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
      _refresh(() => _error = message);
    },
    onRemoved: (id) {
      _document
        ..removeObject(id)
        ..refresh();
      _refresh(
        () => _error = 'That stroke was erased while it was being saved.',
      );
    },
    onEraseOnConfirm: (id) => unawaited(_ops.eraseOnConfirm(id)),
  );

  CanvasOpsController get _ops => _opsController ??= CanvasOpsController(
    channelId: widget.channelId,
    client: ref.read(apiProvider),
    document: _document,
    commits: _commits,
    onError: (message) => _refresh(() => _error = message),
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
}
