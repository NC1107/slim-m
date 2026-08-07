// SPDX-License-Identifier: Apache-2.0
part of 'voice_session.dart';

/// The private "try to change a published track" leaves behind
/// [VoiceSession]'s microphone, camera and deafen controls.
///
/// Split out for the file's 500-line hard ceiling. Each of the three below is
/// self-contained (publish, catch, record the error, refresh the roster) and
/// entirely private, unlike their public callers, which stay declared on
/// [VoiceSession] itself: several tests build a `FakeSession implements
/// VoiceSession` specifically so a method added to the real session is a
/// compile error there rather than a silently untested path, and moving a
/// *public* method out of the class into an extension would drop it from
/// that interface instead of merely relocating its body.
extension VoiceSessionTracks on VoiceSession {
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
