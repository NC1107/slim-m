// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
part of 'message_store.dart';

/// The row a server-acknowledged message is stored as, shared by
/// [MessageStore.applyMessage] and the batch behind
/// [MessageStore.applyMessages] - which built the identical companion twice
/// until a forward gave them seven more columns to keep in step.
MessagesCompanion _rowFor(api.Message message) => MessagesCompanion.insert(
      id: message.id,
      channelId: message.channelId,
      authorId: Value(message.authorId),
      authorDisplayName: Value(message.authorDisplayName),
      seq: Value(message.seq),
      content: message.content,
      createdAt: message.createdAt,
      editedAt: Value(message.editedAt),
      pending: const Value(false),
      failed: const Value(false),
      replyToId: Value(message.replyToId),
      forwardedMessageId: Value(message.forwarded?.messageId),
      forwardedChannelId: Value(message.forwarded?.channelId),
      forwardedAuthorId: Value(message.forwarded?.authorId),
      forwardedAuthorDisplayName: Value(message.forwarded?.authorDisplayName),
      forwardedAuthorAvatarUpdatedAt:
          Value(message.forwarded?.authorAvatarUpdatedAt),
      forwardedCreatedAt: Value(message.forwarded?.createdAt),
      forwardedContent: Value(message.forwarded?.content),
    );
