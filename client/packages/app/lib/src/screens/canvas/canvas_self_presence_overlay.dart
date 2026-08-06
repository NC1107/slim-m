// SPDX-License-Identifier: Apache-2.0
/// The caller's own camera bubble: a floating, screen-anchored overlay
/// rather than a tile placed in canvas world space, and the one presence
/// tile a person may drag out of the way or hide entirely.
///
/// `CanvasPresenceLayer` places every *other* participant deterministically
/// in world space and pans with the canvas exactly like a drawn object
/// would - that is right for them, since seeing where a collaborator sits
/// relative to the ink is the point. A self-view answers a different
/// question ("am I still on this call, and how do I look"), the one every
/// call app already treats as an ordinary, always-available control to hide
/// or move, where hiding someone *else's* tile is a rarer, different act.
/// So the caller's own bubble lives here instead: always on top, never
/// panning, snapped to one of the pane's four corners rather than an
/// arbitrary pixel (a corner recomputes its position from whatever size the
/// pane is now, where a raw remembered offset would drift toward or past an
/// edge the first time the window is narrower), and it alone may be hidden.
///
/// **A right-click on the bubble is absorbed and does nothing, deliberately.**
/// `CanvasObjectContextMenu` hit-tests world space under the pointer for a
/// canvas object to open a menu for, and this overlay sits stacked above it;
/// without an explicit answer here, a right-click on the bubble would either
/// leak through to whatever ink it happens to be covering (surprising - nobody
/// asked to edit content they cannot see) or silently do nothing as a mere
/// side effect of gesture-arena resolution rather than a choice this file
/// made. The bubble is not a canvas object and has no bring-to-front/
/// send-to-back/delete verbs that would mean anything for it, so absorbing
/// is correct; the no-op secondary-tap handler below is what makes it a
/// guaranteed outcome rather than an accident of stacking order.
///
/// **A second overlay, `CanvasCallDock`, floats over the pane's own bottom
/// band, and the two never knew about each other until the dock existed.**
/// A self bubble only ever renders while this device is on the call in this
/// channel (see [_CanvasSelfPresenceOverlayState._self]), which is exactly
/// when the dock is guaranteed to be showing its own call row too - so the
/// two are never merely occasionally in the same place, they collide by
/// construction whenever either is visible at all. [bottomReserved] is how
/// the bubble yields: `canvas_pane_body.dart` measures the dock's own
/// worst-case height from real layout constants (never a guess) and passes
/// it here, so both of the bubble's bottom corners - and a drag's own lower
/// bound - stay clear of the dock rather than resting under it. The bubble
/// yields rather than the dock, because its resting corner is a saved
/// preference somebody dragged it to on purpose, where the dock's position
/// is fixed by the design this whole feature exists to ship.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../../providers/canvas_self_presence.dart';
import 'canvas_presence_layer.dart';

/// A camera-off self tile is only ever an avatar, name and mic glyph - the
/// least informative tile on the whole canvas, since a person already knows
/// what they look like - so it rests noticeably smaller than a camera-on one
/// or a remote participant's tile, rather than spending a full card on it.
const _cameraOnSize = Size(168, 120);
const _cameraOffSize = Size(104, 104);

class CanvasSelfPresenceOverlay extends StatefulWidget {
  const CanvasSelfPresenceOverlay({
    super.key,
    required this.participants,
    required this.cameraViewFor,
    required this.hidden,
    required this.corner,
    required this.onCornerChanged,
    this.margin = 16,
    this.bottomReserved = 0,
  });

  /// The full call roster; only the caller's own entry (`isLocal`) is ever
  /// drawn here - everyone else is `CanvasPresenceLayer`'s job, and this
  /// widget renders nothing at all when no entry is local.
  final List<VoiceParticipant> participants;
  final CameraViewBuilder cameraViewFor;
  final bool hidden;
  final CanvasSelfBubbleCorner corner;
  final ValueChanged<CanvasSelfBubbleCorner> onCornerChanged;
  final double margin;

  /// Extra clearance kept below the bubble's two bottom corners, and below
  /// a drag's own lower bound - see this file's own library doc for why.
  final double bottomReserved;

