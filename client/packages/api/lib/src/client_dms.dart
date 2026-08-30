// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
part of 'client.dart';

/// Direct-message conversations, the `dms` tag.
extension SlimmApiDms on SlimmApi {
  /// Lists the caller's DM conversations, most recently active first. Each
  /// channel id works with the ordinary message, search, and sync routes
  /// exactly like any other channel.
  Future<List<DmConversation>> listDirectMessages() async {
    final json = await _send('GET', '/dms');
    return (json as List<dynamic>)
        .map((d) => DmConversation.fromJson(d as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Opens (or returns) the DM channel with [userId] - or, passing the
  /// caller's own id, their personal space. Idempotent and race-safe:
  /// opening the same pair twice, even concurrently, converges on one
  /// channel. Refused if either party has blocked the other.
  Future<DmConversation> openDirectMessage(String userId) async {
    final json = await _send('POST', '/dms/$userId');
    return DmConversation.fromJson(json as Map<String, dynamic>);
  }

  /// Closes the DM with [userId] out of the caller's own sidebar - a
  /// per-viewer hide, never a delete: no message is touched, and the other
  /// participant's own list is unaffected. Reappears on its own once they
  /// send something new, or the moment the caller opens or messages them
  /// again. Idempotent, and a no-op if the pair has no DM channel yet.
  Future<void> hideDirectMessage(String userId) =>
      _send('DELETE', '/dms/$userId', expectNoContent: true);
}
