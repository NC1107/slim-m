// SPDX-License-Identifier: Apache-2.0
/// Who this account has blocked, held for as long as the session lasts.
///
/// The point of holding it here rather than beside the settings pane that
/// lists it: every read surface that has to hide a blocked author consults
/// this, and a set that lives only while one pane is mounted means nothing is
/// hidden anywhere else. That was the shape of the bug this replaces - the app
/// said "their messages are hidden for you" and nothing filtered anything.
///
/// The block list is a view filter, never a fetch filter. A blocked author's
/// messages still arrive and still land in the local database, and are dropped
/// where they would become UI. That is what makes unblocking instant and
/// complete: filtering them out of `/sync` instead would mean they never
/// arrive, and only a full channel reset could ever bring them back.
///
/// Two surfaces are out of reach from here and handled by the server for the
/// same reason. A reaction crosses the wire as a count with no reactor ids, so
/// there is nothing here to match on, and a push notification is on the device
/// before any of this runs. See `store/safety.rs`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';

import 'providers.dart';

/// The blocked ids, and whether they have been read back from the server yet.
class BlocksState {
  const BlocksState({this.ids = const {}, this.settled = false, this.error});

  /// Who is blocked, as far as this client knows.
  final Set<String> ids;

  /// Whether the server has been asked and has answered, either way. Kept apart
  /// from an empty [ids] because the two mean different things to a caller
  /// deciding what to show: "nobody is blocked" is an answer, and "not asked
  /// yet" is not.
  ///
  /// A failed fetch settles too, with [error] set and nothing blocked. That is a
  /// failure to filter and it is the right one of the two: a transcript held
  /// empty behind an unreachable block list is worse than an unfiltered one, and
  /// the settings pane says plainly that the list could not be read.
  final bool settled;

  /// Why the last fetch or change failed, for the one surface that lists them.
  final String? error;

  /// Whether [userId] is blocked. Null (an anonymized author) never is.
  bool contains(String? userId) => userId != null && ids.contains(userId);
}

class BlocksController extends StateNotifier<BlocksState> {
  BlocksController(this._ref) : super(const BlocksState()) {
    // Emptied on sign-out, or the next account on this device inherits it.
    _sub = _ref.read(sessionProvider).changes.listen((tokens) {
      if (tokens == null) {
        state = const BlocksState();
      } else {
        unawaited(refresh());
      }
    });
    unawaited(refresh());
  }

  final Ref _ref;
  late final StreamSubscription<api.TokenPair?> _sub;

  /// Reads the list back from the server, replacing what is held.
  Future<void> refresh() async {
    try {
      final ids = await _ref.read(apiProvider).listBlocks();
      if (!mounted) return;
      state = BlocksState(ids: ids.toSet(), settled: true);
    } on api.ApiException catch (e) {
      if (!mounted) return;
      state = BlocksState(ids: state.ids, settled: true, error: e.message);
    }
  }

  /// Blocks [userId], hiding them before the request answers so the transcript
  /// reacts to the tap rather than to the round trip, and putting them back if
  /// it fails.
  Future<void> block(String userId) => _change(userId, blocked: true);

  /// Unblocks [userId]. Rethrows, unlike [refresh]: unblocking is a deliberate
  /// action with a button behind it, and a failure that reaches nobody is how
  /// the old call site left somebody believing they had undone a block.
  Future<void> unblock(String userId) => _change(userId, blocked: false);

  Future<void> _change(String userId, {required bool blocked}) async {
    final before = state.ids;
    final after = {...before};
    if (blocked) {
      after.add(userId);
    } else {
      after.remove(userId);
    }
    state = BlocksState(ids: after, settled: state.settled);
    final client = _ref.read(apiProvider);
    try {
      if (blocked) {
        await client.blockUser(userId);
      } else {
        await client.unblockUser(userId);
      }
    } on api.ApiException {
      if (mounted) state = BlocksState(ids: before, settled: state.settled);
      rethrow;
    }
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

/// Deliberately not `autoDispose`: see this file's own notes. Every surface
/// that hides a blocked author reads it, so its lifetime is the session's.
final blocksProvider = StateNotifierProvider<BlocksController, BlocksState>(
  (ref) => BlocksController(ref),
);

/// A channel's transcript as it should be shown, beside what was really in it.
class VisibleTranscript {
  const VisibleTranscript({required this.messages, required this.newestSeq});

  /// The rows to render: everything the local store holds, minus blocked
  /// authors.
  final List<Message> messages;

  /// The highest seq of a delivered message in the channel, blocked authors
  /// included, or zero for a channel holding none.
  ///
  /// Read state has to keep counting them. A blocked author's message is hidden,
  /// not unreceived, and a marker that only advanced past what is shown would
  /// leave the channel lit as unread forever the moment they had the last word.
  final int newestSeq;
}

/// One channel's transcript with blocked authors dropped.
///
/// The screen reads this rather than the store directly, so the filter is a
/// property of the only stream it can get at instead of a `where` clause
/// somebody has to remember at each place messages are rendered.
///
/// Watching the block set re-subscribes on a block or an unblock, which is what
/// makes both take effect on the open channel without a refetch.
///
/// It returns the store's own stream mapped, never an `async*` body delegating to
/// it with `yield*`. Cancelling that shape deadlocks a widget test: drift defers
/// a cancelled query stream's cleanup onto a zero-duration timer, and the fake
/// clock only advances on the next pump, which never comes.
final visibleChannelMessagesProvider = StreamProvider.autoDispose
    .family<VisibleTranscript, String>((ref, channelId) {
      final store = ref.watch(storeProvider).valueOrNull;
      final blocks = ref.watch(blocksProvider);
      // Held until settled, or a launch paints a blocked author for one frame.
      if (store == null || !blocks.settled) {
        return const Stream<VisibleTranscript>.empty();
      }
      final blocked = blocks.ids;
      return store.watchChannel(channelId).map((rows) {
        var newestSeq = 0;
        for (final message in rows) {
          if (!message.pending && message.seq > newestSeq) {
            newestSeq = message.seq;
          }
        }
        return VisibleTranscript(
          messages: rows
              .where((message) => !blocked.contains(message.authorId))
              .toList(growable: false),
          newestSeq: newestSeq,
        );
      });
    });
