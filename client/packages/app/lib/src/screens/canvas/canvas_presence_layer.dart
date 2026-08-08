// SPDX-License-Identifier: Apache-2.0
/// Camera and screen-share tiles for whoever is on this channel's call -
/// including the caller's own - positioned in the canvas's own
/// world-coordinate space, exactly the AR-glasses framing the owner asked
/// for: "make the screen as big or small as you want, draw on it, hide it,
/// lock it in place."
///
/// A widget layer stacked over [CanvasSurface], never painted into it: a
/// live camera or screen-share track is a platform `Texture`
/// (`VoiceSession.cameraViewFor`/`screenShareViewFor` already return one
/// wrapped as a plain `Widget`, per their own docs), and there is no
/// supported way to sample a `Texture`'s pixels into a `CustomPainter`'s
/// `Canvas` without an expensive manual frame capture this package does not
/// do anywhere else. So presence is the topmost layer in its own `Stack`
/// entry, exactly the shape `docs/STRATEGY.md` names: "a presence
/// video-texture layer so LiveKit's video updates never trigger stroke or
/// image repaints."
///
/// **Every tile is presence, never a [CanvasObjectKind]**, and that is a
/// decision recorded in `docs/decisions/0010-canvas-media-tiles.md`, not an
/// oversight: STRATEGY already called camera bubbles and screen-share tiles
/// "ephemeral presence objects never written to the op log and reset on
/// rejoin", and this file extends that same line to position, size, lock and
/// depth, kept in [CanvasPresenceTileOverrides] rather than a
/// `canvas_objects` row. Position, size, lock and depth are shared and
/// persistent now - decision 0010's own reversal of its first call, mirrored
/// from the server's `canvas_media_slots` table by `CanvasMediaSlotSync` in
/// the app's own canvas screen. Only [CanvasPresenceTileOverrides.hidden]
/// stays personal and per-call; see that class's own doc for why.
///
/// This used to render the caller's own bubble nowhere at all (a separate,
/// screen-anchored overlay owned that), which is exactly the "stuck to the
/// dock" complaint the owner reported: a fixed screen corner blocks whatever
/// world content happens to pan underneath it, forever, rather than sitting
/// at one place a person chose. Self and remote are one list now.
///
/// **Sending a tile to the back never moves this widget, or any tile's own
/// controls with it.** A rendered probe proved the obvious version of that
/// feature - reordering the whole manipulable tile below [CanvasSurface] in
/// the pane's Stack - does not merely dim a control, it deletes it:
/// [CanvasSurface] covers its full bounds with an opaque `MouseRegion` for
/// pan and draw, and Flutter's own Stack hit-testing stops at the first
/// child claiming a hit, topmost first, so nothing painted behind it is ever
/// hit-tested again. `CanvasPresenceBackdrop` is the fix: only a
/// sent-to-back tile's *content* (its video, its name badge) moves into that
/// separate, non-interactive, `IgnorePointer`-wrapped widget, painted before
/// [CanvasSurface] so real ink lands over it; the drag area, resize grip and
/// corner controls stay here, at the same screen position, regardless of
/// depth - the same "never a dead end" guarantee `locked` already makes for
/// its own unlock button.
library;

import 'package:flutter/material.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'canvas_presence_bubble.dart';
import 'canvas_presence_geometry.dart';
import 'canvas_presence_tile.dart';

export 'canvas_presence_backdrop.dart';
export 'canvas_presence_bubble.dart';
export 'canvas_presence_geometry.dart'
    show CameraViewBuilder, ScreenShareViewBuilder;

/// Every call participant's tiles, world-anchored and individually
/// draggable, resizable, lockable and hideable through [overrides]. Renders
/// nothing when [participants] is empty, so a canvas opened on a channel
/// with no active call pays for none of this.
class CanvasPresenceLayer extends StatefulWidget {
  const CanvasPresenceLayer({
    super.key,
    required this.document,
    required this.participants,
    required this.cameraViewFor,
    required this.screenShareViewFor,
    required this.overrides,
    required this.onCommit,
    this.hideSelfCamera = false,
    this.layout = const CanvasPresenceLayout(),
  });

  final CanvasDocument document;
  final List<VoiceParticipant> participants;
  final CameraViewBuilder cameraViewFor;
  final ScreenShareViewBuilder screenShareViewFor;
  final CanvasPresenceTileOverrides overrides;

  /// Sends [overrides]' current answer for one tile key onward to the
  /// server - see `CanvasMediaSlotSync.commit` in the app's own canvas
  /// screen, which is what this closes over. Fired once a drag or resize
  /// settles, and immediately on a lock or depth toggle; never fired for
  /// [overrides.setHidden], which needs no commit at all.
  final void Function(String key, Rect rect) onCommit;

