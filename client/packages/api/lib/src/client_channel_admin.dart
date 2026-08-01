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

  /// Sets the deployment's channel order. Requires MANAGE_CHANNELS.
  /// [channelIds] must name exactly the live, non-DM channels, in the
  /// desired order; a partial or wrong list is refused with a 400 naming
  /// what was missing or unrecognized rather than silently leaving a gap.
  /// Deployment-wide, not a per-device preference: everyone sees the same
  /// order. Returns every live, non-DM channel in its new order.
  Future<List<Channel>> reorderChannels(List<String> channelIds) async {
    final json = await _send(
      'PUT',
      '/channels/order',
      body: {'channel_ids': channelIds},
    );
    return (json as List<dynamic>)
        .map((c) => Channel.fromJson(c as Map<String, dynamic>))
        .toList(growable: false);
  }
}
