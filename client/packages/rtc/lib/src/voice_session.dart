// SPDX-License-Identifier: Apache-2.0
/// A live voice call, wrapped so nothing outside this package touches LiveKit.
///
/// The rest of the client never imports `livekit_client`. That is not tidiness:
/// a `Room` cannot be constructed in a widget test without a signalling server,
/// so anything that reaches for one directly becomes untestable, and the whole
/// voice surface would then only be exercisable by hand against a real SFU.
/// Everything here goes through [RoomFactory], so a test drives a session with
/// a fake and asserts on real behaviour.
///
/// The types this exposes are ours ([VoiceParticipant], [VoiceSessionState]),
/// so a LiveKit upgrade that renames one of its own is contained here.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'audio_gain.dart' as rtc_gain;
import 'local_audio.dart';

import 'broadcast_bridge.dart';
import 'camera_devices.dart';
import 'camera_switching.dart';
import 'camera_view.dart';
import 'desktop_sources.dart';
import 'screen_share.dart';
import 'screen_share_control.dart';
import 'screen_share_view.dart';
import 'voice_disconnect_reason.dart';
import 'voice_models.dart';
import 'voice_roster_snapshot.dart';

/// Builds the LiveKit room a session drives. The injection seam.
typedef RoomFactory = lk.Room Function();

/// A voice call in one channel.
///
/// Not a singleton and not global: one session is one call, and the caller owns
/// its lifetime. [dispose] must be called, and leaving is not the same as
/// disposing, because a user can leave and rejoin without the surrounding
/// screen being torn down.
class VoiceSession {
  VoiceSession({
    RoomFactory? roomFactory,
    BroadcastBridge? broadcast,
    DesktopSources? desktopSources,
    CameraDevices? cameraDevices,
  })  : _roomFactory = roomFactory ?? _defaultRoomFactory,
        _broadcast = broadcast ?? const MethodChannelBroadcastBridge(),
        _desktopSources = desktopSources ?? const WebrtcDesktopSources(),
        _cameraSwitching =
            CameraSwitching(cameraDevices ?? const HardwareCameraDevices()) {
    _screenShare = ScreenShareControl(_broadcast);
  }

  static lk.Room _defaultRoomFactory() => lk.Room(
        roomOptions: const lk.RoomOptions(
          // Only what is on screen is subscribed, at the size shown, so
          // several video tiles do not cost the same as all at full size.
          adaptiveStream: true,
          dynacast: true,
        ),
      );

  final RoomFactory _roomFactory;
  final BroadcastBridge _broadcast;
  final DesktopSources _desktopSources;
  final CameraSwitching _cameraSwitching;
  late final ScreenShareControl _screenShare;

  lk.Room? _room;
  // room.events.listen returns a cancel function rather than a
  // StreamSubscription, so this holds the canceller itself.
  lk.CancelListenFunc? _cancelEvents;

  final _stateController = StreamController<VoiceSessionState>.broadcast();
  final _participantsController =
      StreamController<List<VoiceParticipant>>.broadcast();

  VoiceSessionState _state = VoiceSessionState.idle;
  List<VoiceParticipant> _participants = const [];
  Object? _lastError;
  VoiceDisconnect? _lastDisconnect;
  bool _disposed = false;

  /// Deafen, per-participant mute and per-participant gain, which are one
  /// listener's own business and never reach the room; see [LocalAudioState].
  final LocalAudioState _audio = LocalAudioState();

  VoiceSessionState get state => _state;
  Stream<VoiceSessionState> get states => _stateController.stream;

  List<VoiceParticipant> get participants => _participants;
  Stream<List<VoiceParticipant>> get participantChanges =>
      _participantsController.stream;

  bool get deafened => _audio.deafened;

  /// Whether [identity] is silenced for this listener alone.
  bool isLocallyMuted(String identity) => _audio.isMuted(identity);

  /// Whether this host can change one participant's volume at all. See
  /// [supportsParticipantVolume]: on the platforms that answer false the call
  /// would either throw or quietly do nothing, so the control is not offered.
  bool get supportsParticipantVolume => rtc_gain.supportsParticipantVolume;

  /// [identity]'s playback gain for this listener, 1.0 being unchanged.
  double volumeFor(String identity) => _audio.volumeFor(identity);

