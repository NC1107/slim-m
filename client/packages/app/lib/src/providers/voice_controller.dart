// SPDX-License-Identifier: Apache-2.0
/// Drives the one voice call this client can be in.
///
/// One call at a time, deliberately. Joining a second channel leaves the first
/// rather than holding two open microphones, which is what a user means by
/// "join" and is also the only behaviour the call controls can describe.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_rtc/rtc.dart';

import 'providers.dart';

/// Everything a voice surface needs to render, in one value.
class VoiceState {
  const VoiceState({
    this.channelId,
    this.state = VoiceSessionState.idle,
    this.participants = const [],
    this.microphoneEnabled = true,
    this.screenSharing = false,
    this.canPublish = true,
    this.deafened = false,
    this.error,
    this.retryable = true,
  });

  /// The channel this call belongs to, so a screen can tell "in a call here"
  /// from "in a call somewhere else".
  final String? channelId;
  final VoiceSessionState state;
  final List<VoiceParticipant> participants;

  /// What the user has asked for, which is not always what they got: a token
  /// without SPEAK cannot open a microphone however the toggle is set.
  final bool microphoneEnabled;
  final bool screenSharing;

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

  VoiceState copyWith({
    String? channelId,
    VoiceSessionState? state,
    List<VoiceParticipant>? participants,
    bool? microphoneEnabled,
    bool? screenSharing,
    bool? canPublish,
    bool? deafened,
    String? error,
    bool clearError = false,
    bool? retryable,
  }) => VoiceState(
    channelId: channelId ?? this.channelId,
    state: state ?? this.state,
    participants: participants ?? this.participants,
    microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
    screenSharing: screenSharing ?? this.screenSharing,
    canPublish: canPublish ?? this.canPublish,
    deafened: deafened ?? this.deafened,
    error: clearError ? null : (error ?? this.error),
    retryable: clearError ? true : (retryable ?? this.retryable),
  );
}

class VoiceController extends StateNotifier<VoiceState> {
  VoiceController(this._ref, {VoiceSession? session})
    : _session = session ?? VoiceSession(),
      super(const VoiceState()) {
    _states = _session.states.listen((s) {
      state = state.copyWith(state: s);
    });
    _participants = _session.participantChanges.listen((p) {
      state = state.copyWith(
        participants: p,
        // Trust the session's view of the local participant over the local
        // toggle: the SFU is what actually decides whether a track is live.
        screenSharing: p.any((x) => x.isLocal && x.isScreenSharing),
      );
    });
  }

  final Ref _ref;
  final VoiceSession _session;
  late final StreamSubscription<VoiceSessionState> _states;
  late final StreamSubscription<List<VoiceParticipant>> _participants;

  /// Sets the microphone preference before joining. Has no effect on a live
  /// call; use [toggleMicrophone] for that.
  void setMicrophonePreference(bool enabled) {
    state = state.copyWith(microphoneEnabled: enabled);
  }

  Future<void> join(String channelId) async {
    state = state.copyWith(channelId: channelId, clearError: true);
    try {
      final token = await _ref.read(apiProvider).voiceToken(channelId);
      state = state.copyWith(canPublish: token.canPublish);
      await _session.join(
        url: token.url,
        token: token.token,
        // Asking for a microphone a token cannot publish just produces a
        // failure to report; not asking is the honest thing.
        microphoneEnabled: state.microphoneEnabled && token.canPublish,
      );
      if (_session.state == VoiceSessionState.failed) {
        state = state.copyWith(
          error: 'Could not connect to the call. ${_session.lastError ?? ''}'
              .trim(),
        );
      }
    } on api.NotConfiguredException {
      state = state.copyWith(
        state: VoiceSessionState.failed,
        error: 'This server has no voice configured.',
        retryable: false,
      );
    } on api.ForbiddenException {
      state = state.copyWith(
        state: VoiceSessionState.failed,
        error: 'You do not have permission to join this channel.',
        retryable: false,
      );
    } on api.ApiException catch (e) {
      state = state.copyWith(
        state: VoiceSessionState.failed,
        error: e.message,
        retryable: true,
      );
    }
  }

  Future<void> leave() async {
    await _session.leave();
    state = const VoiceState();
  }

  Future<void> toggleMicrophone() async {
    final want = !state.microphoneEnabled;
    final got = await _session.setMicrophoneEnabled(want);
    // Reflects what happened rather than what was asked for, so the button
    // never claims a microphone is open when the SFU refused the track.
    state = state.copyWith(
      microphoneEnabled: got ? want : state.microphoneEnabled,
      error: got
          ? null
          : 'Could not ${want ? 'unmute' : 'mute'} the microphone.',
      clearError: got,
    );
  }

  /// Toggles local playback of everyone else's audio. Never touches this
  /// session's own microphone: deafening and muting are independent, exactly
  /// as they are for every other voice product this design is drawn from.
  Future<void> toggleDeafen() async {
    final want = !state.deafened;
    final got = await _session.setDeafened(want);
    state = state.copyWith(
      deafened: got ? want : state.deafened,
      error: got ? null : 'Could not ${want ? 'deafen' : 'undeafen'}.',
      clearError: got,
    );
  }

  Future<void> setScreenShare(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
  }) async {
    final got = await _session.setScreenShareEnabled(enabled, quality: quality);
    state = state.copyWith(
      screenSharing: got,
      error: enabled && !got
          ? 'Could not start sharing. The desktop may have refused the capture.'
          : null,
      clearError: !(enabled && !got),
    );
  }

  @override
  void dispose() {
    unawaited(_states.cancel());
    unawaited(_participants.cancel());
    unawaited(_session.dispose());
    super.dispose();
  }
}

final voiceControllerProvider =
    StateNotifierProvider<VoiceController, VoiceState>(
      (ref) => VoiceController(ref),
    );
