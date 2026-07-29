// SPDX-License-Identifier: Apache-2.0
/// The event WebSocket: typed frames and the connection that carries them.
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'client.dart';
import 'models.dart';

part 'events_frames.dart';

/// The envelope version this client speaks. The server refuses a mismatch, so a
/// client that is too old fails at connect rather than misreading frames.
const int protocolVersion = 1;

/// An event pushed by the server.
sealed class ServerEvent {
  const ServerEvent();

  /// Parses a frame, or returns null for anything unrecognized. Unknown frame
  /// types (or a known type with a shape that does not parse) are ignored
  /// rather than fatal, so the server can add events without breaking older
  /// clients.
  static ServerEvent? parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final message = decoded['message'];
    return switch (decoded['type']) {
      'hello' => HelloEvent(protocol: decoded['protocol'] as int? ?? 0),
      'message.created' when message is Map<String, dynamic> =>
        MessageCreated(Message.fromJson(message)),
      'message.edited' when message is Map<String, dynamic> =>
        MessageEdited(Message.fromJson(message)),
      'message.deleted'
          when decoded['channel_id'] is String &&
              decoded['message_id'] is String =>
        MessageDeleted(
          channelId: decoded['channel_id'] as String,
          messageId: decoded['message_id'] as String,
        ),
      'reactions.changed'
          when decoded['channel_id'] is String &&
              decoded['message_id'] is String &&
              decoded['reactions'] is List =>
        ReactionsChanged(
          channelId: decoded['channel_id'] as String,
          messageId: decoded['message_id'] as String,
          reactions: (decoded['reactions'] as List<dynamic>)
              .map((r) => ReactionTally.fromJson(r as Map<String, dynamic>))
              .toList(growable: false),
        ),
      'message.pinned'
          when decoded['channel_id'] is String &&
              decoded['message_id'] is String &&
              decoded['pinned_at'] is int =>
        MessagePinned(
          channelId: decoded['channel_id'] as String,
          messageId: decoded['message_id'] as String,
          pinnedBy: decoded['pinned_by'] as String?,
          pinnedAt: decoded['pinned_at'] as int,
        ),
      'message.unpinned'
          when decoded['channel_id'] is String &&
              decoded['message_id'] is String =>
        MessageUnpinned(
          channelId: decoded['channel_id'] as String,
          messageId: decoded['message_id'] as String,
        ),
      'poll.voted'
          when decoded['channel_id'] is String &&
              decoded['message_id'] is String &&
              decoded['options'] is List =>
        PollVoted(
          channelId: decoded['channel_id'] as String,
          messageId: decoded['message_id'] as String,
          options: (decoded['options'] as List<dynamic>)
              .map((o) => PollOptionTally.fromJson(o as Map<String, dynamic>))
              .toList(growable: false),
        ),
      'presence.changed'
          when decoded['user_id'] is String &&
              _presenceStateOf(decoded['status']) != null =>
        PresenceChanged(
          userId: decoded['user_id'] as String,
          status: _presenceStateOf(decoded['status'])!,
        ),
      'member.timeout' when decoded['user_id'] is String =>
        MemberTimeoutChanged(
          userId: decoded['user_id'] as String,
          // Absent and null both mean "no timeout", which is what a lift sends.
          until: decoded['until'] as int?,
        ),
      'member.removed' when decoded['user_id'] is String =>
        MemberRemoved(userId: decoded['user_id'] as String),
      'typing.started'
          when decoded['channel_id'] is String &&
              decoded['user_id'] is String =>
        TypingStarted(
          channelId: decoded['channel_id'] as String,
          userId: decoded['user_id'] as String,
        ),
      'typing.stopped'
          when decoded['channel_id'] is String &&
              decoded['user_id'] is String =>
        TypingStopped(
          channelId: decoded['channel_id'] as String,
          userId: decoded['user_id'] as String,
        ),
      'pong' => const PongEvent(),
      'error' => ErrorEvent(decoded['message'] as String? ?? 'unknown'),
      _ => null,
    };
  }
}

