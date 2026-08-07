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
/// hide, kept in [CanvasPresenceTileOverrides] rather than a
/// `canvas_objects` row. It is a *personal* arrangement, one viewer's own -
/// see that decision record for why a shared one was rejected.
///
/// This used to render the caller's own bubble nowhere at all (a separate,
/// screen-anchored overlay owned that), which is exactly the "stuck to the
/// dock" complaint the owner reported: a fixed screen corner blocks whatever
/// world content happens to pan underneath it, forever, rather than sitting
/// at one place a person chose. Self and remote are one list now.
library;

import 'package:flutter/material.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'canvas_presence_bubble.dart';
import 'canvas_presence_tile.dart';

export 'canvas_presence_bubble.dart';

typedef CameraViewBuilder = Widget Function(String identity);
typedef ScreenShareViewBuilder = Widget Function(String identity);

const _cameraOnSize = Size(220, 160);
const _cameraOffSize = Size(140, 140);
const _screenShareSize = Size(360, 203);

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
    this.hideSelfCamera = false,
    this.layout = const CanvasPresenceLayout(),
  });

  final CanvasDocument document;
  final List<VoiceParticipant> participants;
  final CameraViewBuilder cameraViewFor;
  final ScreenShareViewBuilder screenShareViewFor;
  final CanvasPresenceTileOverrides overrides;

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
    // Before build, never during it: a participant who left the call must not keep their drag, lock or hide the next time they rejoin.
    widget.overrides.prune(_currentKeys());
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

  Set<String> _currentKeys() {
    final keys = <String>{};
    for (final p in widget.participants) {
      keys.add('camera:${p.identity}');
      if (p.isScreenSharing) keys.add('screen:${p.identity}');
    }
    return keys;
  }

  Size _sizeFor(String key, Map<String, VoiceParticipant> byIdentity) {
    if (key.startsWith('screen:')) return _screenShareSize;
    final participant = byIdentity[key.substring('camera:'.length)];
    return (participant?.isCameraOn ?? false) ? _cameraOnSize : _cameraOffSize;
  }

  @override
  Widget build(BuildContext context) {
    final keys = _currentKeys();
    if (keys.isEmpty) return const SizedBox.shrink();
    final byIdentity = {for (final p in widget.participants) p.identity: p};
    final defaults = widget.layout.arrange(
      keys,
      sizeFor: (key) => _sizeFor(key, byIdentity),
    );
    final onCanvas = <String, Rect>{};
    for (final key in keys) {
      final state = widget.overrides.stateFor(key);
      if (state.hidden) continue;
      if (widget.hideSelfCamera &&
          key.startsWith('camera:') &&
          byIdentity[key.substring('camera:'.length)]?.isLocal == true) {
        continue;
      }
      onCanvas[key] = state.rect ?? defaults[key]!;
    }
    if (onCanvas.isEmpty) return const SizedBox.shrink();
    final visibleIds = _visibility.update(widget.document.worldView, onCanvas);
    if (visibleIds.isEmpty) return const SizedBox.shrink();
    final camera = widget.document.camera;
    final painted = _paintOrder(visibleIds);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final key in painted)
          if (_tile(key, onCanvas[key]!, camera, byIdentity) case final tile?)
            tile,
      ],
    );
  }

  /// [visibleIds] sorted so a tile this viewer has ever dragged or resized
  /// paints above every untouched one, most recently touched last (topmost),
  /// and untouched tiles keep their own relative order - a real sheet of
  /// paper does not slide under the pile just because somebody else's is
  /// also on the table.
  List<String> _paintOrder(Set<String> visibleIds) {
    final ordered = visibleIds.toList(growable: false);
    final rank = <String, int>{
      for (var i = 0; i < ordered.length; i++) ordered[i]: i,
    };
    final withZ = ordered
        .map((key) => (key: key, z: widget.overrides.zFor(key) ?? -1))
        .toList();
    withZ.sort((a, b) {
      final byZ = a.z.compareTo(b.z);
      return byZ != 0 ? byZ : rank[a.key]!.compareTo(rank[b.key]!);
    });
    return [for (final entry in withZ) entry.key];
  }

  Widget? _tile(
    String key,
    Rect rect,
    Camera camera,
    Map<String, VoiceParticipant> byIdentity,
  ) {
    final isScreen = key.startsWith('screen:');
    final identity = key.substring(key.indexOf(':') + 1);
    final participant = byIdentity[identity];
    if (participant == null) return null;
    final locked = widget.overrides.stateFor(key).locked;
    return CanvasPresenceManipulableTile(
      key: ValueKey(key),
      worldRect: rect,
      camera: camera,
      locked: locked,
      onRectChanged: (next) => widget.overrides.setRect(key, next),
      onToggleLocked: () => widget.overrides.setLocked(key, !locked),
      onHide: () => widget.overrides.setHidden(key, true),
      semanticLabel: isScreen
          ? (participant.isLocal
                ? "Your screen share, on this call's canvas"
                : "${participant.name}'s screen share, on this call's canvas")
          : '${participant.name}${participant.isLocal ? ', you' : ''}, '
                "on this call's canvas",
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
