// SPDX-License-Identifier: Apache-2.0
part of 'voice_session.dart';

/// The private half of viewport-driven video culling: turning the live room
/// into the LiveKit-free records [VideoSubscriptionCuller] reasons over, and
/// handing them to it.
///
/// Split out for [VoiceSession]'s own 500-line hard ceiling, the same reason
/// `voice_session_tracks.dart` exists, and everything here is private for
/// the same reason too - the one public method this feature adds
/// ([VoiceSession.setVideoInterest]) stays declared on the class itself, so
/// every `implements VoiceSession` fake in the test tree is a compile error
/// until it grows the method rather than silently missing it.
extension VoiceSessionVideo on VoiceSession {
  /// Every remote video publication in the room, keyed the way the canvas's
  /// own `presenceTileKeys` keys a tile.
  ///
  /// Walks `videoTrackPublications` only. An audio publication is never
  /// reachable from here by construction, which is the first of the two
  /// independent guarantees that a cull can never silence anybody; the
  /// second is [VideoSubscriptionCuller]'s own refusal to act on a key whose
  /// kind is not in `cullableTrackKinds`.
  ///
  /// A source LiveKit does not classify as a camera or a screen share (its
  /// own `unknown`, which a publication carries before its metadata lands)
  /// is skipped rather than guessed at: a track nothing on the canvas has a
  /// tile for is a track no interest set could ever name, so culling it
  /// would be culling on absence of evidence.
  Iterable<VideoSubscriptionRef> _videoSubscriptionRefs(lk.Room room) sync* {
    for (final participant in room.remoteParticipants.values) {
      final identity = participant.identity;
      for (final pub in participant.videoTrackPublications) {
        final screenShare = switch (pub.source) {
          lk.TrackSource.camera => false,
          lk.TrackSource.screenShareVideo => true,
          _ => null,
        };
        if (screenShare == null) continue;
        yield (
          key: videoSubscriptionKey(
            identity: identity,
            screenShare: screenShare,
          ),
          subscribed: pub.subscribed,
          subscribe: pub.subscribe,
          unsubscribe: pub.unsubscribe,
        );
      }
    }
  }

  /// Reconciles the room's remote video against whatever the last
  /// [VoiceSession.setVideoInterest] declared. Cheap enough to run on every
  /// room event, which is what it does: a publication's subscription state
  /// changes without the roster changing, so this cannot ride behind
  /// [VoiceSession._refreshParticipants]' own unchanged-roster early return.
  void _applyVideoInterest() {
    final room = _room;
    if (room == null || _disposed) return;
    _videoCuller.apply(_videoSubscriptionRefs(room));
  }
}
