// SPDX-License-Identifier: Apache-2.0
/// Camera bubbles for whoever is on this channel's call, positioned in the
/// canvas's own world-coordinate space.
///
/// A widget layer stacked over [CanvasSurface], never painted into it: a
/// live camera track is a platform `Texture` (`VoiceSession.cameraViewFor`
/// already returns one wrapped as a plain `Widget`, per that method's own
/// doc), and there is no supported way to sample a `Texture`'s pixels into a
/// `CustomPainter`'s `Canvas` without an expensive manual frame capture this
/// package does not do anywhere else. So presence is the topmost layer in
/// its own `Stack` entry, exactly the shape `docs/STRATEGY.md` names: "a
/// presence video-texture layer so LiveKit's video updates never trigger
/// stroke or image repaints" - a separate layer was always the plan, and a
/// `Texture` is the reason it has to be, not only the reason it is fastest.
///
/// [IgnorePointer]-wrapped throughout: a remote bubble never drags, so
/// nothing here may steal a pointer the canvas surface underneath still
/// needs for drawing, panning or erasing. The caller's own bubble is the one
/// exception - it does drag, and hide - and it lives in
/// `canvas_self_presence_overlay.dart` instead, a separate screen-anchored
/// layer rather than one more case in this world-anchored one. This layer
/// therefore renders every participant *but* the caller: `[VoiceParticipant]
/// .isLocal` is the split.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import '../../widgets/user_avatar.dart';

/// Builds the live camera widget for one participant, exactly
/// `VoiceController.cameraViewFor`'s signature - a plain function so this
/// file never imports the provider layer, matching `CanvasPaneBody`'s own
/// "nothing here reaches Riverpod" rule one level further down.
typedef CameraViewBuilder = Widget Function(String identity);

/// The *other* call participants' layer, positioned in world space and
/// following the canvas's own camera. Renders nothing when [participants]
/// holds nobody but the caller - or nobody at all - so a canvas opened on a
/// channel with no active call, or opened by someone who has not joined the
/// call themselves, pays for none of this. The caller's own tile is never
/// drawn here; see this file's own library doc for where it lives instead.
class CanvasPresenceLayer extends StatefulWidget {
  const CanvasPresenceLayer({
    super.key,
    required this.document,
    required this.participants,
    required this.cameraViewFor,
    this.layout = const CanvasPresenceLayout(),
  });

  final CanvasDocument document;
  final List<VoiceParticipant> participants;
  final CameraViewBuilder cameraViewFor;
  final CanvasPresenceLayout layout;

  @override
  State<CanvasPresenceLayer> createState() => _CanvasPresenceLayerState();
}

class _CanvasPresenceLayerState extends State<CanvasPresenceLayer> {
  /// Kept across builds, not rebuilt per frame: the hysteresis band this
  /// class exists for only works if "was this bubble mounted a moment ago"
  /// survives from one recomputation to the next.
  final CanvasPresenceVisibility _visibility = CanvasPresenceVisibility();

  @override
  void initState() {
    super.initState();
    widget.document.addListener(_onDocumentChanged);
  }

  @override
  void didUpdateWidget(covariant CanvasPresenceLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onDocumentChanged);
      widget.document.addListener(_onDocumentChanged);
    }
  }

  @override
  void dispose() {
    widget.document.removeListener(_onDocumentChanged);
    super.dispose();
  }

  void _onDocumentChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final remote = widget.participants
        .where((p) => !p.isLocal)
        .toList(growable: false);
    if (remote.isEmpty) return const SizedBox.shrink();
    final bubbles = widget.layout.arrange(remote.map((p) => p.identity));
    final visibleIds = _visibility.update(widget.document.worldView, bubbles);
    if (visibleIds.isEmpty) return const SizedBox.shrink();
    final camera = widget.document.camera;
    final byIdentity = {for (final p in remote) p.identity: p};
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final id in visibleIds)
            if (byIdentity[id] case final participant?)
              _positioned(bubbles[id]!, camera, participant),
        ],
      ),
    );
  }

  Widget _positioned(Rect world, Camera camera, VoiceParticipant participant) {
    return Positioned(
      left: (world.left - camera.x) * camera.zoom,
      top: (world.top - camera.y) * camera.zoom,
      width: world.width * camera.zoom,
      height: world.height * camera.zoom,
      child: CanvasPresenceBubble(
        participant: participant,
        cameraView: participant.isCameraOn
            ? widget.cameraViewFor(participant.identity)
            : null,
      ),
    );
  }
}

/// One participant's tile: their live camera when it is on, an avatar with
/// the usual speaking ring otherwise - `CallParticipantTile`'s own fallback,
/// reused rather than redrawn, since the answer to "no video, still present"
/// is the same question that tile already answers for the in-call screen.
class CanvasPresenceBubble extends StatelessWidget {
  const CanvasPresenceBubble({
    super.key,
    required this.participant,
    this.cameraView,
  });

  final VoiceParticipant participant;
  final Widget? cameraView;

  bool get _showsCamera => cameraView != null && participant.isCameraOn;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      label:
          '${participant.name}${participant.isLocal ? ', you' : ''}, '
          'on this call\'s canvas',
      // AppRadii.window and AppShadows.float: reserved, by their own docs, for exactly a floating canvas object - a bubble is always one, never only while dragged, since nothing here is draggable yet.
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.window),
          boxShadow: AppShadows.float,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.window),
          child: Container(
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_showsCamera)
                  DecoratedBox(
                    decoration: const BoxDecoration(color: Color(0xFF000000)),
                    child: cameraView,
                  )
                else
                  UserAvatar(
                    name: participant.name,
                    userId: participant.identity,
                    size: 56,
                    speaking: participant.isSpeaking,
                  ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: _NameBadge(
                    name: participant.isLocal
                        ? '${participant.name} (you)'
                        : participant.name,
                    muted: participant.isMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NameBadge extends StatelessWidget {
  const _NameBadge({required this.name, required this.muted});

  final String name;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceBase.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            muted ? AppIcons.micOff : AppIcons.mic,
            size: 12,
            color: muted ? tokens.textSecondary : tokens.accent,
          ),
          const SizedBox(width: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: tokens.textPrimary),
          ),
        ],
      ),
    );
  }
}
