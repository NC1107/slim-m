// SPDX-License-Identifier: Apache-2.0
part of 'voice_session.dart';

/// [VoiceSession]'s private plumbing: the "try to change a published track"
/// leaves behind its microphone, camera and deafen controls, plus the room
/// event listener and the forced-disconnect handler that listener routes to.
///
/// Split out for the file's 500-line hard ceiling. Everything here is
/// entirely private, unlike the public callers, which stay declared on
/// [VoiceSession] itself: several tests build a `FakeSession implements
/// VoiceSession` specifically so a method added to the real session is a
/// compile error there rather than a silently untested path, and moving a
/// *public* method out of the class into an extension would drop it from
/// that interface instead of merely relocating its body.
extension VoiceSessionTracks on VoiceSession {
  /// One coarse listener rather than a subscription per event type. Every
  /// event this cares about ends in the same place, "recompute who is in the
  /// call and what they are doing", so an event LiveKit adds later is picked
  /// up rather than silently ignored.
  void _listen(lk.Room room) {
    _cancelEvents?.call();
    _cancelEvents = room.events.listen((event) {
      if (event is lk.RoomDisconnectedEvent) {
        return _onDisconnected(event.reason);
      }
      _refreshParticipants();
    });
  }

  /// A disconnect this client did not ask for: the SFU removed this
  /// participant, the room was deleted, or the connection was lost for good.
  /// `_teardown` cancels this listener before it disconnects, so a `leave()`
  /// never lands here.
  ///
  /// LiveKit's own engine already unpublishes and stops every local track for
  /// this case (`Room`'s internal cleanup runs on any engine disconnect, not
  /// only a client-initiated one), but that stops at the WebRTC track: it
  /// never asks iOS to end a running broadcast, which is a platform-level
  /// concept LiveKit has no reason to know about. By the time this fires the
  /// SFU has already disconnected, so this is the only remaining chance to
  /// tell iOS to stop, and it is awaited before anything else this handler
  /// does rather than fired into the background: a member removed or timed
  /// out mid-share must not keep recording with no call left to publish to.
  Future<void> _onDisconnected(lk.DisconnectReason? reason) async {
    if (_disposed) return;
    if (reason == lk.DisconnectReason.clientInitiated) return;
    await _screenShare.stopActiveBroadcast();
    _lastDisconnect = mapDisconnectReason(reason);
    _participants = const [];
    if (!_participantsController.isClosed) {
      _participantsController.add(_participants);
    }
    _setState(VoiceSessionState.failed);
    await _screenShare.dispose();
  }

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

  /// Publishes (or stops) a camera track. Failure is swallowed exactly as
  /// [_trySetMicrophone]'s is: a camera pre-toggle a device cannot honour
  /// (permission denied, no hardware) must not fail the join, since a call
  /// with no camera track is still a call.
  Future<bool> _trySetCamera(bool enabled) async {
    final room = _room;
    if (room == null) return false;
    final result = await _cameraSwitching.setEnabled(
      room.localParticipant,
      enabled,
    );
    if (result.error != null) _lastError = result.error;
    _refreshParticipants();
    return result.ok;
  }

  /// Delegates to [LocalAudioState.applyTo]; see that class for why this
  /// runs on every room event rather than only when a control moves.
  Future<void> _applyLocalAudioState(lk.Room room) async {
    final failure = await _audio.applyTo(room);
    if (failure != null) _lastError = failure;
  }
}
