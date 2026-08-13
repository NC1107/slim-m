// SPDX-License-Identifier: Apache-2.0
/// Reading a room's participants into plain [VoiceParticipant] values, split
/// out of `voice_session.dart` to make room there under this repo's file
/// budget.
library;

import 'package:livekit_client/livekit_client.dart' as lk;

import 'voice_models.dart';

/// Every participant currently in [room], local first. [speakingSensitivity]
/// is [VoiceSession]'s own threshold (0 strictest, 1 loosest); the default
/// matches this function's behaviour before that setting existed.
List<VoiceParticipant> snapshotParticipants(
  lk.Room room, {
  double speakingSensitivity = 1.0,
}) {
  final next = <VoiceParticipant>[];
  final local = room.localParticipant;
  if (local != null) {
    next.add(
      _toParticipant(local, isLocal: true, sensitivity: speakingSensitivity),
    );
  }
  for (final remote in room.remoteParticipants.values) {
    next.add(
      _toParticipant(remote, isLocal: false, sensitivity: speakingSensitivity),
    );
  }
  return next;
}

VoiceParticipant _toParticipant(
  lk.Participant p, {
  required bool isLocal,
  required double sensitivity,
}) {
  final audio = p.audioTrackPublications;
  final muted = audio.isEmpty || audio.every((t) => t.muted);
  return VoiceParticipant(
    identity: p.identity,
    // A participant with an empty name still gets a row, keyed by identity.
    name: p.name.isEmpty ? p.identity : p.name,
    isSpeaking:
        passesActivationThreshold(p.isSpeaking, p.audioLevel, sensitivity),
    isMuted: muted,
    isLocal: isLocal,
    isScreenSharing: isSharingScreen(p),
    isCameraOn: hasCameraTrack(p),
  );
}

/// Whether [reported] and [level] together clear [sensitivity]'s floor.
///
/// AND, never OR: this can only narrow what the SFU's own voice-activity
/// detector already decided was speech, never invent speech it did not
/// report - the pinned `livekit_client` 2.10.0 source exposes no adjustable
/// threshold of its own for either field, only on/off capture toggles, so a
/// local floor over the reported [level] (0-1, 1 loudest) is the one knob
/// genuinely available. [sensitivity] 0 is strictest, 1 (the default,
/// matching behaviour before this setting existed) passes any level at all.
bool passesActivationThreshold(
  bool reported,
  double level,
  double sensitivity,
) =>
    reported && level >= (1 - sensitivity.clamp(0.0, 1.0));

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
