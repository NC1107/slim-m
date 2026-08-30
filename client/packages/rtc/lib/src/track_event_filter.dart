// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Which room events can change what one participant's video tile shows.
///
/// `CameraView` and `ScreenShareView` each render a single participant's video
/// and used to rebuild on *every* `Room` event. LiveKit emits many per second
/// that touch nobody's tracks - `ActiveSpeakersChanged` fires continuously for
/// as long as anyone is talking, alongside connection-quality, data, and
/// transcription events - so a tile-per-participant call spent tile-count-many
/// full rebuilds a second for no visual change.
///
/// This narrows a rebuild to the events that can actually change the
/// participant's video: a track published, unpublished, subscribed,
/// unsubscribed, muted, or unmuted, or the participant themselves joining or
/// leaving. The last two are included on their own merit as much as for the
/// filter: a tile must clear when its participant leaves rather than depend on
/// a track-unsubscribe event arriving first.
library;

import 'package:livekit_client/livekit_client.dart' as lk;

/// Whether [event] can change the video shown for the participant [identity],
/// and so warrants rebuilding that participant's tile.
bool trackEventAffectsIdentity(lk.RoomEvent event, String identity) {
  final lk.Participant? participant = switch (event) {
    lk.TrackPublishedEvent(:final participant) => participant,
    lk.TrackUnpublishedEvent(:final participant) => participant,
    lk.LocalTrackPublishedEvent(:final participant) => participant,
    lk.LocalTrackUnpublishedEvent(:final participant) => participant,
    lk.TrackSubscribedEvent(:final participant) => participant,
    lk.TrackUnsubscribedEvent(:final participant) => participant,
    lk.TrackMutedEvent(:final participant) => participant,
    lk.TrackUnmutedEvent(:final participant) => participant,
    lk.ParticipantConnectedEvent(:final participant) => participant,
    lk.ParticipantDisconnectedEvent(:final participant) => participant,
    _ => null,
  };
  return participant != null && participant.identity == identity;
}
