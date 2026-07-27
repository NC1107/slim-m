// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// Channel renaming and deletion: the rest of the `channels` tag that
/// [SlimmApi.listChannels] and [SlimmApi.createChannel] do not cover.
extension SlimmApiChannelAdmin on SlimmApi {
  /// Renames a channel and/or replaces its topic. Requires MANAGE_CHANNELS at
  /// the deployment level, the same check creating a channel uses. At least
  /// one of [name] and [topic] must be given; a blank or whitespace-only
  /// [topic] clears it back to none rather than storing an empty string.
  Future<Channel> updateChannel({
    required String channelId,
    String? name,
    String? topic,
  }) async {
    final json = await _send(
      'PATCH',
      '/channels/$channelId',
      body: {
        if (name != null) 'name': name,
        if (topic != null) 'topic': topic,
      },
    );
    return Channel.fromJson(json as Map<String, dynamic>);
  }

  /// Soft-deletes a channel. Requires MANAGE_CHANNELS. Refused if this is the
  /// deployment's last live channel, since a deployment with zero channels
  /// has nowhere for anyone to land. Deleting an already-deleted channel is
  /// not an error.
  Future<void> deleteChannel(String channelId) =>
      _send('DELETE', '/channels/$channelId', expectNoContent: true);
}