  /// Sets [identity]'s playback gain for this listener only, clamped to the
  /// range the UI offers.
  ///
  /// Stored as well as applied, and reapplied from [_applyLocalAudioState] on
  /// every room event, because native gain lives on the platform track object
  /// and a track that resubscribes arrives as a new one at full volume. A
  /// setter that only touched currently-subscribed tracks would pass every
  /// test and quietly reset somebody whose network blipped.
  Future<void> setVolumeFor(String identity, double volume) async {
    _audio.setVolumeFor(identity, volume);
    final room = _room;
    if (room != null) await _applyLocalAudioState(room);
  }

  /// Silences (or restores) one participant, for this listener only.
  ///
  /// Reapplied on every room event through [_applyLocalAudioState], so a track
  /// that resubscribes after the mute stays silenced without this class
  /// tracking subscriptions itself.
  Future<void> setLocallyMuted(String identity, bool muted) async {
    _audio.setMuted(identity, muted);
    final room = _room;
    if (room != null) await _applyLocalAudioState(room);
    _refreshParticipants();
  }

  /// Why the last attempt failed, when [state] is [VoiceSessionState.failed].
  Object? get lastError => _lastError;

  /// Why the last call ended, when the SFU ended it rather than this client.
  VoiceDisconnect? get lastDisconnect => _lastDisconnect;

  /// The in-flight join, so a second call serializes behind it; see [join].
  Future<void>? _joining;

  /// Joins a room with a token minted by the server.
  ///
  /// The token decides what this connection may do: a member without SPEAK gets
  /// one that cannot publish, and the SFU enforces that, so nothing here needs
  /// to know about permissions. Rejoining an already-connected session leaves
  /// the old one first rather than stacking two connections.
  ///
  /// Overlapping calls serialize rather than race: both would otherwise pass
  /// the `_room != null` check before either assigns it, and two rooms then
  /// fight over one session's state, stranding the UI on connecting. A second
  /// tap of Join, or a channel switch mid-connect, now waits for the first
  /// attempt to settle and then runs, which ends in the state the *last*
  /// caller asked for.
  Future<void> join({
    required String url,
    required String token,
    bool microphoneEnabled = true,
    bool cameraEnabled = false,
  }) {
    final previous = _joining ?? Future<void>.value();
    final current = previous.catchError((_) {}).then(
          (_) => _join(
            url: url,
            token: token,
            microphoneEnabled: microphoneEnabled,
            cameraEnabled: cameraEnabled,
          ),
        );
    _joining = current.whenComplete(() {
      if (identical(_joining, current)) _joining = null;
    });
    return current;
  }

  Future<void> _join({
    required String url,
    required String token,
    required bool microphoneEnabled,
    required bool cameraEnabled,
  }) async {
    if (_disposed) return;
    if (_room != null) await leave();

    _lastDisconnect = null;
    _setState(VoiceSessionState.connecting);
    try {
      final room = _roomFactory();
      _room = room;
      _listen(room);
      await room.connect(url, token);
      // Publishing is separate from connecting on purpose: a join preview
      // can arrive muted, and a token without SPEAK must not fail the join.
      if (microphoneEnabled) {
        await _trySetMicrophone(true);
      }
      if (cameraEnabled) {
        await _trySetCamera(true);
      }
      _refreshParticipants();
      _setState(VoiceSessionState.connected);
    } catch (e) {
      _lastError = e;
      await _teardown();
      _setState(VoiceSessionState.failed);
    }
  }

  /// Leaves the call. Safe to call when not in one.
  ///
  /// Resets [deafened] along with everything else: there is no room left to
  /// apply it to once this returns, and leaving it set internally would
  /// silently deafen the next call before anyone asked for that, with
  /// nothing in [VoiceState] (which does reset) around to say so.
  Future<void> leave() async {
    await _teardown();
    _participants = const [];
    _audio.deafened = false;
    _audio.muted.clear();
    // Gain deliberately survives: somebody you turned down stays turned down.
    _lastDisconnect = null;
    if (!_participantsController.isClosed) {
      _participantsController.add(_participants);
    }
    _setState(VoiceSessionState.idle);
  }

  /// Whether starting a share here must name a source first.
  bool get screenShareNeedsSource => _desktopSources.required;

  /// Whether more than one enumerated source is worth asking a person to
  /// pick between; see [DesktopSources.sourcePickerUseful].
  bool get screenShareSourcePickerUseful => _desktopSources.sourcePickerUseful;

