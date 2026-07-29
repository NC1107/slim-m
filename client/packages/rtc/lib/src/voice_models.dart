// SPDX-License-Identifier: Apache-2.0
/// The value types a voice call exposes to the rest of the client.
///
/// Split out of `voice_session.dart` when that file reached the 500-line
/// ceiling. Deliberately plain values with no LiveKit types in them, for the
/// reason the session's own doc comment gives: the UI needs names and
/// booleans, not a live SDK object it could subscribe to behind our back.
library;

/// Where a session is in its lifecycle.
enum VoiceSessionState {
  /// Not in a call.
  idle,

  /// Token in hand, negotiating with the SFU.
  connecting,

  /// In the call.
  connected,

  /// The last attempt failed, or the connection dropped and did not recover.
  /// `VoiceSession.lastError` says what happened.
  failed,
}

/// Why a call ended, when it was not this client that ended it.
///
/// The SFU reports a reason on every disconnect and nothing read it, so a call
/// that was dropped looked exactly like a call that was left.
enum VoiceDisconnect {
  /// The same account joined from somewhere else and took this slot. The SFU
  /// allows one connection per identity and evicts the older one.
  replacedByOtherDevice,

  /// A moderator removed this participant, or the room went away.
  removed,

  /// The connection dropped and reconnecting did not recover it.
  connectionLost,

  /// Ended for a reason this client cannot name.
  unknown;

  /// What to tell the user, in their terms rather than the SFU's.
  String get message => switch (this) {
        replacedByOtherDevice =>
          'You joined this call from another device, so this one left it.',
        removed => 'You were removed from the call.',
        connectionLost => 'The call disconnected and could not reconnect.',
        unknown => 'The call ended unexpectedly.',
      };
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
        identity,
        name,
        isSpeaking,
        isMuted,
        isLocal,
        isScreenSharing,
      );
}
