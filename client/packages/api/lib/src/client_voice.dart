// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// Voice: joining a channel's room, evicting a participant, and previewing
/// who is already in one, the `voice` tag.
extension SlimmApiVoice on SlimmApi {
  /// Mints a join token for a channel's voice room.
  ///
  /// Throws [NotImplementedException] when the deployment has no SFU, which is
  /// a supported way to run text-only rather than a fault, so a caller should
  /// hide voice rather than retry.
  Future<VoiceToken> voiceToken(String channelId) async {
    final json = await _send('POST', '/channels/$channelId/voice/token');
    return VoiceToken.fromJson(json as Map<String, dynamic>);
  }

  /// Evicts a participant from a channel's voice room.
  ///
  /// Idempotent: removing somebody who is not connected succeeds, so a retry
  /// after a timeout is safe. This does not bar them from rejoining - taking
  /// away CONNECT is what does that - it makes the removal take effect now
  /// rather than when their current token lapses.
  Future<void> kickVoiceParticipant(String channelId, String userId) => _send(
        'POST',
        '/channels/$channelId/voice/participants/$userId/kick',
        expectNoContent: true,
      );

  /// Who is currently in a channel's voice room, whether or not this client
  /// has joined it.
  ///
  /// A real round trip to the server's SFU, unlike [voiceToken], which is pure
  /// local signing; poll this on an interval rather than on every render.
  ///
  /// Throws [NotConfiguredException] when the deployment has no SFU (hide the
  /// roster rather than retry), and [UnavailableException] when one is
  /// configured but could not be reached just now (unknown, not empty; keep
  /// showing the last roster you had rather than clearing it to nothing).
  Future<List<VoiceRosterParticipant>> voiceRoster(String channelId) async {
    final json = await _send('GET', '/channels/$channelId/voice/roster');
    final participants = (json as Map<String, dynamic>)['participants'];
    return (participants as List<dynamic>)
        .map((p) => VoiceRosterParticipant.fromJson(p as Map<String, dynamic>))
        .toList(growable: false);
  }
}
