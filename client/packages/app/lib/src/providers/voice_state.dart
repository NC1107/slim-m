// SPDX-License-Identifier: Apache-2.0
/// Everything a voice surface needs to render, in one value.
///
/// Split out of `voice_controller.dart`, which sat at this repo's 500-line
/// hard ceiling before the camera-refusal diagnostics grew it past it.
library;

import 'package:slimm_rtc/rtc.dart';

class VoiceState {
  const VoiceState({
    this.channelId,
    this.state = VoiceSessionState.idle,
    this.joining = false,
    this.participants = const [],
    this.microphoneEnabled = true,
    this.cameraEnabled = false,
    this.screenSharing = false,
    this.awaitingBroadcast = false,
    this.canPublish = true,
    this.deafened = false,
    this.error,
    this.retryable = true,
    this.connectedAt,
  });

  /// The channel this call belongs to, so a screen can tell "in a call here"
  /// from "in a call somewhere else".
  final String? channelId;
  final VoiceSessionState state;
  final List<VoiceParticipant> participants;

  /// True for the whole span of a [VoiceController.join] call, set before
  /// its first `await` and cleared in a `finally`. [state] does not reach
  /// [VoiceSessionState.connecting] until the token round trip already
  /// answered, so this is what tells a screen arriving elsewhere that a
  /// join is under way during that gap; see `voice_screen.dart`'s `_busyElsewhere`.
  final bool joining;

  /// What the user has asked for, which is not always what they got: a token
  /// without SPEAK cannot open a microphone however the toggle is set.
  final bool microphoneEnabled;

  /// What the user has asked for, the same double duty [microphoneEnabled]
  /// carries: a pre-toggle before `VoiceController.join`, and the live truth
  /// once in a call, kept in step by `VoiceController`'s participant listener.
  final bool cameraEnabled;
  final bool screenSharing;

  /// iOS only: sharing has been asked for and the system is waiting on the
  /// user to start a broadcast. Nobody can see a screen yet, so this is
  /// deliberately not [screenSharing]; showing it as sharing is the exact
  /// lie this field exists to stop.
  final bool awaitingBroadcast;

  /// Whether the token allows publishing at all, mirroring the SPEAK grant.
  final bool canPublish;

  /// Whether every other participant's audio is locally silenced. Purely
  /// local: it never touches this session's own microphone, so it carries
  /// no [canPublish]-style server permission to check.
  final bool deafened;

  final String? error;

  /// False for a failure this channel cannot retry its way out of: no voice
  /// configured, or no permission. True (the default) is everything
  /// transient, where trying again might really work.
  final bool retryable;

  /// When this call connected, for the in-call duration readout. Null
  /// whenever not connected; survives reconnect-free state churn but resets
  /// with the call.
  final DateTime? connectedAt;

  VoiceState copyWith({
    String? channelId,
    VoiceSessionState? state,
    bool? joining,
    List<VoiceParticipant>? participants,
    bool? microphoneEnabled,
    bool? cameraEnabled,
    bool? screenSharing,
    bool? awaitingBroadcast,
    bool? canPublish,
    bool? deafened,
    String? error,
    bool clearError = false,
    bool? retryable,
    DateTime? connectedAt,
    bool clearConnectedAt = false,
  }) => VoiceState(
    channelId: channelId ?? this.channelId,
    state: state ?? this.state,
    joining: joining ?? this.joining,
    participants: participants ?? this.participants,
    microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
    cameraEnabled: cameraEnabled ?? this.cameraEnabled,
    screenSharing: screenSharing ?? this.screenSharing,
    awaitingBroadcast: awaitingBroadcast ?? this.awaitingBroadcast,
    canPublish: canPublish ?? this.canPublish,
    deafened: deafened ?? this.deafened,
    error: clearError ? null : (error ?? this.error),
    retryable: clearError ? true : (retryable ?? this.retryable),
    connectedAt: clearConnectedAt ? null : (connectedAt ?? this.connectedAt),
  );
}
