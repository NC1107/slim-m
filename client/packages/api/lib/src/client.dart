// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The REST client for the slim-m API.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exceptions.dart';
import 'models.dart';

// One tag per file. `part`, not separate libraries: they all reach the
// private transport, and Dart privacy is library-scoped, not file-scoped.
part 'client_admin.dart';
part 'client_attachments.dart';
part 'client_auth.dart';
part 'client_channel_admin.dart';
part 'client_canvas.dart';
part 'client_dms.dart';
part 'client_emoji.dart';
part 'client_gifs.dart';
part 'client_messages.dart';
part 'client_moderation.dart';
part 'client_presence.dart';
part 'client_push.dart';
part 'client_roles.dart';
part 'client_space.dart';
part 'client_threads.dart';
part 'client_transport.dart';
part 'client_users.dart';
part 'client_voice.dart';

/// Holds the current session and hands out the access token.
///
/// Kept separate from the client so storage (secure storage on device, memory
/// in tests) can vary without the client knowing, and so a refresh performed by
/// one call is visible to every other.
class SessionStore {
  SessionStore({TokenPair? tokens, Future<void> Function(TokenPair?)? onChange})
      : _tokens = tokens,
        _onChange = onChange;

  TokenPair? _tokens;
  final Future<void> Function(TokenPair?)? _onChange;

  /// Chains every [_onChange] call behind the last, so a slow write cannot
  /// finish after a faster later one and leave a stale value stored: without
  /// it, a rotation overtaking the sign-out that superseded it persists a
  /// token for a session that has ended.
  Future<void> _pending = Future<void>.value();

  final _changes = StreamController<TokenPair?>.broadcast();

  /// Emits whenever the session changes, including null when it ends.
  Stream<TokenPair?> get changes => _changes.stream;

  TokenPair? get tokens => _tokens;
  bool get isSignedIn => _tokens != null;

  /// In-memory and announced immediately, same as always: nothing here
  /// depends on [_onChange], so a slow or hung persist layer never delays a
  /// live session from working. [settled] is the separate, explicit way to
  /// wait for durability.
  void set(TokenPair? tokens) {
    _tokens = tokens;
    _changes.add(tokens);
    if (_onChange case final onChange?) {
      // Caught, or an uncaught error here would poison every later onChange (see FileKeyStore).
      _pending = _pending.then((_) => onChange(tokens)).catchError((_) {});
    }
  }

  void clear() => set(null);

  /// Resolves once every [_onChange] triggered by [set] so far has settled,
  /// whether it succeeded or failed.
  ///
  /// [SlimmApiAuth._refreshOnce] awaits this after rotating: the server has
  /// already spent the old refresh token by the time a new one comes back, so
  /// a process death between that response and the new token reaching disk
  /// replays the old, now-spent one on the next launch and gets read as
  /// reuse. Awaiting this closes that window down to the write itself.
  ///
  /// It never completes before the write does, so anything awaiting it
  /// inherits the key store's worst case and must bound its own wait. A
  /// failed write is fine and resolves normally; only a hung one is a
  /// problem, and every 401 retry funnels through that same rotation.
  Future<void> get settled => _pending;

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
    required this.baseUrl,
    SessionStore? session,
    http.Client? httpClient,
  })  : session = session ?? SessionStore(),
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

  // --- System ---

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

  // --- Channels ---

  /// The caller's visible channels. A plain array, unchanged since before
  /// channel categories: the wire is additive-only, and reshaping this
  /// response would break every client that has not updated yet. The
  /// category list is [SlimmApiChannelAdmin.listCategories] instead.
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

  // --- Read state and sync ---

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

  // --- Devices, blocking, private notes, and reporting ---

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

  /// The caller's own private note about [userId], or an all-null [UserNote]
  /// if they have not left one. Never the subject's view of anything: this
  /// can only ever answer for the caller's own note. A subject with nothing
  /// live to answer for - never registered, or since deleted - answers 404,
  /// exactly like [getUser].
  Future<UserNote> getUserNote(String userId) async {
    final json = await _send('GET', '/users/$userId/note');
    return UserNote.fromJson(json as Map<String, dynamic>);
  }

  /// Sets the caller's private note about [userId]. An empty or
  /// whitespace-only [body] clears it rather than storing a blank one, the
  /// same convention [updateMe]'s status text follows.
  Future<UserNote> setUserNote(String userId, String body) async {
    final json = await _send(
      'PUT',
      '/users/$userId/note',
      body: {'body': body},
    );
    return UserNote.fromJson(json as Map<String, dynamic>);
  }

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
}
