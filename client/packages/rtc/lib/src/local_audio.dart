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
library;

import 'package:livekit_client/livekit_client.dart' as lk;

import 'audio_gain.dart';

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
  Future<Object?> applyTo(lk.Room room) async {
    Object? failure;
    for (final participant in room.remoteParticipants.values) {
      // Deafened silences everyone; otherwise only the individually muted.
      final silence = deafened || muted.contains(participant.identity);
      for (final publication in participant.audioTrackPublications) {
        final track = publication.track;
        if (track == null) continue;
        try {
          if (silence) {
            await track.disable();
          } else {
            await track.enable();
          }
        } catch (e) {
          failure = e;
        }
        if (silence) continue;
        // After the enable, never before: re-enabling can reset source volume.
        failure = await applyParticipantVolume(
              track,
              volumeFor(participant.identity),
            ) ??
            failure;
      }
    }
    return failure;
  }
}
