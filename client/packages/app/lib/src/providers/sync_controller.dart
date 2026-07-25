// SPDX-License-Identifier: Apache-2.0
/// Keeps the local store current: catch-up, then live events.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_data/data.dart';

import 'providers.dart';

/// How the connection is doing, for the UI to show honestly rather than
/// pretending everything is fine while messages silently stop arriving.
enum SyncStatus { offline, connecting, live }

/// Drives synchronisation.
///
/// The order matters and is the whole point: on every (re)connect it catches up
/// over REST first, then attaches the live socket. Attaching first would leave a
/// gap between the last message the client holds and the first one the socket
/// delivers, and nothing would ever notice.
///
/// The socket is only a delivery route for things already written durably, so
/// losing it is never data loss, just staleness, and reconnecting re-runs the
/// same catch-up.
///
/// Session-driven: starts the moment a session begins, whether that is a
/// fresh sign-in or one restored from the last launch, and stops the moment
/// one ends, whether that is a sign-out or a refresh token the server
/// rejected. Only that 0-to-1 or 1-to-0 edge matters, not every token
/// rotation in between, so a routine access-token refresh mid-session does
/// not drop and reconnect the socket for no reason.
class SyncController extends StateNotifier<SyncStatus> {
  SyncController(this._ref) : super(SyncStatus.offline) {
    final session = _ref.read(sessionProvider);
    // Subscribe before reading the current value, so a change landing between
    // the two is never missed.
    _sessionSubscription = session.changes.listen((tokens) {
      final signedIn = tokens != null;
      if (signedIn == _lastSignedIn) return;
      _lastSignedIn = signedIn;
      if (signedIn) {
        unawaited(start());
      } else {
        unawaited(stop());
      }
    });
    _lastSignedIn = session.isSignedIn;
    if (_lastSignedIn) unawaited(start());
  }

  final Ref _ref;
  late final StreamSubscription<TokenPair?> _sessionSubscription;
  bool _lastSignedIn = false;
  EventConnection? _connection;
  StreamSubscription<ServerEvent>? _events;
  Timer? _retry;
  bool _disposed = false;
  int _attempt = 0;

  /// Starts, or restarts, synchronisation. Safe to call repeatedly.
  Future<void> start() async {
    if (_disposed) return;
    _retry?.cancel();
    await _teardown();
    state = SyncStatus.connecting;

    try {
      final api = _ref.read(apiProvider);
      final store = await _ref.read(storeProvider.future);

      await _refreshChannels(api, store);
      await _catchUp(api, store);
      await _attach(api, store);

      _attempt = 0;
      state = SyncStatus.live;
    } catch (_) {
      // Any failure here is a connectivity or auth problem, and both are
      // handled the same way: show offline and try again with backoff.
      state = SyncStatus.offline;
      _scheduleRetry();
    }
  }

  Future<void> _refreshChannels(SlimmApi api, MessageStore store) async {
    final channels = await api.listChannels();
    await store.upsertChannels(channels);
  }

  /// Catches every known scope up in one request, applying deltas in order.
  Future<void> _catchUp(SlimmApi api, MessageStore store) async {
    final cursors = await store.allCursors();
    if (cursors.isEmpty) return;

    final deltas = await api.sync(cursors);
    for (final delta in deltas) {
      if (delta.reset) {
        // The server says the gap is too large to stream: local state for this
        // scope cannot be trusted, so drop it and refetch from the start.
        await store.resetChannel(delta.channelId);
        final fresh = await api.listMessages(delta.channelId, limit: 50);
        await store.applyMessages(fresh);
        continue;
      }
      await store.applyMessages(delta.messages);
      if (delta.hasMore) {
        // More remains than one response could carry; go again next tick rather
        // than looping here and blocking the first paint.
        unawaited(
            Future<void>.delayed(Duration.zero, () => _catchUp(api, store)));
      }
    }
  }

  /// Attaches the live socket. Its closure schedules a full restart, so the
  /// next connection catches up before trusting live events again.
  Future<void> _attach(SlimmApi api, MessageStore store) async {
    final ticket = await api.webSocketTicket();
    final connection = await EventConnection.connect(
      url: api.webSocketUrl,
      ticket: ticket.ticket,
    );
    _connection = connection;

    _events = connection.events.listen(
      (event) async {
        switch (event) {
          case MessageCreated(:final message):
          case MessageEdited(:final message):
            await store.applyMessage(message);
          case ErrorEvent(:final needsResync) when needsResync:
            // The connection fell behind and the server closed it; a restart
            // re-runs catch-up, which is exactly the recovery.
            unawaited(start());
          case _:
            break;
        }
      },
      onError: (_) => _onDropped(),
      onDone: _onDropped,
    );
  }

  void _onDropped() {
    if (_disposed || state == SyncStatus.connecting) return;
    state = SyncStatus.offline;
    _scheduleRetry();
  }

  /// Backs off, and jitters, so a server restart does not bring every client
  /// back in the same instant.
  void _scheduleRetry() {
    if (_disposed) return;
    _attempt = (_attempt + 1).clamp(1, 6);
    final seconds = (1 << (_attempt - 1)).clamp(1, 32);
    final jitter = Duration(milliseconds: DateTime.now().microsecond % 1000);
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds) + jitter, start);
  }

  Future<void> _teardown() async {
    await _events?.cancel();
    _events = null;
    await _connection?.close();
    _connection = null;
  }

  /// Stops synchronising, for sign-out.
  Future<void> stop() async {
    _retry?.cancel();
    await _teardown();
    state = SyncStatus.offline;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sessionSubscription.cancel());
    _retry?.cancel();
    unawaited(_teardown());
    super.dispose();
  }
}

final syncControllerProvider =
    StateNotifierProvider<SyncController, SyncStatus>(
        (ref) => SyncController(ref));