  @override
  State<CanvasSelfPresenceOverlay> createState() =>
      _CanvasSelfPresenceOverlayState();
}

class _CanvasSelfPresenceOverlayState extends State<CanvasSelfPresenceOverlay> {
  /// The top-left position while a drag is under way, in this overlay's own
  /// local coordinates; null whenever the bubble is at rest, which is what
  /// tells [build] to fall back to the corner-derived resting position.
  Offset? _dragPosition;

  Size _sizeFor(VoiceParticipant participant) =>
      participant.isCameraOn ? _cameraOnSize : _cameraOffSize;

  Offset _restPosition(Size area, Size tile) {
    final left = switch (widget.corner) {
      CanvasSelfBubbleCorner.topLeft ||
      CanvasSelfBubbleCorner.bottomLeft => widget.margin,
      CanvasSelfBubbleCorner.topRight || CanvasSelfBubbleCorner.bottomRight =>
        area.width - tile.width - widget.margin,
    };
    final top = switch (widget.corner) {
      CanvasSelfBubbleCorner.topLeft ||
      CanvasSelfBubbleCorner.topRight => widget.margin,
      CanvasSelfBubbleCorner.bottomLeft || CanvasSelfBubbleCorner.bottomRight =>
        area.height - tile.height - widget.margin - widget.bottomReserved,
    };
    return Offset(left.clamp(0, area.width), top.clamp(0, area.height));
  }

  /// The corner whose quadrant the tile's own centre now sits in - a coarse
  /// four-way split rather than a nearest-of-four-points distance, so a
  /// drag released anywhere in, say, the top-left quarter of the pane always
  /// settles top-left regardless of exactly how far into it the release was.
  CanvasSelfBubbleCorner _nearestCorner(Offset topLeft, Size area, Size tile) {
    final center = topLeft + Offset(tile.width / 2, tile.height / 2);
    final left = center.dx < area.width / 2;
    final top = center.dy < area.height / 2;
    if (top) {
      return left
          ? CanvasSelfBubbleCorner.topLeft
          : CanvasSelfBubbleCorner.topRight;
    }
    return left
        ? CanvasSelfBubbleCorner.bottomLeft
        : CanvasSelfBubbleCorner.bottomRight;
  }

  VoiceParticipant? _self() {
    for (final participant in widget.participants) {
      if (participant.isLocal) return participant;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hidden) return const SizedBox.shrink();
    final participant = _self();
    if (participant == null) return const SizedBox.shrink();
    final tile = _sizeFor(participant);
    // An inner Stack, not a bare Positioned, or LayoutBuilder's own RenderObject breaks Positioned's parent-data lookup.
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(constraints.maxWidth, constraints.maxHeight);
        final rest = _restPosition(area, tile);
        final position = _dragPosition ?? rest;
        final dragging = _dragPosition != null;
        final maxX = (area.width - tile.width).clamp(0.0, double.infinity);
        final maxY = (area.height - tile.height - widget.bottomReserved).clamp(
          0.0,
          double.infinity,
        );
        return Stack(
          children: [
            AnimatedPositioned(
              duration: dragging
                  ? Duration.zero
                  : AppMotion.reduced(context, AppMotion.base),
              curve: AppMotion.entrance,
              left: position.dx,
              top: position.dy,
              width: tile.width,
              height: tile.height,
              child: GestureDetector(
                // A no-op, not an omission: see this file's own library doc for why a right-click here must never reach the canvas object menu beneath.
                onSecondaryTapUp: (_) {},
                onPanStart: (_) => setState(() => _dragPosition = rest),
                onPanUpdate: (details) => setState(() {
                  final next = (_dragPosition ?? rest) + details.delta;
                  _dragPosition = Offset(
                    next.dx.clamp(0.0, maxX),
                    next.dy.clamp(0.0, maxY),
                  );
                }),
                onPanEnd: (_) {
                  final settled = _dragPosition ?? rest;
                  final corner = _nearestCorner(settled, area, tile);
                  setState(() => _dragPosition = null);
                  if (corner != widget.corner) widget.onCornerChanged(corner);
                },
                child: CanvasPresenceBubble(
                  participant: participant,
                  cameraView: participant.isCameraOn
                      ? widget.cameraViewFor(participant.identity)
                      : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
