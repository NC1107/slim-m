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
///
/// [_participant] checks the local participant too, not only remote ones: an
/// earlier version only ever found a remote share, so a lone caller who
/// started sharing saw the same nothing this whole widget exists to fix.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'first_frame_gate.dart';
import 'track_event_filter.dart';

/// Test-only build counter, keyed by identity; see the twin in
/// `camera_view.dart` for why a rebuild-scoping test needs it.
@visibleForTesting
final Map<String, int> debugScreenShareViewBuildCounts = {};

@visibleForTesting
void debugResetScreenShareViewBuildCounts() =>
    debugScreenShareViewBuildCounts.clear();

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
  lk.VideoTrack? _renderedTrack;
  OwnedVideoRenderer? _ownedRenderer;

  @override
  void initState() {
    super.initState();
    // Only this participant's own track changes can alter what we render; every other room event is noise.
    _cancel = widget.room.events.listen((event) {
      if (mounted && trackEventAffectsIdentity(event, widget.identity)) {
        _syncRenderer();
        setState(() {});
      }
    });
    _syncRenderer();
  }

  /// Swaps in a fresh [OwnedVideoRenderer] whenever the share track this
  /// tile renders changes, so a re-share after stopping gets its own
  /// first-frame warm-up rather than inheriting a stale renderer's
  /// already-latched [FirstFrameTracker].
  void _syncRenderer() {
    final track = _shareTrack();
    if (identical(track, _renderedTrack)) return;
    _renderedTrack = track;
    final stale = _ownedRenderer;
    _ownedRenderer = null;
    if (stale != null) unawaited(stale.dispose());
    if (track != null) unawaited(_attachRenderer(track));
  }

  Future<void> _attachRenderer(lk.VideoTrack track) async {
    final owned = OwnedVideoRenderer();
    await owned.initialize();
    if (!mounted || !identical(track, _renderedTrack)) {
      unawaited(owned.dispose());
      return;
    }
    setState(() => _ownedRenderer = owned);
  }

  @override
  void dispose() {
    _cancel?.call();
    final owned = _ownedRenderer;
    _ownedRenderer = null;
    if (owned != null) unawaited(owned.dispose());
    super.dispose();
  }

  /// Checked as two concretely-typed branches, not one lookup returning the
  /// abstract `Participant`: see `camera_view.dart`'s own copy of this note.
  lk.VideoTrack? _shareTrack() {
    final local = widget.room.localParticipant;
    if (local != null && local.identity == widget.identity) {
      return _shareTrackFrom(local.videoTrackPublications);
    }
    for (final p in widget.room.remoteParticipants.values) {
      if (p.identity != widget.identity) continue;
      return _shareTrackFrom(p.videoTrackPublications);
    }
    return null;
  }

  static lk.VideoTrack? _shareTrackFrom(
    List<lk.TrackPublication<lk.VideoTrack>> publications,
  ) {
    for (final pub in publications) {
      if (pub.source != lk.TrackSource.screenShareVideo) continue;
      final track = pub.track;
      if (pub.subscribed && !pub.muted && track != null) return track;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    assert(() {
      debugScreenShareViewBuildCounts[widget.identity] =
          (debugScreenShareViewBuildCounts[widget.identity] ?? 0) + 1;
      return true;
    }());
    final track = _shareTrack();
    // Honest about the beat between "sharing" and the track arriving.
    if (track == null) return _waitingForScreen;
    // And the further beat between the track arriving and a real frame.
    final owned = _ownedRenderer;
    if (owned == null) return _waitingForScreen;
    return FirstFrameReveal(
      tracker: owned.tracker,
      placeholder: _waitingForScreen,
      child: lk.VideoTrackRenderer(
        track,
        fit: lk.VideoViewFit.contain,
        cachedRenderer: owned.renderer,
        autoDisposeRenderer: false,
      ),
    );
  }

  static const _waitingForScreen = Center(
    child: Text(
      'Waiting for the shared screen...',
      style: TextStyle(color: Color(0xFF9AA4AD), fontSize: 13),
    ),
  );
}
