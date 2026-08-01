// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// The whole `messages` tag: sending, reading, editing, deleting,
/// full-text search and reactions.
///
/// The first three used to sit in `client.dart` and the rest here, which
/// was a line-count boundary rather than a real one.
extension SlimmApiMessages on SlimmApi {
  /// History, newest first. Pass the smallest `seq` already held as [before] to
  /// page backwards.
  Future<List<Message>> listMessages(
    String channelId, {
    int? before,
    int? limit,
  }) async {
    final query = <String, String>{
      if (before != null) 'before': '$before',
      if (limit != null) 'limit': '$limit',
    };
    final json = await _send(
      'GET',
      '/channels/$channelId/messages',
      query: query.isEmpty ? null : query,
    );
    return (json as List<dynamic>)
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Sends a message. [id] must be a client-generated UUIDv7 and makes the send
  /// idempotent, so retrying an uncertain send is always safe. [attachmentIds]
  /// are hex sha256 ids already uploaded through [SlimmApi.uploadAttachment],
  /// in display order; a non-empty list needs ATTACH_FILES in addition to
  /// SEND_MESSAGES. [replyToId] must already name a message in this same
  /// channel (live or deleted) or the send is refused.
  Future<Message> sendMessage({
    required String channelId,
    required String id,
    required String content,
    List<String> attachmentIds = const [],
    String? replyToId,
  }) async {
    final json = await _send(
      'POST',
      '/channels/$channelId/messages',
      body: {
        'id': id,
        'content': content,
        if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
        if (replyToId != null) 'reply_to_id': replyToId,
      },
    );
    return Message.fromJson(json as Map<String, dynamic>);
  }

  Future<Message> editMessage({
    required String channelId,
    required String messageId,
    required String content,
  }) async {
    final json = await _send(
      'PATCH',
      '/channels/$channelId/messages/$messageId',
      body: {'content': content},
    );
    return Message.fromJson(json as Map<String, dynamic>);
  }

  /// Soft-deletes a message. Allowed for the author, or a member with
  /// MANAGE_MESSAGES. Deleting an already-deleted message is not an error.
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) =>
      _send(
        'DELETE',
        '/channels/$channelId/messages/$messageId',
        expectNoContent: true,
      );

  /// Full-text searches a channel's live messages. [q] reaches FTS5 close to
  /// as-is, so its mini query language (`AND`/`OR`/`NOT`, `"phrase"`, a
  /// trailing `*` prefix) is available. Results are permission-filtered and
  /// keyset paginated on `seq` exactly like [SlimmApi.listMessages].
  Future<List<Message>> searchMessages(
    String channelId, {
    required String q,
    int? before,
    int? limit,
  }) async {
    final query = <String, String>{
      'q': q,
      if (before != null) 'before': '$before',
      if (limit != null) 'limit': '$limit',
    };
    final json = await _send(
      'GET',
      '/channels/$channelId/messages/search',
      query: query,
    );
    return (json as List<dynamic>)
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Reacts to a message with one [emoji]. Idempotent: reacting twice with
  /// the same emoji leaves one reaction. [emoji] is user content, never
  /// chrome, so it is a plain runtime string rather than a literal in source.
  ///
  /// The server keys the reaction on the string, not on a codepoint: it takes
  /// any non-empty run under 64 bytes (`MAX_EMOJI_BYTES`, `store/reactions.rs`)
  /// and hands it back verbatim in every summary. So one of the deployment's
  /// own emoji rides here as its `:shortcode:`, at most 34 bytes, and the
  /// colons stay unescaped in the path because they are legal there.
  Future<void> addReaction({
    required String messageId,
    required String emoji,
  }) =>
      _send(
        'PUT',
        '/messages/$messageId/reactions/$emoji',
        expectNoContent: true,
      );

  /// Removes the caller's own reaction of one [emoji] from a message.
  /// Idempotent: removing a reaction that is not there succeeds, since the
  /// caller's intent already holds.
  Future<void> removeReaction({
    required String messageId,
    required String emoji,
  }) =>
      _send(
        'DELETE',
        '/messages/$messageId/reactions/$emoji',
        expectNoContent: true,
      );

  /// Pins a message. Idempotent: pinning an already-pinned message leaves the
  /// original pin's timestamp and pinner in place. Requires MANAGE_MESSAGES,
  /// evaluated in this channel specifically.
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) =>
      _send(
        'PUT',
        '/channels/$channelId/messages/$messageId/pin',
        expectNoContent: true,
      );

  /// Unpins a message. Idempotent: unpinning a message that is not pinned
  /// succeeds, since the caller's intent already holds either way.
  Future<void> unpinMessage({
    required String channelId,
    required String messageId,
  }) =>
      _send(
        'DELETE',
        '/channels/$channelId/messages/$messageId/pin',
        expectNoContent: true,
      );

  /// A channel's pinned messages, newest pin first. Requires only
  /// VIEW_CHANNEL.
  Future<List<PinnedMessage>> listPinnedMessages(String channelId) async {
    final json = await _send('GET', '/channels/$channelId/pins');
    return (json as List<dynamic>)
        .map((p) => PinnedMessage.fromJson(p as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// How many messages are pinned in a channel. Cheap: a single indexed
  /// count, never a fetch of every pinned message.
  Future<int> pinnedMessageCount(String channelId) async {
    final json = await _send('GET', '/channels/$channelId/pins/count');
    return (json as Map<String, dynamic>)['count'] as int;
  }

  /// Sends a message that carries a poll. Idempotent by [id] exactly like
  /// [SlimmApi.sendMessage], and gated the same way (view plus send in this
  /// channel). [options] needs between 2 and 4 entries. [closeAt] (unix
  /// milliseconds), if given, is when the server starts refusing votes.
  Future<Message> sendPollMessage({
    required String channelId,
    required String id,
    required String question,
    required List<String> options,
    String? content,
    int? closeAt,
  }) async {
    final json = await _send(
      'POST',
      '/channels/$channelId/messages/polls',
      body: {
        'id': id,
        'question': question,
        'options': options,
        if (content != null) 'content': content,
        if (closeAt != null) 'close_at': closeAt,
      },
    );
    return Message.fromJson(json as Map<String, dynamic>);
  }

  /// Casts or changes the caller's vote on a message's poll: one vote per
  /// user, so a second call replaces the first rather than adding to it.
  /// Requires viewing the channel plus SEND_MESSAGES there, and is refused
  /// once the poll's close time has passed.
  Future<void> votePoll({required String messageId, required int option}) =>
      _send(
        'PUT',
        '/messages/$messageId/polls/vote',
        body: {'option': option},
        expectNoContent: true,
      );
}
