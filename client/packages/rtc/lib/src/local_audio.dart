// SPDX-License-Identifier: Apache-2.0
/// What one listener has done about what reaches their own ears.
///
/// Three axes that all end in the same place, so they live together rather
/// than as three fields on the session: deafen everyone, silence one person,
/// and turn one person up or down. Split out of `voice_session.dart` when the
/// third took that file past the 500-line ceiling.
///
/// **All of it is local and none of it is announced.** The SFU is never told,
/// so somebody who has been muted or turned down cannot learn that they were
/// - the same reason blocking is silent. Anything room-visible (a moderator's
/// timeout, a kick) is a server call, not this.
///
/// **It is applied by reapplication, not by event.** [applyTo] runs on every
/// room event rather than only when a control moves, which is what keeps a
/// participant who joins mid-call, or whose track resubscribes after a
/// network blip, in the state this listener chose. Gain needs that more than
/// muting does: it lives on the platform track object, so a resubscribed
/// track arrives back at full volume with nothing to say so.
///
/// **What it does not do is push a value a track already has.** The caller
/// fires this from a catch-all room-event listener, and one of those events
/// is `ActiveSpeakersChanged`, which arrives several times a second for as
/// long as anybody is talking. Every push is a real platform round trip -
/// flutter_webrtc's `enabled` setter invokes `mediaStreamTrackSetEnable`
/// with no equality check of its own, and for an audio track it also fires
/// that track's `onMute`/`onUnMute` - so reapplying unconditionally spends a
/// method channel per remote track per event to set values that are already
/// set. [_applied] remembers what was last pushed and skips the rest.
///
/// That cache is keyed on the platform track object, never on a track or
/// publication id, and the difference is the whole reason the reapplication
/// invariant above still holds. A resubscribe reuses the publication and its
/// sid, so an id-keyed cache would report a hit and skip the reapplication
/// that exists precisely to catch it. It does not reuse the objects:
/// `addSubscribedMediaTrack` builds a new `RemoteAudioTrack` around the new
/// `MediaStreamTrack` the peer connection just handed it, so a resubscribed
/// track misses this cache and is reapplied, which is the point.
library;

import 'package:livekit_client/livekit_client.dart' as lk;

import 'audio_gain.dart';

/// One subscribed remote audio track, described with no LiveKit type in
/// sight.
///
/// Plain closures on a record, the shape [VideoSubscriptionCuller] and
/// [ScreenShareControl] already use and for the same reason: what is worth
/// testing here is which calls are made and which are skipped, and a test
/// that needs a signalling server to find that out is a test nobody writes.
///
/// [track] is the identity the skip-cache is keyed on. It must be the object
/// whose state these closures actually set, so that the object being
/// replaced is what invalidates the entry.
typedef LocalAudioRef = ({
  String identity,
  Object track,
  Future<void> Function() enable,
  Future<void> Function() disable,
  Future<Object?> Function(double volume) setVolume,
});

/// What was last successfully pushed to one platform track.
class _AppliedAudio {
  const _AppliedAudio({required this.silenced, required this.volume});

  final bool silenced;
  final double volume;
}

class LocalAudioState {
  /// Silences every remote participant.
  bool deafened = false;

  /// Identities silenced individually.
  final Set<String> muted = {};

  /// Per-identity gain, absent meaning [kDefaultParticipantVolume].
  ///
  /// Deliberately not carried on the participant value type: that list is
  /// compared by value to decide whether to push a new roster to every
  /// listener, so a gain field would turn each pixel of a slider drag into a
  /// full roster rebuild.
  final Map<String, double> volumes = {};

  double volumeFor(String identity) =>
      volumes[identity] ?? kDefaultParticipantVolume;

  void setVolumeFor(String identity, double volume) {
    volumes[identity] = clampParticipantVolume(volume);
  }

  void setMuted(String identity, bool value) {
    value ? muted.add(identity) : muted.remove(identity);
  }

  bool isMuted(String identity) => muted.contains(identity);

  /// Applies all three to every remote audio track currently subscribed,
  /// returning the last failure or null.
  ///
  /// Failures are returned rather than thrown because the caller fires this
  /// without awaiting from a room-event handler, where a throw would become
  /// an unhandled zone error instead of something anybody could act on.
  ///
  /// Disabling the media track rather than unsubscribing is deliberate: a
  /// publication's own `disable()` drops the SFU subscription and needs
  /// renegotiation before sound comes back, while the track's `enabled` flag
  /// is local, instant, and instantly reversible.
  Future<Object?> applyTo(lk.Room room) => applyToRefs(refsOf(room));

  /// Every subscribed remote audio track in [room], as [LocalAudioRef]s.
  Iterable<LocalAudioRef> refsOf(lk.Room room) sync* {
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.audioTrackPublications) {
        final track = publication.track;
        if (track == null) continue;
        yield (
          identity: participant.identity,
          track: track.mediaStreamTrack,
          enable: track.enable,
          disable: track.disable,
          setVolume: (volume) => applyParticipantVolume(track, volume),
        );
      }
    }
  }

  /// The half of [applyTo] worth testing, over an explicit track list.
  Future<Object?> applyToRefs(Iterable<LocalAudioRef> refs) async {
    Object? failure;
    for (final ref in refs) {
      // Deafened silences everyone; otherwise only the individually muted.
      final silence = deafened || muted.contains(ref.identity);
      final volume = volumeFor(ref.identity);
      if (_isAlreadyApplied(ref.track, silence: silence, volume: volume)) {
        continue;
      }

      Object? here;
      try {
        await (silence ? ref.disable() : ref.enable());
      } catch (e) {
        here = e;
      }
      if (!silence) {
        // After the enable, never before: re-enabling can reset source volume.
        here = await ref.setVolume(volume) ?? here;
      }

      // Only a clean push is remembered, so a failure still retries next event.
      _applied[ref.track] = here == null
          ? _AppliedAudio(silenced: silence, volume: volume)
          : null;
      failure = here ?? failure;
    }
    return failure;
  }

  /// Whether this track already carries this state, so nothing need be sent.
  ///
  /// Volume is compared only between two unsilenced states, because volume is
  /// not pushed while silenced: comparing it there would make a slider moved
  /// during a mute re-send a `disable` the track is already holding.
  bool _isAlreadyApplied(
    Object track, {
    required bool silence,
    required double volume,
  }) {
    final last = _applied[track];
    if (last == null) return false;
    if (last.silenced || silence) return last.silenced && silence;
    return last.volume == volume;
  }

  /// Weakly keyed, so remembering a track never keeps a finished call's
  /// platform objects alive.
  final Expando<_AppliedAudio> _applied = Expando('local audio last applied');
}