  /// The caller's own standing "never show my own camera" preference
  /// (`canvas_self_presence.dart`), layered on top of whatever
  /// [overrides] says for `camera:<selfId>` - distinct from a per-call hide,
  /// since this one is meant to survive a rejoin rather than reset with it.
  /// Never suppresses a self screen-share tile: that preference is about a
  /// face, not about whatever this device is sharing.
  final bool hideSelfCamera;
  final CanvasPresenceLayout layout;

  @override
  State<CanvasPresenceLayer> createState() => _CanvasPresenceLayerState();
}

class _CanvasPresenceLayerState extends State<CanvasPresenceLayer> {
  final CanvasPresenceVisibility _visibility = CanvasPresenceVisibility();

  @override
  void initState() {
    super.initState();
    widget.document.addListener(_onChanged);
    widget.overrides.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant CanvasPresenceLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onChanged);
      widget.document.addListener(_onChanged);
    }
    if (oldWidget.overrides != widget.overrides) {
      oldWidget.overrides.removeListener(_onChanged);
      widget.overrides.addListener(_onChanged);
    }
    // After this frame, not inside didUpdateWidget: overrides is shared with the dock's own still-mid-reconciliation ListenableBuilder, and notifyListeners() reaching it here throws "setState() called during build".
    final overrides = widget.overrides;
    final keys = presenceTileKeys(widget.participants);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.overrides == overrides) overrides.prune(keys);
    });
  }

  @override
  void dispose() {
    widget.document.removeListener(_onChanged);
    widget.overrides.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final keys = presenceTileKeys(widget.participants);
    if (keys.isEmpty) return const SizedBox.shrink();
    final byIdentity = {for (final p in widget.participants) p.identity: p};
    final onCanvas = presenceOnCanvasRects(
      keys: keys,
      layout: widget.layout,
      overrides: widget.overrides,
      byIdentity: byIdentity,
      hideSelfCamera: widget.hideSelfCamera,
    );
    if (onCanvas.isEmpty) return const SizedBox.shrink();
    final visibleIds = _visibility.update(widget.document.worldView, onCanvas);
    if (visibleIds.isEmpty) return const SizedBox.shrink();
    final camera = widget.document.camera;
    final painted = presencePaintOrder(visibleIds, widget.overrides.zFor);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final key in painted)
          if (_tile(key, onCanvas[key]!, camera, byIdentity) case final tile?)
            tile,
      ],
    );
  }

  Widget? _tile(
    String key,
    Rect rect,
    Camera camera,
    Map<String, VoiceParticipant> byIdentity,
  ) {
    final isScreen = presenceTileKind(key) == 'screen';
    final identity = presenceTileIdentity(key);
    final participant = byIdentity[identity];
    if (participant == null) return null;
    final state = widget.overrides.stateFor(key);
    final locked = state.locked;
    final sentToBack = state.sentToBack;
    // Never null: the override's own rect once set, this build's resolved default otherwise.
    void commit() =>
        widget.onCommit(key, widget.overrides.stateFor(key).rect ?? rect);
    return CanvasPresenceManipulableTile(
      key: ValueKey(key),
      worldRect: rect,
      camera: camera,
      locked: locked,
      sentToBack: sentToBack,
      document: widget.document,
      onRectChanged: (next) => widget.overrides.setRect(key, next),
      onRectCommitted: commit,
      onToggleLocked: () {
        widget.overrides.setLocked(key, !locked);
        commit();
      },
      onToggleSentToBack: () {
        widget.overrides.setSentToBack(key, !sentToBack);
        commit();
      },
      onHide: () => widget.overrides.setHidden(key, true),
      semanticLabel: isScreen
          ? (participant.isLocal
                ? "Your screen share, on this call's canvas"
                : "${participant.name}'s screen share, on this call's canvas")
          : '${participant.name}${participant.isLocal ? ', you' : ''}, '
                "on this call's canvas",
      // Real content moves to CanvasPresenceBackdrop when sent to back; .expand, not .shrink, or the wrapping GestureDetector's own opaque hit box shrinks with it.
      child: sentToBack
          ? const SizedBox.expand()
          : isScreen
          ? CanvasScreenShareBubble(
              participant: participant,
              view: widget.screenShareViewFor(identity),
            )
          : CanvasPresenceBubble(
              participant: participant,
              cameraView: participant.isCameraOn
                  ? widget.cameraViewFor(identity)
                  : null,
            ),
    );
  }
}
