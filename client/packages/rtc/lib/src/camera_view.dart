// SPDX-License-Identifier: Apache-2.0
/// Renders one participant's live camera feed.
///
/// Not exported from the package barrel, for the same reason
/// `screen_share_view.dart` is not: it takes LiveKit types, and the seam
/// this package exists for is that nothing outside it does. The app reaches
/// it through `VoiceSession.cameraViewFor`, which returns it as a plain
/// `Widget`.
///
/// Local and remote alike, unlike an earlier version of `ScreenShareView`
/// that only ever looked at `remoteParticipants`: a local camera preview is
/// exactly the surface that was missing when the owner reported turning a
/// camera on alone in a call and seeing nothing.
///
/// A local front-facing preview mirrors, the same way a real mirror only
/// ever shows the person looking into it; a local back-facing one, and any
/// remote participant's camera regardless of facing, never does. See
/// `mirrorModeFor` in `camera_switching.dart` for the decision itself.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'camera_switching.dart';

/// One participant's camera video, tracking the room live: a published track
/// routinely arrives a beat after the roster learns a camera is on, the same
/// reason `ScreenShareView` watches room events rather than trusting the
/// state at build time.
class CameraView extends StatefulWidget {
  const CameraView({
    super.key,
    required this.room,
    required this.identity,
    required this.facing,
  });

  final lk.Room room;

  /// Whose camera to render, by server user id. May be the local
  /// participant's own identity.
  final String identity;

  /// This session's own camera facing, only ever meaningful when
  /// [identity] turns out to be the local participant - a flip on this
  /// device says nothing about anyone else's camera.
  final ValueListenable<CameraFacing> facing;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  lk.CancelListenFunc? _cancel;

  @override
  void initState() {
    super.initState();
    _cancel = widget.room.events.listen((_) {
      if (mounted) setState(() {});
    });
    // A flip fires no room event at all, so the mirror needs its own listener.
    widget.facing.addListener(_onFacingChanged);
  }

  void _onFacingChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cancel?.call();
    widget.facing.removeListener(_onFacingChanged);
    super.dispose();
  }

  bool get _isLocal =>
      widget.room.localParticipant?.identity == widget.identity;

  /// Checked as two concretely-typed branches, not one lookup returning the
  /// abstract `Participant`: losing the concrete type there widens
  /// `videoTrackPublications`' element type to a bare `Track`, which no
  /// longer satisfies this method's `VideoTrack?` return.
  lk.VideoTrack? _cameraTrack() {
    final local = widget.room.localParticipant;
    if (local != null && local.identity == widget.identity) {
      return _cameraTrackFrom(local.videoTrackPublications);
    }
    for (final p in widget.room.remoteParticipants.values) {
      if (p.identity != widget.identity) continue;
      return _cameraTrackFrom(p.videoTrackPublications);
    }
    return null;
  }

  static lk.VideoTrack? _cameraTrackFrom(
    List<lk.TrackPublication<lk.VideoTrack>> publications,
  ) {
    for (final pub in publications) {
      if (pub.source != lk.TrackSource.camera) continue;
      final track = pub.track;
      if (pub.subscribed && !pub.muted && track != null) return track;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final track = _cameraTrack();
    // Unlike a screen share, no placeholder text for a camera not here yet.
    if (track == null) return const SizedBox.shrink();
    return lk.VideoTrackRenderer(
      track,
      fit: lk.VideoViewFit.cover,
      mirrorMode: mirrorModeFor(isLocal: _isLocal, facing: widget.facing.value),
    );
  }
}
