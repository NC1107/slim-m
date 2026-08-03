// SPDX-License-Identifier: Apache-2.0
/// Reading a room's participants into plain [VoiceParticipant] values, split
/// out of `voice_session.dart` to make room there under this repo's file
/// budget.
library;

import 'package:livekit_client/livekit_client.dart' as lk;

import 'voice_models.dart';

/// Every participant currently in [room], local first.
List<VoiceParticipant> snapshotParticipants(lk.Room room) {
  final next = <VoiceParticipant>[];
  final local = room.localParticipant;
  if (local != null) next.add(_toParticipant(local, isLocal: true));
  for (final remote in room.remoteParticipants.values) {
    next.add(_toParticipant(remote, isLocal: false));
  }
  return next;
}

VoiceParticipant _toParticipant(lk.Participant p, {required bool isLocal}) {
  final audio = p.audioTrackPublications;
  final muted = audio.isEmpty || audio.every((t) => t.muted);
  return VoiceParticipant(
    identity: p.identity,
    // A participant with an empty name still gets a row, keyed by identity.
    name: p.name.isEmpty ? p.identity : p.name,
    isSpeaking: p.isSpeaking,
    isMuted: muted,
    isLocal: isLocal,
    isScreenSharing: isSharingScreen(p),
    isCameraOn: hasCameraTrack(p),
  );
}

/// A published screen track is the only thing that means anybody can see a
/// screen, so it is what both the roster and a share outcome read.
bool isSharingScreen(lk.Participant? p) =>
    p?.videoTrackPublications
        .any((t) => t.source == lk.TrackSource.screenShareVideo) ??
    false;

/// Whether a camera track is published, the same track-presence check
/// [isSharingScreen] uses for a screen share.
bool hasCameraTrack(lk.Participant? p) =>
    p?.videoTrackPublications.any((t) => t.source == lk.TrackSource.camera) ??
    false;
