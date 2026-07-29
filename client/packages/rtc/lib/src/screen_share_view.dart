// SPDX-License-Identifier: Apache-2.0
/// Renders one participant's shared screen.
///
/// Not exported from the package barrel on purpose: it takes LiveKit types,
/// and the seam this package exists for is that nothing outside it does. The
/// app reaches it through `VoiceSession.screenShareViewFor`, which returns it
/// as a plain [Widget].
///
/// Why this exists at all: publishing a share and *seeing* one are separate
/// halves, and only the first was built. A peer's share reached the client as
/// a subscribed track (the e2e run proves that at the SFU) and then nothing
/// anywhere rendered it - the viewer saw a glyph on a roster row and no
/// screen. This is the missing half.
library;

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// One participant's screen share video, tracking the room live.
///
/// Listens to the room's own event stream rather than trusting the state at
/// build time, because the track routinely arrives *after* the roster learns
/// the participant is sharing: subscription lags the boolean by a beat, and a
/// widget built in that beat would show the placeholder forever.
class ScreenShareView extends StatefulWidget {
  const ScreenShareView({
    super.key,
    required this.room,
    required this.identity,
  });

  final lk.Room room;

  /// Whose share to render, by server user id.
  final String identity;

  @override
  State<ScreenShareView> createState() => _ScreenShareViewState();
}

class _ScreenShareViewState extends State<ScreenShareView> {
  lk.CancelListenFunc? _cancel;

  @override
  void initState() {
    super.initState();
    // Any room event can change track availability; a rebuild is cheap next to decoding video.
    _cancel = widget.room.events.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _cancel?.call();
    super.dispose();
  }

  lk.VideoTrack? _shareTrack() {
    final participants = widget.room.remoteParticipants.values;
    for (final p in participants) {
      if (p.identity != widget.identity) continue;
      for (final pub in p.videoTrackPublications) {
        if (pub.source != lk.TrackSource.screenShareVideo) continue;
        final track = pub.track;
        if (pub.subscribed && !pub.muted && track != null) return track;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final track = _shareTrack();
    if (track == null) {
      // Honest about the beat between "sharing" and the track arriving.
      return const Center(
        child: Text(
          'Waiting for the shared screen...',
          style: TextStyle(color: Color(0xFF9AA4AD), fontSize: 13),
        ),
      );
    }
    return lk.VideoTrackRenderer(
      track,
      fit: lk.VideoViewFit.contain,
    );
  }
}
