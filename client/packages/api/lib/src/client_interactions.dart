// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
part of 'client.dart';

/// Pressing a bot's button. The bot's own answers (replace the buttons, ack,
/// reply privately) are called from its process, never from this client. See
/// docs/decisions/0039-bot-message-buttons.md.
extension SlimmApiInteractions on SlimmApi {
  /// Presses [customId] on [messageId]. [id] is the caller's own UUID, so a
  /// retry after a timeout is the same press rather than a second one.
  Future<void> pressMessageButton({
    required String channelId,
    required String messageId,
    required String id,
    required String customId,
  }) =>
      _send(
        'POST',
        '/channels/$channelId/messages/$messageId/interactions',
        body: {'id': id, 'custom_id': customId},
      );
}
