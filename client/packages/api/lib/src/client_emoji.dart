// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// Custom emoji: the deployment's own named images. The `emoji` tag.
///
/// Reading is open to every authenticated member, deliberately unlike an
/// attachment: an emoji renders inside messages they may already read, and
/// gating it per channel would leak which channels use which emoji. Writing
/// takes MANAGE_SERVER.
extension SlimmApiEmoji on SlimmApi {
  /// Every custom emoji in the deployment, oldest first.
  ///
  /// Unpaginated on purpose: rendering any message containing a
  /// `:shortcode:` needs the whole set, and the server caps it.
  Future<List<CustomEmoji>> listCustomEmoji() async {
    final json = await _send('GET', '/emoji');
    return (json as List<dynamic>)
        .map((e) => CustomEmoji.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Adds an emoji from raw [bytes] under [name]. Requires MANAGE_SERVER.
  ///
  /// The server normalises [name] to lowercase a-z, 0-9 and underscore, so
  /// the returned [CustomEmoji.name] is authoritative and may differ from
  /// what was sent. Two spellings that normalise together collide: the second
  /// throws [ConflictException] rather than creating an emoji a shortcode
  /// could not choose between. The content type is sniffed from the bytes, so
  /// a non-image throws [BadRequestException] whatever it was named.
  Future<CustomEmoji> uploadCustomEmoji(
    List<int> bytes, {
    required String name,
  }) async {
    final json = await _send(
      'POST',
      '/emoji',
      bytes: bytes,
      query: {'name': name},
    );
    return CustomEmoji.fromJson(json as Map<String, dynamic>);
  }

  /// Removes an emoji. Requires MANAGE_SERVER. Idempotent: removing one
  /// already gone succeeds, so a retry never has to tell "gone" from "never
  /// existed".
  Future<void> deleteCustomEmoji(String emojiId) =>
      _send('DELETE', '/emoji/$emojiId', expectNoContent: true);

  /// Fetches an emoji's image bytes. Gated on authentication only, and the
  /// bytes never change under an id, so the result is safe to cache for as
  /// long as the id is held.
  Future<FetchedBytes> fetchCustomEmojiImage(String emojiId) =>
      _fetchBytes('/emoji/$emojiId/image');
}
