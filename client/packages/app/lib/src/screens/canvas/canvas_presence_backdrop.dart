// SPDX-License-Identifier: Apache-2.0
/// The visible half of a tile sent to the back: its own video and name
/// badge, painted *before* [CanvasSurface] in `canvas_pane_body.dart`'s own
/// Stack, so real ink drawn near it composites on top - answering "draw on
/// it" for a tile the owner has deliberately put behind the canvas.
///
/// Carries no gesture of its own, on purpose - see `canvas_presence_layer
/// .dart`'s own doc for the rendered probe that ruled out the shape that
/// would need one. [CanvasPresenceManipulableTile] still owns every tile's
/// drag, resize, lock and hide, at the same screen position, whichever side
/// of [CanvasSurface] its content happens to be painting on; this widget
/// only ever answers "what does a sent-to-back tile look like right now,"
/// never "did somebody just touch it."
library;

import 'package:flutter/widgets.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'canvas_presence_bubble.dart';
import 'canvas_presence_geometry.dart';

/// Identifies this widget's own [IgnorePointer] for a test to assert on
/// directly, rather than guessing at its position among any others a
/// descendant bubble happens to carry.
@visibleForTesting
const canvasPresenceBackdropIgnorePointerKey = Key(
  'canvas_presence_backdrop_ignore_pointer',
);

/// The non-interactive backdrop for every currently sent-to-back tile.
/// Renders nothing when none is - the common case - so an ordinary call
/// with every tile still in front pays nothing for this widget beyond the
/// two listeners it registers.
class CanvasPresenceBackdrop extends StatefulWidget {
  const CanvasPresenceBackdrop({
    super.key,
    required this.document,
    required this.participants,
    required this.cameraViewFor,
    required this.screenShareViewFor,
    required this.overrides,
    this.hideSelfCamera = false,
    this.layout = const CanvasPresenceLayout(),
  });

  final CanvasDocument document;
  final List<VoiceParticipant> participants;
  final CameraViewBuilder cameraViewFor;
  final ScreenShareViewBuilder screenShareViewFor;
  final CanvasPresenceTileOverrides overrides;
  final bool hideSelfCamera;
  final CanvasPresenceLayout layout;

  @override
  State<CanvasPresenceBackdrop> createState() => _CanvasPresenceBackdropState();
}

class _CanvasPresenceBackdropState extends State<CanvasPresenceBackdrop> {
  // Its own instance, computed over the same full onCanvas map CanvasPresenceLayer's own instance sees - see build() below for why that keeps the two in step.
  final CanvasPresenceVisibility _visibility = CanvasPresenceVisibility();

  @override
  void initState() {
    super.initState();
    widget.document.addListener(_onChanged);
    widget.overrides.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant CanvasPresenceBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onChanged);
      widget.document.addListener(_onChanged);
    }
    if (oldWidget.overrides != widget.overrides) {
      oldWidget.overrides.removeListener(_onChanged);
      widget.overrides.addListener(_onChanged);
    }
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
    // The full onCanvas map, not a pre-filtered one - the two widgets' separate CanvasPresenceVisibility instances would drift apart otherwise.
    final visibleIds = _visibility.update(widget.document.worldView, onCanvas);
    final backKeys = visibleIds
        .where((key) => widget.overrides.stateFor(key).sentToBack)
        .toSet();
    if (backKeys.isEmpty) return const SizedBox.shrink();
    final camera = widget.document.camera;
    final painted = presencePaintOrder(backKeys, widget.overrides.zFor);
    return IgnorePointer(
      key: canvasPresenceBackdropIgnorePointerKey,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final key in painted)
            if (_bubble(key, onCanvas[key]!, camera, byIdentity) case final b?)
              b,
        ],
      ),
    );
  }

  Widget? _bubble(
    String key,
    Rect worldRect,
    Camera camera,
    Map<String, VoiceParticipant> byIdentity,
  ) {
    final isScreen = presenceTileKind(key) == screenTrackKind;
    final identity = presenceTileIdentity(key);
    final participant = byIdentity[identity];
    if (participant == null) return null;
    final screen = presenceScreenRect(worldRect, camera);
    return Positioned(
      key: ValueKey(key),
      left: screen.left,
      top: screen.top,
      width: screen.width,
      height: screen.height,
      child: isScreen
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
