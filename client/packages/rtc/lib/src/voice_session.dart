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

import 'package:livekit_client/livekit_client.dart' as lk;

import 'broadcast_bridge.dart';
import 'screen_share.dart';

/// Where a session is in its lifecycle.
enum VoiceSessionState {
  /// Not in a call.
  idle,

  /// Token in hand, negotiating with the SFU.
  connecting,

  /// In the call.
  connected,

  /// The last attempt failed, or the connection dropped and did not recover.
  /// [VoiceSession.lastError] says what happened.
  failed,
}

/// Somebody in the call, including you.
///
/// Deliberately a plain value rather than a LiveKit participant: the UI needs
/// an identity, a name, and three booleans, and handing it a live SDK object
/// would let a widget subscribe to something this class is supposed to own.
class VoiceParticipant {
  const VoiceParticipant({
    required this.identity,
    required this.name,
    required this.isSpeaking,
    required this.isMuted,
    required this.isLocal,
    required this.isScreenSharing,
  });

  /// The server's user id. The token's `sub`, so it is trustworthy.
  final String identity;

  /// Display name as the token carried it.
  final String name;

  final bool isSpeaking;
  final bool isMuted;
  final bool isLocal;
  final bool isScreenSharing;

  @override
  bool operator ==(Object other) =>
      other is VoiceParticipant &&
      other.identity == identity &&
      other.name == name &&
      other.isSpeaking == isSpeaking &&
      other.isMuted == isMuted &&
      other.isLocal == isLocal &&
      other.isScreenSharing == isScreenSharing;

  @override
  int get hashCode => Object.hash(
      identity, name, isSpeaking, isMuted, isLocal, isScreenSharing);
}

/// Builds the LiveKit room a session drives. The injection seam.
typedef RoomFactory = lk.Room Function();

/// A voice call in one channel.
///
/// Not a singleton and not global: one session is one call, and the caller owns
/// its lifetime. [dispose] must be called, and leaving is not the same as
/// disposing, because a user can leave and rejoin without the surrounding
/// screen being torn down.
class VoiceSession {
  VoiceSession({RoomFactory? roomFactory, BroadcastBridge? broadcast})
      : _roomFactory = roomFactory ?? _defaultRoomFactory,
        _broadcast = broadcast ?? const MethodChannelBroadcastBridge();

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
  bool _disposed = false;

  /// Whether every remote participant's audio is locally silenced. Purely
  /// local playback state: it never touches this session's own microphone
  /// or publishes anything, so nobody else in the call can tell.
  bool _deafened = false;

  VoiceSessionState get state => _state;
  Stream<VoiceSessionState> get states => _stateController.stream;

  List<VoiceParticipant> get participants => _participants;
  Stream<List<VoiceParticipant>> get participantChanges =>
      _participantsController.stream;

  bool get deafened => _deafened;

  /// Why the last attempt failed, when [state] is [VoiceSessionState.failed].
  Object? get lastError => _lastError;

