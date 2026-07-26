// SPDX-License-Identifier: Apache-2.0
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

  /// Opens (or returns) the DM channel with [userId]. Idempotent and
  /// race-safe: opening the same pair twice, even concurrently, converges on
  /// one channel. Refused if either party has blocked the other.
  Future<DmConversation> openDirectMessage(String userId) async {
    final json = await _send('POST', '/dms/$userId');
    return DmConversation.fromJson(json as Map<String, dynamic>);
  }
}
