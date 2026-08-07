// SPDX-License-Identifier: Apache-2.0
/// The AR-glasses interaction the owner asked for by name: a camera or
/// screen-share tile you can drag anywhere in the canvas's own world space,
/// resize with a grip, lock so a drawing tool reaches through it, or hide.
///
/// Deliberately not built on the drag-and-resize state machine
/// `canvas_ops_controller_select.dart` already drives for a real
/// [CanvasObjectKind] - a presence tile is not one of those (see
/// `canvas_presence_layer.dart`'s own doc for why), so it owns a short,
/// self-contained gesture handler instead, the same shape the self bubble's
/// old screen-anchored drag already used before this file replaced it.
///
/// [CanvasPresenceManipulableTile.locked] wraps only the content in
/// [IgnorePointer]: the resize grip disappears (nothing to resize while
/// locked) but the lock control itself never does, or a locked tile would be
/// a dead end with no way back.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

/// The world-space box a resize may not shrink below or grow past - small
/// enough that the name badge and controls still fit, large enough that a
/// single tile can never swallow a typical viewport.
const canvasPresenceTileMinSize = Size(72, 54);
const canvasPresenceTileMaxSize = Size(720, 540);

class CanvasPresenceManipulableTile extends StatefulWidget {
  const CanvasPresenceManipulableTile({
    super.key,
    required this.worldRect,
    required this.camera,
    required this.locked,
    required this.onRectChanged,
    required this.onToggleLocked,
    required this.onHide,
    required this.semanticLabel,
    required this.child,
  });

  final Rect worldRect;
  final Camera camera;
  final bool locked;

  /// Fired on every drag/resize update, in world space - the caller owns
  /// persisting it (`CanvasPresenceTileOverrides.setRect`), this widget owns
  /// only the arithmetic and the live-while-dragging feel.
  final ValueChanged<Rect> onRectChanged;
  final VoidCallback onToggleLocked;
  final VoidCallback onHide;
  final String semanticLabel;
  final Widget child;

  @override
  State<CanvasPresenceManipulableTile> createState() =>
      _CanvasPresenceManipulableTileState();
}

class _CanvasPresenceManipulableTileState
    extends State<CanvasPresenceManipulableTile> {
  /// Non-null only while a drag or resize is in flight. Tracking it locally,
  /// rather than trusting [CanvasPresenceManipulableTile.worldRect] to have
  /// already round-tripped through the caller's own state and back by the
  /// next pointer event, is what keeps a fast drag from stuttering on a
  /// rebuild that has not landed yet.
  Rect? _liveRect;

  Rect get _rect => _liveRect ?? widget.worldRect;

  void _drag(DragUpdateDetails details) {
    final next = _rect.shift(details.delta / widget.camera.zoom);
    setState(() => _liveRect = next);
    widget.onRectChanged(next);
  }

  void _resize(DragUpdateDetails details) {
    final delta = details.delta / widget.camera.zoom;
    final current = _rect;
    final width = (current.width + delta.dx).clamp(
      canvasPresenceTileMinSize.width,
      canvasPresenceTileMaxSize.width,
    );
    final height = (current.height + delta.dy).clamp(
      canvasPresenceTileMinSize.height,
      canvasPresenceTileMaxSize.height,
    );
    final next = Rect.fromLTWH(current.left, current.top, width, height);
    setState(() => _liveRect = next);
    widget.onRectChanged(next);
  }

  void _settle(DragEndDetails details) => setState(() => _liveRect = null);

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    final camera = widget.camera;
    final screen = Rect.fromLTWH(
      (rect.left - camera.x) * camera.zoom,
      (rect.top - camera.y) * camera.zoom,
      rect.width * camera.zoom,
      rect.height * camera.zoom,
    );
    return Positioned(
      left: screen.left,
      top: screen.top,
      width: screen.width,
      height: screen.height,
      child: Semantics(
        container: true,
        label: widget.semanticLabel,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            IgnorePointer(
              ignoring: widget.locked,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // A no-op, not an omission: a right-click on a tile must never leak to a canvas object underneath it, `canvas_self_presence_overlay.dart`'s old precedent for this exact absorption.
                onSecondaryTapUp: (_) {},
                onPanUpdate: _drag,
                onPanEnd: _settle,
                child: widget.child,
              ),
            ),
            if (!widget.locked)
              Positioned(
                right: -4,
                bottom: -4,
                child: _ResizeGrip(onUpdate: _resize, onEnd: _settle),
              ),
            Positioned(
              right: 2,
              top: 2,
              child: _TileControls(
                locked: widget.locked,
                onToggleLocked: widget.onToggleLocked,
                onHide: widget.onHide,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResizeGrip extends StatelessWidget {
  const _ResizeGrip({required this.onUpdate, required this.onEnd});

  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpLeftDownRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: onUpdate,
        onPanEnd: onEnd,
        child: Container(
          width: AppSizes.controlSm,
          height: AppSizes.controlSm,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.surfaceBase.withValues(alpha: 0.85),
            shape: BoxShape.circle,
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Icon(
            AppIcons.tileResize,
            size: AppSizes.icon16,
            color: tokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _TileControls extends StatelessWidget {
  const _TileControls({
    required this.locked,
    required this.onToggleLocked,
    required this.onHide,
  });

  final bool locked;
  final VoidCallback onToggleLocked;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: tokens.surfaceBase.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconButton(
            icon: locked ? AppIcons.tileLocked : AppIcons.tileUnlocked,
            semanticLabel: locked
                ? 'Unlock this tile'
                : 'Lock this tile in place',
            tooltip: locked
                ? 'Unlock - drag and resize again'
                : 'Lock in place - a drawing tool reaches through it',
            size: AppIconButtonSize.sm,
            active: locked,
            onPressed: onToggleLocked,
          ),
          AppIconButton(
            icon: AppIcons.tileHide,
            semanticLabel: 'Hide this tile on your canvas',
            tooltip: 'Hide on your canvas',
            size: AppIconButtonSize.sm,
            onPressed: onHide,
          ),
        ],
      ),
    );
  }
}
