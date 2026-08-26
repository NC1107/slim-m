// SPDX-License-Identifier: Apache-2.0
/// Keeps the local store current: catch-up, then live events.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_data/data.dart';

import 'channel_history.dart';
import 'channel_refresher.dart';
import 'dm_call_activity.dart';
import 'failed_send_retry.dart';
import 'message_ops_sync.dart';
import 'op_adjacency.dart';
import 'message_extras.dart';
import 'providers.dart';
import 'user_profiles.dart';

/// How the connection is doing, for the UI to show honestly rather than
/// pretending everything is fine while messages silently stop arriving.
enum SyncStatus { offline, connecting, live }

/// Whether this session's first catch-up round has completed, independent of
/// whether the live socket then attaches.
///
/// Read by the transcript ([MessageTranscript.historyKnown]) so an optimistic
/// send made before the very first catch-up lands does not briefly anchor a
/// day divider it does not really own - see `isNewDay`'s own doc comment.
/// Deliberately not folded into [SyncStatus]: that flips back to
/// `connecting`/`offline` on every later reconnect, while this only ever
/// needs to become true once and stay true for the session, since a
/// reconnect's catch-up can only confirm history already known, never
/// un-confirm it.
final initialSyncCompleteProvider = StateProvider<bool>((ref) => false);

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
    // Subscribe before reading the current value, so a change landing between the two is never missed.
    _sessionSubscription = session.changes.listen((tokens) {
      final signedIn = tokens != null;
      if (signedIn == _lastSignedIn) return;
      _lastSignedIn = signedIn;
      if (signedIn) {
        // A fresh sign-in reuses this process, so a stale cached identity must not survive it.
        _ref.invalidate(meProvider);
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
  final _channelRefresher = ChannelRefresher();

  /// Bumped by every [stop], every fresh [start] and [dispose], so a run
  /// superseded mid-flight (a sign-out landing during catch-up, or a second
  /// start racing the first) notices at its next checkpoint rather than
  /// finishing and writing stale data into a store a newer run already
  /// cleared. Every await in this class that is followed by a write has to
  /// re-check it, including the ones inside [ChannelRefresher], which is why
  /// that takes the predicate rather than being trusted to finish quickly.
  int _generation = 0;

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

  /// Tells the server this user's pointer moved on a channel's canvas.
  ///
  /// The same no-op-while-down shape as [notifyTyping]: a cursor position
  /// missed during a reconnect is worth nothing and must never surface as an
  /// error to whoever is drawing.
  void notifyCanvasCursor(String channelId, double x, double y) =>
      _connection?.canvasCursor(channelId, x, y);

  /// Tells the server this user's in-flight stroke gained points, or ended.
  ///
  /// The same no-op-while-down shape as [notifyCanvasCursor]: a preview
  /// frame missed during a reconnect is worth nothing and must never surface
  /// as an error to whoever is drawing.
  void notifyCanvasStrokePreview(
    String channelId,
    String objectId,
    List<double> points, {
    bool ended = false,
  }) => _connection?.canvasStrokePreview(
    channelId,
    objectId,
    points,
    ended: ended,
  );

  /// Starts, or restarts, synchronisation. Safe to call repeatedly: a call
  /// superseded by a later [start] or a [stop] before it reaches a given
  /// checkpoint abandons itself there rather than finishing against a
  /// session, or a store, that has since moved on.
  Future<void> start() async {
    if (_disposed) return;
    final generation = ++_generation;
    _retry?.cancel();
    await _teardown();
    if (generation != _generation) return;
    state = SyncStatus.connecting;
    // No cursor over a rename to catch up from, so forget every cached name on a fresh connect.
    _ref.read(batchProfilesControllerProvider.notifier).clear();
    // A missed voice.activity frame while disconnected is otherwise unrecoverable.
    _ref.read(dmCallActivityProvider.notifier).clear();

    try {
      final api = _ref.read(apiProvider);
      final store = await _ref.read(storeProvider.future);
      if (generation != _generation) return;

      await _channelRefresher.refresh(
        api,
        store,
        isCurrent: () => generation == _generation,
      );
      if (generation != _generation) return;
      await _catchUp(generation, api, store);
      if (generation != _generation) return;
      _ref.read(initialSyncCompleteProvider.notifier).state = true;
      await _attach(generation, api, store);
      if (generation != _generation) return;

      _attempt = 0;
      state = SyncStatus.live;
      // A DB read failure here must not read as this connect itself having failed; retryMessage's own catch already covers a failed resend.
      unawaited(
        retryFailedSends(
          _ref.read,
          store,
          isCurrent: () => generation == _generation,
        ).catchError((_) {}),
      );
    } catch (_) {
      if (generation != _generation) return;
      // A connectivity or auth problem here: both mean show offline and retry with backoff.
      state = SyncStatus.offline;
      _scheduleRetry();
    }
  }

  /// Catches every known scope up in one request, applying deltas in order.
  ///
  /// [generation] is this call's [start], checked before every write: a
  /// sign-out landing while the network round trip above is already in
  /// flight must not let its answer, arriving after the store has been
  /// cleared for the account signing out, write into it anyway.
  Future<void> _catchUp(
    int generation,
    SlimmApi api,
    MessageStore store,
  ) async {
    bool isCurrent() => generation == _generation;
    final cursors = await store.allCursors();
    if (cursors.isEmpty) return;

    final deltas = await api.sync(cursors);
    if (generation != _generation) return;
    var more = false;
    for (final delta in deltas) {
      if (generation != _generation) return;
      if (delta.reset) {
        // Either cursor is too far behind to stream: local state is untrusted.
        await _resetScope(generation, api, store, delta.channelId);
        if (!isCurrent()) return;
        continue;
      }
      await store.applyMessages(delta.messages);

      // After the messages: an edit cannot precede the message it names.
      if (delta.opLatestSeq != null) {
        final cursor = await store.opCursorFor(delta.channelId);
        if (!isCurrent()) return;
        if (cursor == null) {
          // Adopt the head; asking from zero replays every edit ever made.
          await store.setOpCursor(delta.channelId, delta.opLatestSeq);
        } else if (delta.ops.isNotEmpty) {
          final outcome = await applyOps(store, delta.channelId, delta.ops);
          if (!isCurrent()) return;
          if (outcome == OpsOutcome.needsReset) {
            await _resetScope(generation, api, store, delta.channelId);
            continue;
          }
        }
      }

      more = more || delta.hasMore || delta.opsHasMore;
    }

    /// At most one continuation per round, however many scopes are behind.
    /// Scheduling inside the loop meant every backlogged channel started its own
    /// full-cursor resync, so ten of them fanned out into ten overlapping /sync
    /// calls that each re-requested all ten scopes. Next tick rather than
    /// straight through, so a long backlog does not block the first paint.
    if (more) {
      // This continuation runs outside start()'s try/catch, so a failure in a
      // later backlog round (a 429 from the server's own limiter, a transient
      // 5xx) was an unhandled async error: the catch-up stopped silently while
      // the socket kept the status at live, leaving a permanent gap. Routed to
      // the same drop path a lost socket takes, which reconnects and catches
      // up fresh.
      unawaited(
        Future<void>.delayed(
          Duration.zero,
          () => _catchUp(generation, api, store),
        ).catchError((_) {
          if (!_disposed && generation == _generation) _onDropped();
        }),
      );
    }
  }

  /// Drops a scope's cached messages and both its cursors, then refetches the
  /// newest page.
  ///
  /// [MessageStore.resetChannel] clears the op cursor to null as well as
  /// rewinding the message one, so the next catch-up adopts a fresh head
  /// rather than asking from a seq the server may have swept past.
  Future<void> _resetScope(
    int generation,
    SlimmApi api,
    MessageStore store,
    String channelId,
  ) async {
    await store.resetChannel(channelId);
    final fresh = await api.listMessages(channelId, limit: 50);
    if (generation != _generation) return;
    await store.applyMessages(fresh);
  }

  /// Runs one catch-up round against the current generation.
  ///
  /// The gap detector's entry point: a live op that is not exactly the next
  /// one schedules this rather than applying a payload it cannot place.
  Future<void> reconcile() async {
    if (_disposed) return;
    final generation = _generation;
    final api = _ref.read(apiProvider);
    final store = await _ref.read(storeProvider.future);
    if (generation != _generation) return;
    await _catchUp(generation, api, store);
  }

  /// Attaches the live socket. Its closure schedules a full restart, so the
  /// next connection catches up before trusting live events again.
  ///
  /// [generation] is checked after the ticket mint and the connect, because
  /// both are network round trips: a [stop] landing inside either used to
  /// return from [start] having already assigned a socket the superseding
  /// [_teardown] had run too early to see, leaving it live and applying
  /// frames with nothing left holding a handle to close it.
  Future<void> _attach(int generation, SlimmApi api, MessageStore store) async {
    final ticket = await api.webSocketTicket();
    final connection = await EventConnection.connect(
      url: api.webSocketUrl,
      ticket: ticket.ticket,
    );
    if (generation != _generation) {
      await connection.close();
      return;
    }
    _connection = connection;

    _events = connection.events.listen(
      (event) async {
        if (generation != _generation) return;

        /// Broadcast first and unconditionally: a listener that only cares
        /// about, say, ReactionsChanged must not depend on this switch ever
        /// learning about that event type.
        _liveEvents.add(event);
        await _applyServerEvent(generation, api, store, event);
      },
      onError: (_) => _onDropped(),
      onDone: _onDropped,
    );
  }

  /// How one frame from the socket changes local state. A method of its own
  /// so [applyServerEventForTest] can drive it without a real socket.
  Future<void> _applyServerEvent(
    int generation,
    SlimmApi api,
    MessageStore store,
    ServerEvent event,
  ) async {
    bool isCurrent() => generation == _generation;
    switch (event) {
      case MessageCreated(:final message):
        // A DM's first message is a channel never fetched; materialise it first or this no-ops.
        if (!await store.hasChannel(message.channelId)) {
          await _channelRefresher.refreshOnce(api, store, isCurrent: isCurrent);
        }
        if (!isCurrent()) return;
        await store.applyMessage(message);
      case MessageEdited(:final message, :final opSeq):
        if (!await store.hasChannel(message.channelId)) {
          await _channelRefresher.refreshOnce(api, store, isCurrent: isCurrent);
        }
        if (!isCurrent()) return;
        if (!await _placeLiveOp(message.channelId, opSeq, store)) return;
        await store.applyMessage(message);
      case MessageDeleted(:final channelId, :final messageId, :final opSeq):

        /// Closes a real gap: this switch previously had no case for a
        /// delete at all, so a message removed by another user (or this
        /// account's own delete looping back) never left the local store
        /// and stayed visible until the next full resync.
        if (!await _placeLiveOp(channelId, opSeq, store)) return;
        await store.discard(messageId);
      case ChannelCreated(:final channel):
      case ChannelUpdated(:final channel):
        await store.upsertChannels([channel]);
      case ChannelDeleted(:final channelId):
        // A channel already known to be gone; no round trip needed for that.
        await store.removeChannel(channelId);
      case OverwriteChanged():
      case RoleChanged():
      case MemberRoleChanged():
      case CategoryChanged():
        // None say which channel (or category) changed; a refresh finds it.
        await _channelRefresher.refreshOnce(api, store, isCurrent: isCurrent);
      case ErrorEvent(:final needsResync) when needsResync:
        // The server closed a connection that fell behind; a restart re-runs catch-up.
        unawaited(start());
      case _:
        break;
    }
  }

  /// Decides whether a live op may be applied, and advances the cursor when
  /// it may. Answers false when the caller must not apply the payload.
  ///
  /// A gap schedules one reconcile rather than applying an op it cannot place:
  /// moving the cursor past something never seen would strand it permanently,
  /// where a stall only lasts until the next round.
  Future<bool> _placeLiveOp(
    String channelId,
    int? opSeq,
    MessageStore store,
  ) async {
    final cursor = await store.opCursorFor(channelId);
    switch (liveOpDecision(opSeq, cursor)) {
      case LiveOpOutcome.ignored:
        return false;
      case LiveOpOutcome.needsReconcile:
        unawaited(reconcile().catchError((_) {}));
        return false;
      case LiveOpOutcome.applied:
        if (opSeq != null) await store.setOpCursor(channelId, opSeq);
        return true;
    }
  }

  /// Applies one live event the way [_attach]'s listener would, without
  /// needing a real socket. For tests only.
  @visibleForTesting
  Future<void> applyServerEventForTest(ServerEvent event) async {
    final api = _ref.read(apiProvider);
    final store = await _ref.read(storeProvider.future);
    await _applyServerEvent(_generation, api, store, event);
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
    // Supersedes any in-flight start(), even one paused mid-catch-up on a network call.
    _generation++;
    _channelRefresher.discardInFlight();
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
  ///
  /// [channelHistoryProvider] and [messageExtrasProvider] are reset alongside
  /// the database for the same reason; see their own doc comments.
  Future<void> _endSession() async {
    await stop();
    _ref.invalidate(channelHistoryProvider);
    _ref.invalidate(meProvider);
    _ref.invalidate(initialSyncCompleteProvider);
    _ref.read(messageExtrasProvider.notifier).clear();
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
    _generation++;
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
