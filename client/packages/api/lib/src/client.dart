// SPDX-License-Identifier: Apache-2.0
/// The REST client for the slim-m API.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exceptions.dart';
import 'models.dart';

// Split into companion files purely to stay under this repo's line budget.
// Each is a `part of` this library rather than its own, since every one of
// them needs the private `_send` helper below and privacy in Dart is scoped
// to the library, not the file.
part 'client_admin.dart';
part 'client_attachments.dart';
part 'client_channel_admin.dart';
part 'client_dms.dart';
part 'client_messages.dart';
part 'client_moderation.dart';
part 'client_presence.dart';
part 'client_roles.dart';
part 'client_users.dart';

/// Holds the current session and hands out the access token.
///
/// Kept separate from the client so storage (secure storage on device, memory
/// in tests) can vary without the client knowing, and so a refresh performed by
/// one call is visible to every other.
class SessionStore {
  SessionStore({TokenPair? tokens}) : _tokens = tokens;

  TokenPair? _tokens;

  final _changes = StreamController<TokenPair?>.broadcast();

  /// Emits whenever the session changes, including null when it ends.
  Stream<TokenPair?> get changes => _changes.stream;

  TokenPair? get tokens => _tokens;
  bool get isSignedIn => _tokens != null;

  void set(TokenPair? tokens) {
    _tokens = tokens;
    _changes.add(tokens);
  }

  void clear() => set(null);

  Future<void> dispose() => _changes.close();
}

/// A typed client for one server.
///
/// Refresh is handled here rather than by callers: when a request comes back
/// unauthorized and a refresh token is held, the client rotates once and
/// replays the request. Concurrent calls share a single in-flight refresh, so a
/// burst of expired requests does not spend the single-use refresh token more
/// than once (which the server would read as reuse and revoke the session).
class SlimmApi {
  SlimmApi({
    required Uri baseUrl,
    SessionStore? session,
    http.Client? httpClient,
  })  : baseUrl = baseUrl,
        session = session ?? SessionStore(),
        _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final SessionStore session;
  final http.Client _http;

  Future<TokenPair>? _refreshInFlight;

  /// The WebSocket URL for this server, with the scheme mapped from http(s).
  Uri get webSocketUrl {
    final scheme = baseUrl.scheme == 'https' ? 'wss' : 'ws';
    return baseUrl.replace(scheme: scheme, path: '/ws');
  }

  void close() => _http.close();

  // ---------------------------------------------------------------------------
  // System
  // ---------------------------------------------------------------------------

  Future<Version> version() async {
    final json = await _send('GET', '/version', authenticated: false);
    return Version.fromJson(json as Map<String, dynamic>);
  }

