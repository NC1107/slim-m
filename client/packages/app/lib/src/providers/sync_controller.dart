// SPDX-License-Identifier: Apache-2.0
/// Keeps the local store current: catch-up, then live events.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_data/data.dart';

import 'dms.dart';
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
        unawaited(_endSession());
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

  /// The in-flight refresh from a live event naming an unknown channel, so a
  /// burst of such frames shares one round trip rather than firing one each.
  Future<void>? _channelRefresh;

  /// Every event this session receives, broadcast to whoever else wants one
  /// (presence, typing, reactions, pins, polls): a second, independent
  /// listener on top of the store-application switch below, so those
  /// features do not need their own socket connection or their own copy of
  /// the reconnect/backoff logic. Outlives any one connection: created once
  /// here, never recreated by [_teardown] or a reconnect.
  final _liveEvents = StreamController<ServerEvent>.broadcast();

  /// Every event this session receives, for anything that wants to react to
  /// one live rather than re-deriving it from the local store.
  Stream<ServerEvent> get liveEvents => _liveEvents.stream;

  /// Tells the server this user is typing in a channel.
  ///
  /// A no-op while the socket is down: typing is ephemeral, so a refresh
  /// missed during a reconnect is worth nothing and must never surface as an
  /// error to the person typing.
  void notifyTyping(String channelId) => _connection?.typing(channelId);

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

  /// Refreshes both channel listings the server keeps apart: the
  /// deployment's own channels, and the caller's DM conversations (which
  /// `GET /channels` deliberately excludes). Both land in the same local
  /// channel table under the same shape, so everything downstream (the
  /// rail, sync cursors, read state) treats a DM exactly like any other
  /// channel once it is here.
  ///
  /// Also hydrates each channel's read marker from the server. `ScopeDelta`
  /// carries no read state, so `/sync` can never do this, and
  /// `MessageStore.clear()` wipes the local marker on every sign-out; without
  /// this, a reinstall or a second device shows every channel unread
  /// forever, however recently it was actually read elsewhere.
  Future<void> _refreshChannels(SlimmApi api, MessageStore store) async {
    final channels = await api.listChannels();
    final dms = await api.listDirectMessages();
    final all = [...channels, ...dms.map(channelFromDm)];
    await store.upsertChannels(all);

    // Per channel, not bundled with the listing above: the server does not
    // hand back read state for a list of channels in one call. One channel's
    // read state failing to fetch must not stop the rest from hydrating.
    await Future.wait(
      all.map((channel) async {
        try {
          final read = await api.readState(channel.id);
          await store.setReadMarker(channel.id, read.lastReadSeq);
        } on ApiException {
          // Best-effort: the next refresh (reconnect, or the next start())
          // tries again, and until then the channel just reads as unread.
        }
      }),
    );
  }

  /// [_refreshChannels], but a concurrent caller joins the one already
  /// running instead of starting a second. See [_channelRefresh].
  Future<void> _refreshChannelsOnce(SlimmApi api, MessageStore store) {
    return _channelRefresh ??= _refreshChannels(api, store).whenComplete(() {
      _channelRefresh = null;
    });
  }

  /// Catches every known scope up in one request, applying deltas in order.
  Future<void> _catchUp(SlimmApi api, MessageStore store) async {
    final cursors = await store.allCursors();
    if (cursors.isEmpty) return;

    final deltas = await api.sync(cursors);
    var more = false;
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
      more = more || delta.hasMore;
    }

    // At most one continuation per round, however many scopes are behind.
    // Scheduling inside the loop meant every backlogged channel started its own
    // full-cursor resync, so ten of them fanned out into ten overlapping /sync
    // calls that each re-requested all ten scopes. Next tick rather than
    // straight through, so a long backlog does not block the first paint.
    if (more) {
      unawaited(
        Future<void>.delayed(Duration.zero, () => _catchUp(api, store)),
      );
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
        // Broadcast first and unconditionally: a listener that only cares
        // about, say, ReactionsChanged must not depend on this switch ever
        // learning about that event type.
        _liveEvents.add(event);
        await _applyServerEvent(api, store, event);
      },
      onError: (_) => _onDropped(),
      onDone: _onDropped,
    );
  }

  /// How one frame from the socket changes local state. A method of its own
  /// so [applyServerEventForTest] can drive it without a real socket.
  Future<void> _applyServerEvent(
    SlimmApi api,
    MessageStore store,
    ServerEvent event,
  ) async {
    switch (event) {
      case MessageCreated(:final message):
      case MessageEdited(:final message):
        // A DM's first message is a channel this client has never
        // fetched; materialise it first or applyMessage lands silently.
        if (!await store.hasChannel(message.channelId)) {
          await _refreshChannelsOnce(api, store);
        }
        await store.applyMessage(message);
      case MessageDeleted(:final messageId):
        // Closes a real gap: this switch previously had no case for a
        // delete at all, so a message removed by another user (or this
        // account's own delete looping back) never left the local store
        // and stayed visible until the next full resync.
        await store.discard(messageId);
      case ErrorEvent(:final needsResync) when needsResync:
        // The connection fell behind and the server closed it; a restart
        // re-runs catch-up, which is exactly the recovery.
        unawaited(start());
      case _:
        break;
    }
  }

  /// Applies one live event the way [_attach]'s listener would, without
  /// needing a real socket. For tests only.
  @visibleForTesting
  Future<void> applyServerEventForTest(ServerEvent event) async {
    final api = _ref.read(apiProvider);
    final store = await _ref.read(storeProvider.future);
    await _applyServerEvent(api, store, event);
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
  ///
  /// Deliberately does not touch the local database. The sign-out and delete
  /// handlers await this before their request goes out, and a delete that
  /// fails keeps the session on purpose; wiping here would throw the cache
  /// away for an account the user is still signed into. The wipe belongs to
  /// the session actually ending, which is [_endSession].
  Future<void> stop() async {
    _retry?.cancel();
    await _teardown();
    state = SyncStatus.offline;
  }

  /// The session ended, whichever way: a sign-out, an account deletion that
  /// went through, or a refresh the server rejected.
  ///
  /// The local database is one file for the whole app, not one per account or
  /// per server, so whatever survives here is read by whoever signs in next on
  /// this device: the previous account's channel list and message text,
  /// visible before any new sync could correct it. Phones get handed over and
  /// desktops are shared, so the cache goes the moment it stops belonging to
  /// the person holding the device.
  ///
  /// Best-effort. A database that will not open or clear must not leave
  /// somebody stuck signed in, so the failure is swallowed; the session is
  /// already gone by the time this runs.
  Future<void> _endSession() async {
    await stop();
    try {
      final store = await _ref.read(storeProvider.future);
      await store.clear();
    } catch (_) {
      // Nothing useful to do here, and the sign-out itself already succeeded.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sessionSubscription.cancel());
    _retry?.cancel();
    unawaited(_teardown());
    unawaited(_liveEvents.close());
    super.dispose();
  }
}

final syncControllerProvider =
    StateNotifierProvider<SyncController, SyncStatus>(
      (ref) => SyncController(ref),
    );
