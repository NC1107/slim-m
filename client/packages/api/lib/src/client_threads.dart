// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// Opening a thread: the one call `openThread` needs, split out of
/// `client_messages.dart` to keep that file under the review budget, the
/// same reason `client_channel_admin.dart` exists.
extension SlimmApiThreads on SlimmApi {
  /// Opens (or reuses) the thread hanging off a message. Idempotent per
  /// message: a second call for the same message, by anyone who can already
  /// see it, returns the same channel. Requires VIEW_CHANNEL and
  /// SEND_MESSAGES in [channelId], the same bits [SlimmApiMessages.sendMessage]
  /// itself needs there - starting a thread is a way of sending, not a way
  /// of managing the channel. Refused if [messageId] is itself inside a
  /// thread; nesting is not supported.
  Future<Channel> openThread({
    required String channelId,
    required String messageId,
  }) async {
    final json = await _send(
      'POST',
      '/channels/$channelId/messages/$messageId/thread',
    );
    return Channel.fromJson(json as Map<String, dynamic>);
  }
}