/// Resolves a frame's raw `status` string to a known [PresenceState], or null
/// for anything else (including a non-string), so a future server addition
/// is ignored the same way an unrecognized frame type is rather than
/// throwing out of an enum lookup.
PresenceState? _presenceStateOf(Object? raw) {
  if (raw is! String) return null;
  for (final state in PresenceState.values) {
    if (state.name == raw) return state;
  }
  return null;
}

/// The server accepted the handshake.
class HelloEvent extends ServerEvent {
  const HelloEvent({required this.protocol});

  final int protocol;
}

/// A message was posted in a channel this session can view.
class MessageCreated extends ServerEvent {
  const MessageCreated(this.message);

  final Message message;
}

/// A message was edited.
class MessageEdited extends ServerEvent {
  const MessageEdited(this.message);

  final Message message;
}

/// Keepalive reply.
class PongEvent extends ServerEvent {
  const PongEvent();
}

/// A terminal condition. `resync` means the connection fell behind and was
/// closed, so reconnect and catch up over sync.
class ErrorEvent extends ServerEvent {
  const ErrorEvent(this.message);

  final String message;

  bool get needsResync => message == 'resync';
}

/// Opens the event socket and yields its events.
///
/// The connection is deliberately not self-healing here: it surfaces closure so
/// the layer above can decide to reconnect and, critically, to catch up over
/// sync before trusting the live stream again. Silent reconnection would leave
/// a gap in the sequence that the caller never learns about.
class EventConnection {
  EventConnection._(this._channel, this._events);

  final WebSocketChannel _channel;
  final Stream<ServerEvent> _events;

  /// Events after a successful handshake.
  Stream<ServerEvent> get events => _events;

  /// Resolves when the socket closes, for any reason.
  Future<void> get closed => _channel.sink.done;

  /// Connects, mints nothing itself: pass a ticket from
  /// [SlimmApi.webSocketTicket]. Completes once the server's hello arrives, so
  /// a returned connection is authenticated and ready.
  static Future<EventConnection> connect({
    required Uri url,
    required String ticket,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final channel = WebSocketChannel.connect(url);
    await channel.ready.timeout(timeout);

    final events = channel.stream
        .map((raw) => ServerEvent.parse(
            raw is String ? raw : utf8.decode(raw as List<int>)))
        .where((event) => event != null)
        .cast<ServerEvent>()
        .asBroadcastStream();

    // Send the hello and wait for the server's, so the caller never sees a
    // half-open connection.
    final handshake = events.first.timeout(timeout);
    channel.sink.add(
      jsonEncode(
          {'type': 'hello', 'ticket': ticket, 'protocol': protocolVersion}),
    );

    final ServerEvent first;
    try {
      first = await handshake;
    } on TimeoutException {
      await channel.sink.close();
      throw const EventConnectionRefused(
          'the server did not answer the handshake');
    }

    switch (first) {
      case HelloEvent(:final protocol) when protocol == protocolVersion:
        return EventConnection._(channel, events);
      case HelloEvent(:final protocol):
        await channel.sink.close();
        throw EventConnectionRefused(
          'the server speaks protocol $protocol, this client speaks $protocolVersion',
        );
      case ErrorEvent(:final message):
        await channel.sink.close();
        throw EventConnectionRefused(message);
      default:
        await channel.sink.close();
        throw const EventConnectionRefused(
            'the server did not open with a hello');
    }
  }

  /// Sends a keepalive. The server answers with [PongEvent].
  void ping() => _channel.sink.add(jsonEncode({'type': 'ping'}));

  /// Refreshes "this user is typing" in a channel.
  ///
  /// There is deliberately no stop frame: the server expires the state on a
  /// TTL, so a client that closes mid-typing cannot leave the indicator stuck
  /// on somebody else's screen. Call this repeatedly while the user types.
  /// Over-sending is safe - the server rate-limits it and drops the excess
  /// silently rather than erroring or closing the socket.
  void typing(String channelId) => _channel.sink
      .add(jsonEncode({'type': 'typing', 'channel_id': channelId}));

  Future<void> close() => _channel.sink.close();
}

/// The socket could not be established or the handshake was rejected.
class EventConnectionRefused implements Exception {
  const EventConnectionRefused(this.reason);

  final String reason;

  @override
  String toString() => 'EventConnectionRefused: $reason';
}