  /// The screens this desktop will let the app capture.
  ///
  /// Calling this is what makes a later [setScreenShareEnabled] able to find
  /// anything at all: see [DesktopSources].
  Future<List<ScreenShareSource>> screenShareSources() async {
    try {
      return await _desktopSources.list();
    } catch (e) {
      _lastError = e;
      return const [];
    }
  }

  /// Mutes or unmutes the local microphone.
  ///
  /// Returns whether the microphone ended up in the requested state, which is
  /// not the same as whether the call asked for it: a token without SPEAK, or a
  /// denied OS permission, both mean no. The UI needs to reflect what happened
  /// rather than what was requested, or the button lies.
  Future<bool> setMicrophoneEnabled(bool enabled) => _trySetMicrophone(enabled);

  Future<bool> _trySetMicrophone(bool enabled) async {
    final room = _room;
    if (room == null) return false;
    try {
      await room.localParticipant?.setMicrophoneEnabled(enabled);
      _refreshParticipants();
      return true;
    } catch (e) {
      _lastError = e;
      _refreshParticipants();
      return false;
    }
  }

  /// Enables or disables the local camera live, mid-call. The [join]-time
  /// `cameraEnabled` parameter is only the pre-toggle for before you connect;
  /// this is the same call `toggleMicrophone`'s equivalent already used, now
  /// reachable while already in the call.
  Future<bool> setCameraEnabled(bool enabled) => _trySetCamera(enabled);

  /// Publishes (or stops) a camera track. Failure is swallowed exactly as
  /// [_trySetMicrophone]'s is: a camera pre-toggle a device cannot honour
  /// (permission denied, no hardware) must not fail the join, since a call
  /// with no camera track is still a call.
  Future<bool> _trySetCamera(bool enabled) async {
    final room = _room;
    if (room == null) return false;
    try {
      await room.localParticipant?.setCameraEnabled(enabled);
      _refreshParticipants();
      return true;
    } catch (e) {
      _lastError = e;
      _refreshParticipants();
      return false;
    }
  }

