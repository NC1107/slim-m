// SPDX-License-Identifier: Apache-2.0
/// Drives the one voice call this client can be in.
///
/// One call at a time, deliberately. Joining a second channel leaves the first
/// rather than holding two open microphones, which is what a user means by
/// "join" and is also the only behaviour the call controls can describe.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

import '../api_failure.dart';
import '../diagnostics/debug_log.dart';
import 'providers.dart';
import 'voice_call_heartbeat.dart';
import 'voice_call_lifecycle_report.dart';
import 'voice_sfu_security.dart';

/// Everything a voice surface needs to render, in one value.
class VoiceState {
  const VoiceState({
    this.channelId,
    this.state = VoiceSessionState.idle,
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

  /// What the user has asked for, which is not always what they got: a token
  /// without SPEAK cannot open a microphone however the toggle is set.
  final bool microphoneEnabled;

  /// What the user has asked for, the same double duty [microphoneEnabled]
  /// carries: a pre-toggle before [VoiceController.join], and the live truth
  /// once in a call, kept in step by [VoiceController]'s participant listener.
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

class VoiceController extends StateNotifier<VoiceState> {
  VoiceController(
    this._ref, {
    VoiceSession? session,
    CallLifecycleChannel? callLifecycle,
    this.broadcastStartTimeout = const Duration(seconds: 30),
    Duration voiceHeartbeatInterval = const Duration(seconds: 15),
  }) : _session = session ?? VoiceSession(),
       _callLifecycle = callLifecycle ?? CallLifecycleChannel(),
       _heartbeat = VoiceCallHeartbeat(_ref, interval: voiceHeartbeatInterval),
       super(const VoiceState()) {
    _endCallRequests = _callLifecycle.endCallRequests.listen((_) {
      unawaited(leave());
    });
    _states = _session.states.listen((s) {
      reportCallLifecycle(_callLifecycle, s, channelId: state.channelId);
      // A drop the SFU decided on: the reason is the only thing that can tell
      // "you joined elsewhere" from "your network went".
      final dropped = _session.lastDisconnect;
      if (s == VoiceSessionState.failed && dropped != null) {
        _heartbeat.stop();
        _log('Call ended: ${dropped.name}', detail: dropped.message);
        state = state.copyWith(
          state: s,
          error: dropped.message,
          clearConnectedAt: true,
        );
        return;
      }
      switch (s) {
        case VoiceSessionState.connected:
          // Not gated on lifecycle: only termination may let this lapse.
          _heartbeat.start(state.channelId);
        case VoiceSessionState.idle:
        case VoiceSessionState.failed:
          _heartbeat.stop();
        default:
          break;
      }
      // The duration clock starts at the connected transition and only there,
      // so participant churn does not restart it.
      state = switch (s) {
        VoiceSessionState.connected when state.connectedAt == null =>
          state.copyWith(state: s, connectedAt: DateTime.now()),
        VoiceSessionState.idle || VoiceSessionState.failed => state.copyWith(
          state: s,
          clearConnectedAt: true,
        ),
        _ => state.copyWith(state: s),
      };
    });
    _participants = _session.participantChanges.listen((p) {
      // Trust the session's view of the local participant over the local
      // toggle: the SFU is what actually decides whether a track is live.
      final sharing = p.any((x) => x.isLocal && x.isScreenSharing);
      final camera = p.any((x) => x.isLocal && x.isCameraOn);
      if (sharing) _cancelBroadcastDeadline();
      state = state.copyWith(
        participants: p,
        screenSharing: sharing,
        cameraEnabled: camera,
        awaitingBroadcast: sharing ? false : state.awaitingBroadcast,
      );
    });
  }

  /// How long to wait for iOS to actually start a broadcast before saying so.
  /// Long enough for the picker, its confirmation and a three second
  /// countdown; short enough that a build with no extension is not a mystery.
  final Duration broadcastStartTimeout;

  final Ref _ref;
  final VoiceSession _session;
  final CallLifecycleChannel _callLifecycle;
  final VoiceCallHeartbeat _heartbeat;
  late final StreamSubscription<VoiceSessionState> _states;
  late final StreamSubscription<List<VoiceParticipant>> _participants;
  late final StreamSubscription<void> _endCallRequests;
  Timer? _broadcastDeadline;

  /// Sets the microphone preference before joining. Has no effect on a live
  /// call; use [toggleMicrophone] for that.
  void setMicrophonePreference(bool enabled) {
    state = state.copyWith(microphoneEnabled: enabled);
  }

  /// Sets the camera preference before joining, applied once on the next
  /// [join] exactly the way [setMicrophonePreference] is; use [toggleCamera]
  /// for the live in-call control.
  void setCameraPreference(bool enabled) {
    state = state.copyWith(cameraEnabled: enabled);
  }

  Future<void> join(String channelId) async {
    state = state.copyWith(channelId: channelId, clearError: true);
    try {
      final token = await _ref.read(apiProvider).voiceToken(channelId);
      final insecureReason = insecureSfuReason(token.url);
      if (insecureReason != null) {
        state = state.copyWith(
          state: VoiceSessionState.failed,
          error: insecureReason,
          retryable: false,
        );
        return;
      }
      state = state.copyWith(canPublish: token.canPublish);
      await _session.join(
        url: token.url,
        token: token.token,
        // Asking for a microphone or camera a token cannot publish just
        // produces a failure to report; not asking is the honest thing.
        microphoneEnabled: state.microphoneEnabled && token.canPublish,
        cameraEnabled: state.cameraEnabled && token.canPublish,
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
        error: 'This Space has no voice configured.',
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
        error: describeApiFailure('join the call', e),
        retryable: true,
      );
    } catch (e) {
      // Joining is automatic now, so nothing asks first; an exception no other clause names must still fail cleanly.
      _log('Join failed with an unexpected error', detail: e);
      state = state.copyWith(
        state: VoiceSessionState.failed,
        error: 'Could not join the call.',
        retryable: true,
      );
    }
  }

  Future<void> leave() async {
    _cancelBroadcastDeadline();
    final channelId = state.channelId;
    _heartbeat.stop();
    await _session.leave();
    // Best-effort and fire-and-forget: this client already disconnected.
    if (channelId != null) unawaited(_heartbeat.forget(channelId));
    // The mic/camera preference survives the reset: there is no lobby left to re-set them on.
    state = VoiceState(
      microphoneEnabled: state.microphoneEnabled,
      cameraEnabled: state.cameraEnabled,
    );
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

  /// Enables or disables the local camera mid-call, [toggleMicrophone]'s
  /// exact counterpart. The participant listener above corrects this from
  /// the session's own truth regardless, so a refusal here still repaints
  /// as off rather than lying that the toggle worked.
  Future<void> toggleCamera() async {
    final want = !state.cameraEnabled;
    final got = await _session.setCameraEnabled(want);
    state = state.copyWith(
      cameraEnabled: got ? want : state.cameraEnabled,
      error: got ? null : 'Could not turn the camera ${want ? 'on' : 'off'}.',
      clearError: got,
    );
  }

  /// Whether [identity] is silenced for this listener alone; see
  /// [VoiceSession.setLocallyMuted].
  bool isLocallyMuted(String identity) => _session.isLocallyMuted(identity);

  /// Silences (or restores) one participant locally. Rebuilds the state so a
  /// popover reading [isLocallyMuted] repaints with the new label.
  Future<void> setLocallyMuted(String identity, bool muted) async {
    await _session.setLocallyMuted(identity, muted);
    state = state.copyWith(participants: _session.participants);
  }

  /// Whether this host can change one participant's volume at all. False on
  /// Linux, Windows and web, where the underlying call either throws or does
  /// nothing; see `audio_gain.dart` in the rtc package for why.
  bool get supportsParticipantVolume => _session.supportsParticipantVolume;

  /// [identity]'s playback gain for this listener, 1.0 being unchanged.
  double volumeFor(String identity) => _session.volumeFor(identity);

  /// Sets [identity]'s playback gain for this listener only.
  ///
  /// Deliberately does not rebuild the controller state: this is dragged, and
  /// republishing the roster on every frame of a drag is what makes the call
  /// screen jank. The slider owns its own value while it moves.
  Future<void> setVolumeFor(String identity, double volume) =>
      _session.setVolumeFor(identity, volume);

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

  /// Whether starting a share here needs a screen chosen first, and the
  /// screens to choose from. Enumerating is also what makes the capture that
  /// follows able to find anything, so it happens even for a single screen.
  bool get screenShareNeedsSource => _session.screenShareNeedsSource;

  Future<List<ScreenShareSource>> screenShareSources() =>
      _session.screenShareSources();

  /// The live view of [identity]'s shared screen; see
  /// [VoiceSession.screenShareViewFor].
  Widget screenShareViewFor(String identity) =>
      _session.screenShareViewFor(identity);

  /// The live view of [identity]'s camera feed; see
  /// [VoiceSession.cameraViewFor].
  Widget cameraViewFor(String identity) => _session.cameraViewFor(identity);

  /// Whether switching cameras is a bare flip (mobile) rather than a picker.
  bool get canFlipCamera => _session.canFlipCamera;

  /// Whether switching cameras needs one named first (desktop and web).
  bool get cameraNeedsSelection => _session.cameraNeedsSelection;

  /// The cameras available to pick from; see [VoiceSession.cameraDevices].
  Future<List<CameraDevice>> cameraDevices() => _session.cameraDevices();

  /// Flips the published camera between front and back, mobile only.
  Future<bool> flipCamera() async {
    final ok = await _session.flipCamera();
    state = state.copyWith(
      error: ok ? null : 'Could not switch the camera.',
      clearError: ok,
    );
    return ok;
  }

  /// Switches the published camera to [device], desktop's picker equivalent
  /// of [flipCamera].
  Future<bool> selectCameraDevice(CameraDevice device) async {
    final ok = await _session.selectCameraDevice(device);
    state = state.copyWith(
      error: ok ? null : 'Could not switch to that camera.',
      clearError: ok,
    );
    return ok;
  }

  Future<void> setScreenShare(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
    String? sourceId,
  }) async {
    _cancelBroadcastDeadline();
    final outcome = await _session.setScreenShareEnabled(
      enabled,
      quality: quality,
      sourceId: sourceId,
    );
    switch (outcome) {
      case ScreenShareOutcome.started:
        state = state.copyWith(screenSharing: true, clearError: true);
      case ScreenShareOutcome.stopped:
        state = state.copyWith(screenSharing: false, clearError: true);
      case ScreenShareOutcome.pendingBroadcast:
        state = state.copyWith(awaitingBroadcast: true, clearError: true);
        _broadcastDeadline = Timer(
          broadcastStartTimeout,
          _reportBroadcastNeverStarted,
        );
      case ScreenShareOutcome.unsupported:
        state = state.copyWith(
          screenSharing: false,
          awaitingBroadcast: false,
          error:
              'This build cannot share a screen: its screen recording '
              'extension is missing or not set up.',
          retryable: false,
        );
      case ScreenShareOutcome.failed:
        final cause = _session.lastError;
        _log(
          'Screen share ${enabled ? 'start' : 'stop'} failed',
          detail: cause,
        );
        state = state.copyWith(
          screenSharing: false,
          awaitingBroadcast: false,
          // The cause is included rather than dropped: "the system refused the
          // capture" alone sent a real Linux failure to a log nobody reads.
          error: enabled
              ? 'Could not start sharing. ${cause ?? 'The system refused the capture.'}'
              : 'Could not stop sharing. ${cause ?? ''}'.trim(),
        );
    }
  }

  void _log(String message, {Object? detail}) => _ref
      .read(debugLogProvider.notifier)
      .record('voice', message, detail: detail);

  /// The user was shown a broadcast picker and nothing came of it: they
  /// dismissed it, or there was nothing in it to pick. Either way the share
  /// is not happening, and saying nothing would leave the button pretending.
  void _reportBroadcastNeverStarted() {
    _broadcastDeadline = null;
    if (!state.awaitingBroadcast) return;
    state = state.copyWith(
      awaitingBroadcast: false,
      screenSharing: false,
      error:
          'Screen sharing never started. Tap share again and choose Start '
          'Broadcast. If nothing appeared to choose, this build has no screen '
          'recording extension.',
    );
  }

  void _cancelBroadcastDeadline() {
    _broadcastDeadline?.cancel();
    _broadcastDeadline = null;
  }

  @override
  void dispose() {
    _cancelBroadcastDeadline();
    _heartbeat.stop();
    unawaited(_states.cancel());
    unawaited(_participants.cancel());
    unawaited(_endCallRequests.cancel());
    unawaited(_session.dispose());
    _callLifecycle.dispose();
    super.dispose();
  }
}

final voiceControllerProvider =
    StateNotifierProvider<VoiceController, VoiceState>(
      (ref) => VoiceController(ref),
    );