  /// Joins a room with a token minted by the server.
  ///
  /// The token decides what this connection may do: a member without SPEAK gets
  /// one that cannot publish, and the SFU enforces that, so nothing here needs
  /// to know about permissions. Rejoining an already-connected session leaves
  /// the old one first rather than stacking two connections.
  Future<void> join({
    required String url,
    required String token,
    bool microphoneEnabled = true,
  }) async {
    if (_disposed) return;
    if (_room != null) await leave();

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
    _deafened = false;
    if (!_participantsController.isClosed) {
      _participantsController.add(_participants);
    }
    _setState(VoiceSessionState.idle);
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

  /// Starts or stops sharing a screen, bounded by [quality].
  ///
  /// Reports what happened rather than what was asked for, because on iOS
  /// those differ: see [ScreenShareOutcome]. Stopping asks the platform to end
  /// any broadcast as well as dropping the track, so the two cannot get out of
  /// step and leave a phone still recording with nothing published.
  Future<ScreenShareOutcome> setScreenShareEnabled(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
  }) async {
    final room = _room;
    if (room == null) return ScreenShareOutcome.failed;
    // Asked before the request, not after a wait: a build with no extension
    // shows no picker, so waiting only turns a knowable no into a slow one.
    if (enabled && !await _broadcast.isAvailable()) {
      return ScreenShareOutcome.unsupported;
    }
    try {
      await room.localParticipant?.setScreenShareEnabled(
        enabled,
        screenShareCaptureOptions: enabled
            ? lk.ScreenShareCaptureOptions(
                maxFrameRate: quality.fps.toDouble(),
                params: lk.VideoParameters(
                  dimensions: lk.VideoDimensions(quality.width, quality.height),
                  encoding: lk.VideoEncoding(
                    maxBitrate: quality.maxBitrate,
                    maxFramerate: quality.fps,
                  ),
                ),
              )
            : null,
      );
      if (!enabled) await _broadcast.requestStop();
      _refreshParticipants();
      if (!enabled) return ScreenShareOutcome.stopped;
      return _isSharing(room.localParticipant)
          ? ScreenShareOutcome.started
          : ScreenShareOutcome.pendingBroadcast;
    } catch (e) {
      _lastError = e;
      _refreshParticipants();
      return ScreenShareOutcome.failed;
    }
  }

  /// A published screen track is the only thing that means anybody can see a
  /// screen, so it is what both the roster and the outcome above read.
  static bool _isSharing(lk.Participant? p) =>
      p?.videoTrackPublications
          .any((t) => t.source == lk.TrackSource.screenShareVideo) ??
      false;

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
    _deafened = deafened;
    await _applyDeafenState(room);
    return true;
  }

  /// Applies [_deafened] to every remote audio track currently subscribed.
  /// Called again on every room event (see [_listen]), not just when the
  /// toggle changes, which is what keeps a participant who joins (or whose
  /// track resubscribes) after deafening starts silenced too, without this
  /// session having to track subscriptions itself.
  Future<void> _applyDeafenState(lk.Room room) async {
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.audioTrackPublications) {
        final track = publication.track;
        if (track == null) continue;
        try {
          if (_deafened) {
            await track.disable();
          } else {
            await track.enable();
          }
        } catch (e) {
          _lastError = e;
        }
      }
    }
  }

  /// One coarse listener rather than a subscription per event type. Every
  /// event this cares about ends in the same place, "recompute who is in the
  /// call and what they are doing", so an event LiveKit adds later is picked
  /// up rather than silently ignored.
  void _listen(lk.Room room) {
    _cancelEvents?.call();
    _cancelEvents = room.events.listen((_) => _refreshParticipants());
  }

  void _refreshParticipants() {
    final room = _room;
    if (room == null || _disposed) return;

    // Reapplied on every refresh, not only on toggle, so a participant or
    // track appearing after deafening starts is silenced too.
    unawaited(_applyDeafenState(room));

    final next = <VoiceParticipant>[];
    final local = room.localParticipant;
    if (local != null) {
      next.add(_toParticipant(local, isLocal: true));
    }
    for (final remote in room.remoteParticipants.values) {
      next.add(_toParticipant(remote, isLocal: false));
    }

    // Only emit on a real change: the events stream is chatty (audio levels
    // arrive constantly) and rebuilding the roster each time is how it janks.
    if (_listEquals(next, _participants)) return;
    _participants = List.unmodifiable(next);
    if (!_participantsController.isClosed) {
      _participantsController.add(_participants);
    }
  }

  VoiceParticipant _toParticipant(lk.Participant p, {required bool isLocal}) {
    final audio = p.audioTrackPublications;
    final muted = audio.isEmpty || audio.every((t) => t.muted);
    return VoiceParticipant(
      identity: p.identity,
      // Falls back to the identity rather than showing an empty row: a
      // participant with no name is still somebody in the call.
      name: p.name.isEmpty ? p.identity : p.name,
      isSpeaking: p.isSpeaking,
      isMuted: muted,
      isLocal: isLocal,
      isScreenSharing: _isSharing(p),
    );
  }

  static bool _listEquals(List<VoiceParticipant> a, List<VoiceParticipant> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _teardown() async {
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