  /// Starts or stops sharing a screen, bounded by [quality].
  ///
  /// Reports what happened rather than what was asked for, because on iOS
  /// those differ: see [ScreenShareOutcome]. Stopping asks the platform to end
  /// any broadcast as well as dropping the track, so the two cannot get out of
  /// step and leave a phone still recording with nothing published. The
  /// sequencing that makes iOS actually honour [quality] lives in
  /// [ScreenShareControl]; this method only supplies it a room to act on.
  Future<ScreenShareOutcome> setScreenShareEnabled(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
    String? sourceId,
  }) async {
    final room = _room;
    if (room == null) return ScreenShareOutcome.failed;
    final outcome = await _screenShare.setEnabled(
      enabled,
      quality: quality,
      sourceId: sourceId,
      publish: (enabled, options) async {
        await room.localParticipant?.setScreenShareEnabled(
          enabled,
          screenShareCaptureOptions: options,
        );
      },
      isSharing: () => isSharingScreen(room.localParticipant),
      onSettled: (error) {
        if (error != null) _lastError = error;
        _refreshParticipants();
      },
    );
    _refreshParticipants();
    return outcome;
  }

  /// The widget that renders [identity]'s shared screen, live.
  ///
  /// Returned as a plain [Widget] so no LiveKit type crosses the package
  /// seam; the real rendering is [ScreenShareView], which tracks the room's
  /// events itself so a share track arriving a beat after the roster flips
  /// still appears. Out of a call it renders nothing, not a placeholder:
  /// there is no room to watch.
  Widget screenShareViewFor(String identity) {
    final room = _room;
    if (room == null) return const SizedBox.shrink();
    return ScreenShareView(room: room, identity: identity);
  }

  /// The widget that renders [identity]'s live camera feed, [screenShareViewFor]'s
  /// exact counterpart: a plain [Widget] backed by [CameraView], working for
  /// the local participant exactly as it works for anyone else, which is
  /// what makes a self camera preview possible.
  Widget cameraViewFor(String identity) {
    final room = _room;
    if (room == null) return const SizedBox.shrink();
    return CameraView(room: room, identity: identity);
  }

  /// Whether flipping needs no chosen device; see [CameraSwitching.canFlip].
  bool get canFlipCamera => _cameraSwitching.canFlip;

  /// Whether picking a camera needs one named first; see
  /// [CameraSwitching.needsSelection].
  bool get cameraNeedsSelection => _cameraSwitching.needsSelection;

  /// The cameras this desktop (or browser) offers, for the picker. Calling
  /// this is what makes a later [selectCameraDevice] able to find anything,
  /// the same reason [screenShareSources] has to run first.
  Future<List<CameraDevice>> cameraDevices() async {
    try {
      return await _cameraSwitching.devices();
    } catch (e) {
      _lastError = e;
      return const [];
    }
  }

  /// Flips the published camera between front and back, mobile only.
  Future<bool> flipCamera() async {
    try {
      return await _cameraSwitching.flip(_room?.localParticipant);
    } catch (e) {
      _lastError = e;
      return false;
    }
  }

  /// Switches the published camera to [device], desktop's answer to
  /// [flipCamera] where more than one webcam can exist.
  Future<bool> selectCameraDevice(CameraDevice device) async {
    final room = _room;
    if (room == null) return false;
    try {
      await _cameraSwitching.select(room, device);
      _refreshParticipants();
      return true;
    } catch (e) {
      _lastError = e;
      return false;
    }
  }

  /// Silences (or restores) every remote participant's audio locally, by
  /// disabling the underlying WebRTC track rather than unsubscribing from
  /// it: a track publication's own `disable()` drops the SFU subscription
  /// and would need renegotiation before sound comes back, while flipping
  /// the underlying media track's `enabled` flag is a local, instant, and
  /// instantly reversible mute. Returns whether it took effect, matching
  /// [setMicrophoneEnabled] and [setScreenShareEnabled]'s own convention: no
  /// room, no effect.
  Future<bool> setDeafened(bool deafened) async {
    final room = _room;
    if (room == null) return false;
    _audio.deafened = deafened;
    await _applyLocalAudioState(room);
    return true;
  }

  /// Delegates to [LocalAudioState.applyTo]; see that class for why this
  /// runs on every room event rather than only when a control moves.
  Future<void> _applyLocalAudioState(lk.Room room) async {
    final failure = await _audio.applyTo(room);
    if (failure != null) _lastError = failure;
  }

  /// One coarse listener rather than a subscription per event type. Every
  /// event this cares about ends in the same place, "recompute who is in the
  /// call and what they are doing", so an event LiveKit adds later is picked
  /// up rather than silently ignored.
  void _listen(lk.Room room) {
    _cancelEvents?.call();
    _cancelEvents = room.events.listen((event) {
      if (event is lk.RoomDisconnectedEvent) {
        _onDisconnected(event.reason);
        return;
      }
      _refreshParticipants();
    });
  }

  /// A disconnect this client did not ask for. [_teardown] cancels this
  /// listener before it disconnects, so a `leave()` never lands here.
  void _onDisconnected(lk.DisconnectReason? reason) {
    if (_disposed) return;
    if (reason == lk.DisconnectReason.clientInitiated) return;
    _lastDisconnect = mapDisconnectReason(reason);
    _participants = const [];
    if (!_participantsController.isClosed) {
      _participantsController.add(_participants);
    }
    _setState(VoiceSessionState.failed);
  }

  void _refreshParticipants() {
    final room = _room;
    if (room == null || _disposed) return;

    // Reapplied on every refresh, not only on toggle, so a participant or
    // track appearing after deafening starts is silenced too.
    unawaited(_applyLocalAudioState(room));

    final next = snapshotParticipants(room);
    // Only emit on a real change: the events stream is chatty (audio levels
    // arrive constantly) and rebuilding the roster each time is how it janks.
    if (listEquals(next, _participants)) return;
    _participants = List.unmodifiable(next);
    if (!_participantsController.isClosed) {
      _participantsController.add(_participants);
    }
  }

  Future<void> _teardown() async {
    await _screenShare.dispose();
    _cancelEvents?.call();
    _cancelEvents = null;
    final room = _room;
    _room = null;
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {
        // Already gone, which is the state we wanted anyway.
      }
      await room.dispose();
    }
  }

  void _setState(VoiceSessionState next) {
    if (_state == next || _disposed) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _teardown();
    await _stateController.close();
    await _participantsController.close();
  }
}