  Future<bool> health() async {
    try {
      final response = await _http.get(baseUrl.replace(path: '/healthz'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  /// Creates an account and signs in. On an unclaimed deployment the first
  /// account also becomes its administrator.
  ///
  /// Once a deployment has been claimed, joining it takes an [inviteCode]: the
  /// server spends the code in the same transaction that creates the account,
  /// so there is no separate redeem step to get wrong, and a rejected signup
  /// leaves both the username and the code untouched.
  Future<TokenPair> register({
    required String username,
    required String displayName,
    required String password,
    required String deviceName,
    String? inviteCode,
  }) async {
    final json = await _send(
      'POST',
      '/auth/register',
      authenticated: false,
      body: {
        'username': username,
        'display_name': displayName,
        'password': password,
        'device_name': deviceName,
        if (inviteCode != null) 'invite_code': inviteCode,
      },
    );
    final tokens = TokenPair.fromJson(json as Map<String, dynamic>);
    session.set(tokens);
    return tokens;
  }

  Future<TokenPair> login({
    required String username,
    required String password,
    required String deviceName,
  }) async {
    final json = await _send(
      'POST',
      '/auth/login',
      authenticated: false,
      body: {
        'username': username,
        'password': password,
        'device_name': deviceName,
      },
    );
    final tokens = TokenPair.fromJson(json as Map<String, dynamic>);
    session.set(tokens);
    return tokens;
  }

  /// Rotates the session. Callers rarely need this directly; an unauthorized
  /// response triggers it automatically.
  Future<TokenPair> refresh() {
    // Share one in-flight rotation: the refresh token is single-use, so two
    // concurrent rotations would spend it twice and the server would treat the
    // second as a leak and revoke the session.
    return _refreshInFlight ??= _refreshOnce().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<TokenPair> _refreshOnce() async {
    final current = session.tokens;
    if (current == null) {
      throw const UnauthorizedException('not signed in');
    }
    try {
      final json = await _send(
        'POST',
        '/auth/refresh',
        authenticated: false,
        body: {'refresh_token': current.refreshToken},
      );
      final tokens = TokenPair.fromJson(json as Map<String, dynamic>);
      session.set(tokens);
      return tokens;
    } on UnauthorizedException {
      // The refresh token is spent, revoked, or the session is gone; the only
      // move left is a fresh sign-in.
      session.clear();
      rethrow;
    }
  }

  /// Mints a single-use ticket for opening a WebSocket.
  Future<Ticket> webSocketTicket() async {
    final json = await _send('POST', '/auth/ws-ticket');
    return Ticket.fromJson(json as Map<String, dynamic>);
  }

  /// Ends this session. Any live WebSocket on it is closed by the server.
  Future<void> logout() async {
    await _send('POST', '/auth/logout', expectNoContent: true);
    session.clear();
  }

  /// Deletes the signed-in account. Irreversible.
  Future<void> deleteAccount() async {
    await _send('DELETE', '/account', expectNoContent: true);
    session.clear();
  }

  // ---------------------------------------------------------------------------
  // Channels
  // ---------------------------------------------------------------------------

  Future<List<Channel>> listChannels() async {
    final json = await _send('GET', '/channels');
    return (json as List<dynamic>)
        .map((c) => Channel.fromJson(c as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Creates a channel. Requires the manage-channels permission.
  Future<Channel> createChannel(
      {required String name, String kind = 'text'}) async {
    final json = await _send(
      'POST',
      '/channels',
      body: {'name': name, 'kind': kind},
    );
    return Channel.fromJson(json as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

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
  /// SEND_MESSAGES.
  Future<Message> sendMessage({
    required String channelId,
    required String id,
    required String content,
    List<String> attachmentIds = const [],
  }) async {
    final json = await _send(
      'POST',
      '/channels/$channelId/messages',
      body: {
        'id': id,
        'content': content,
        if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
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

  // ---------------------------------------------------------------------------
  // Read state and sync
  // ---------------------------------------------------------------------------

  Future<ReadState> readState(String channelId) async {
    final json = await _send('GET', '/channels/$channelId/read');
    return ReadState.fromJson(json as Map<String, dynamic>);
  }

  /// Advances the read marker. Monotonic: a lower seq is ignored by the server.
  Future<ReadState> markRead(
      {required String channelId, required int seq}) async {
    final json = await _send(
      'PUT',
      '/channels/$channelId/read',
      body: {'seq': seq},
    );
    return ReadState.fromJson(json as Map<String, dynamic>);
  }

  /// Catches several scopes up in one request. Scopes the caller cannot view
  /// are omitted from the response rather than refused.
  Future<List<ScopeDelta>> sync(List<ScopeCursor> scopes) async {
    final json = await _send(
      'POST',
      '/sync',
      body: {'scopes': scopes.map((s) => s.toJson()).toList(growable: false)},
    );
    final map = json as Map<String, dynamic>;
    return (map['scopes'] as List<dynamic>)
        .map((s) => ScopeDelta.fromJson(s as Map<String, dynamic>))
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Devices, blocking, and reporting
  // ---------------------------------------------------------------------------

  /// The account's own devices, with the current one flagged.
  Future<List<Device>> listDevices() async {
    final json = await _send('GET', '/devices');
    return (json as List<dynamic>)
        .map((d) => Device.fromJson(d as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Signs a device out. Its tokens die immediately and its socket is closed.
  Future<void> removeDevice(String deviceId) =>
      _send('DELETE', '/devices/$deviceId', expectNoContent: true);

  /// The users this account has blocked. Blocking is a client-side view filter,
  /// so the caller applies this rather than the server stripping messages.
  Future<List<String>> listBlocks() async {
    final json = await _send('GET', '/blocks');
    return (json as List<dynamic>).cast<String>();
  }

  /// Blocks a user. Idempotent, and the blocked user is never told.
  Future<void> blockUser(String userId) =>
      _send('POST', '/blocks/$userId', expectNoContent: true);

  Future<void> unblockUser(String userId) =>
      _send('DELETE', '/blocks/$userId', expectNoContent: true);

  /// Whether an invite code can be used, and if so, a preview of what it
  /// joins. Unauthenticated, because the person holding a code does not have
  /// an account yet.
  Future<InviteCheck> checkInvite(String code) async {
    final json = await _send(
      'GET',
      '/invites/$code/check',
      authenticated: false,
    );
    return InviteCheck.fromJson(json as Map<String, dynamic>);
  }

  /// Spends an invite for the signed-in account.
  Future<void> redeemInvite(String code) =>
      _send('POST', '/invites/$code/redeem', expectNoContent: true);

  /// Mints a join token for a channel's voice room.
  ///
  /// Throws [NotImplementedException] when the deployment has no SFU, which is
  /// a supported way to run text-only rather than a fault, so a caller should
  /// hide voice rather than retry.
  Future<VoiceToken> voiceToken(String channelId) async {
    final json = await _send('POST', '/channels/$channelId/voice/token');
    return VoiceToken.fromJson(json as Map<String, dynamic>);
  }

  /// Files a report for a human to review.
  Future<String> report({
    required ReportSubject subject,
    required String subjectId,
    required String reason,
  }) async {
    final json = await _send(
      'POST',
      '/reports',
      body: {
        'subject_kind': subject.wire,
        'subject_id': subjectId,
        'reason': reason,
      },
    );
    return (json as Map<String, dynamic>)['id'] as String;
  }

  // ---------------------------------------------------------------------------
  // Push
  // ---------------------------------------------------------------------------

  /// Registers, or replaces, this device's push registration. The server seals
  /// a content-free envelope to [pushPublicKey]; only this device holds the
  /// matching private key, so a device that never registers one gets no push.
  Future<void> registerPush({
    required String platform,
    required String pushToken,
    String? voipPushToken,
    required String pushPublicKey,
  }) =>
      _send(
        'PUT',
        '/push',
        body: {
          'platform': platform,
          'push_token': pushToken,
          'voip_push_token': voipPushToken,
          'push_public_key': pushPublicKey,
        },
        expectNoContent: true,
      );

  /// Clears this device's push registration.
  Future<void> unregisterPush() =>
      _send('DELETE', '/push', expectNoContent: true);

  /// Reports this device's app lifecycle state. Push is triggered from this
  /// self-reported state rather than WebSocket presence, because a suspended
  /// but still-connected socket is not proof the app can show a notification.
  Future<void> reportPushLifecycle({required String state}) => _send(
        'PUT',
        '/push/lifecycle',
        body: {'state': state},
        expectNoContent: true,
      );

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    List<int>? bytes,
    Map<String, String>? query,
    bool authenticated = true,
    bool expectNoContent = false,
    bool isRetry = false,
  }) async {
    final uri = baseUrl.replace(path: path, queryParameters: query);
    final request = http.Request(method, uri);
    if (bytes != null) {
      // An upload (an attachment or an avatar): the request body is the raw
      // bytes, never JSON, though the response below still is.
      request.headers['content-type'] = 'application/octet-stream';
      request.bodyBytes = bytes;
    } else if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (authenticated) {
      final token = session.tokens?.accessToken;
      if (token == null) {
        throw const UnauthorizedException('not signed in');
      }
      request.headers['authorization'] = 'Bearer $token';
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } catch (e) {
      throw TransportException('$method $path failed: $e');
    }

    // One automatic rotation, then replay. Only for authenticated calls, and
    // never twice for the same request.
    if (response.statusCode == 401 &&
        authenticated &&
        !isRetry &&
        session.tokens != null) {
      await refresh();
      return _send(
        method,
        path,
        body: body,
        bytes: bytes,
        query: query,
        authenticated: authenticated,
        expectNoContent: expectNoContent,
        isRetry: true,
      );
    }

    if (response.statusCode == 204 ||
        (expectNoContent && response.statusCode < 300)) {
      return null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      try {
        return jsonDecode(response.body) as Object;
      } catch (e) {
        throw TransportException(
            'could not decode the reply to $method $path: $e');
      }
    }
    throw _errorFor(response);
  }

  /// Like [_send], for an authenticated GET whose response is raw bytes
  /// rather than JSON (an attachment or an avatar fetch): the same one-shot
  /// refresh-and-retry and error mapping, without a JSON decode that would
  /// only fail on a body that was never JSON to begin with.
  Future<FetchedBytes> _fetchBytes(String path, {bool isRetry = false}) async {
    final uri = baseUrl.replace(path: path);
    final request = http.Request('GET', uri);
    final token = session.tokens?.accessToken;
    if (token == null) {
      throw const UnauthorizedException('not signed in');
    }
    request.headers['authorization'] = 'Bearer $token';

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } catch (e) {
      throw TransportException('GET $path failed: $e');
    }

    if (response.statusCode == 401 && !isRetry && session.tokens != null) {
      await refresh();
      return _fetchBytes(path, isRetry: true);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return FetchedBytes(
        bytes: response.bodyBytes,
        contentType:
            response.headers['content-type'] ?? 'application/octet-stream',
      );
    }
    throw _errorFor(response);
  }

  ApiException _errorFor(http.Response response) {
    var reason = 'request failed';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['error'] is String) {
        reason = decoded['error'] as String;
      }
    } catch (_) {
      // A non-JSON body is not itself an error worth surfacing; the status is.
    }
    return switch (response.statusCode) {
      400 => BadRequestException(reason),
      401 => UnauthorizedException(reason),
      403 => ForbiddenException(reason),
      404 => NotFoundException(reason),
      409 => ConflictException(reason),
      429 => RateLimitedException(reason),
      501 => NotConfiguredException(reason),
      503 => UnavailableException(reason),
      _ => ServerException(reason, response.statusCode),
    };
  }
}
