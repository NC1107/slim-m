// SPDX-License-Identifier: Apache-2.0
/// Paging a channel's history backwards, and knowing whether the top of it
/// has actually been reached.
///
/// Two things depended on this and neither had it. The transcript rendered
/// `ChannelStartHeader` from the channel's name alone, so a channel with more
/// history than the loaded window announced the start of the conversation
/// while sitting directly above messages nobody had fetched. And scrolling to
/// the top loaded nothing at all: `/sync` and the channel screen's own
/// hydration both stop at 50, and `MessageStore.watchChannel` shows the newest
/// 200 rows, so everything older than that was unreachable in the client.
///
/// [ChannelHistory.atStart] is the answer to both, and it is only ever set by
/// the server running out of older messages - never inferred from a row's
/// `seq`, which soft deletes make gappy, and never from the window being
/// unfilled, which says nothing about what was never asked for.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';

import 'message_extras.dart';
import 'providers.dart';

/// How many older messages one backwards page asks for.
///
/// Comfortably under the server's own `MAX_LIMIT` of 100, which matters: a
/// page shorter than this is read as the end of the channel's history, and a
/// server that clamped the request below what was asked for would turn that
/// into a false claim.
const _pageSize = 50;

/// The transcript's opening window, matching [MessageStore.watchChannel]'s
/// own default so a channel that has never been paged reads exactly as it
/// did before this existed.
const _initialWindow = 200;

/// How much of a channel's history is loaded, and whether that is all of it.
class ChannelHistory {
  const ChannelHistory({
    this.atStart = false,
    this.loading = false,
    this.failed = false,
    this.window = _initialWindow,
  });

  /// True once the server has answered with fewer older messages than a full
  /// page, which is the only evidence that the oldest loaded row is genuinely
  /// the channel's first.
  final bool atStart;

  final bool loading;

  /// A failed page stops the automatic trigger from retrying: the top of the
  /// list stays in view while it is showing, so an auto-retry would become an
  /// unbounded request loop against whatever just refused.
  final bool failed;

  /// How many rows the local store is asked to hand the transcript, grown by
  /// each page so prepended history is actually visible.
  final int window;

  ChannelHistory copyWith({
    bool? atStart,
    bool? loading,
    bool? failed,
    int? window,
  }) => ChannelHistory(
    atStart: atStart ?? this.atStart,
    loading: loading ?? this.loading,
    failed: failed ?? this.failed,
    window: window ?? this.window,
  );
}

class ChannelHistoryController extends StateNotifier<ChannelHistory> {
  ChannelHistoryController(this._ref, this._channelId)
    : super(const ChannelHistory());

  final Ref _ref;
  final String _channelId;

  /// Fetches the page of messages immediately older than [oldestLoadedSeq]
  /// and prepends it to the local store.
  ///
  /// Safe to call on every scroll frame: it is a no-op once the start has
  /// been reached, while a page is in flight, and after a failure. A null or
  /// zero [oldestLoadedSeq] means nothing delivered is loaded yet, so there is
  /// no keyset to page from.
  Future<void> loadOlder(int? oldestLoadedSeq) async {
    if (state.atStart || state.loading || state.failed) return;
    if (oldestLoadedSeq == null || oldestLoadedSeq <= 0) return;
    state = state.copyWith(loading: true);
    try {
      final older = await _ref
          .read(apiProvider)
          .listMessages(_channelId, before: oldestLoadedSeq, limit: _pageSize);
      final store = await _ref.read(storeProvider.future);
      await store.applyMessages(older);
      if (!mounted) return;
      _ref.read(messageExtrasProvider.notifier).applyMessages(older);
      state = state.copyWith(
        loading: false,
        atStart: older.length < _pageSize,
        window: state.window + older.length,
      );
    } on api.ApiException {
      if (!mounted) return;
      state = state.copyWith(loading: false, failed: true);
    }
  }

  /// Clears a failed page and asks again, from the retry the top of the list
  /// offers.
  Future<void> retry(int? oldestLoadedSeq) async {
    if (!state.failed) return;
    state = state.copyWith(failed: false);
    await loadOlder(oldestLoadedSeq);
  }
}

/// Per channel and deliberately not `autoDispose`: what has been paged in is
/// a property of the channel, not of the screen currently showing it, and
/// dropping it on a channel switch would re-announce the start of a
/// conversation that had already been proved to have more above it.
final channelHistoryProvider =
    StateNotifierProvider.family<
      ChannelHistoryController,
      ChannelHistory,
      String
    >((ref, channelId) => ChannelHistoryController(ref, channelId));

/// The smallest `seq` among the delivered rows in [rows], or null when none
/// are delivered.
///
/// Pending sends carry `seq` 0 until the server acknowledges them, and zero
/// is the lowest value there is, so a naive minimum would page from the
/// beginning of every channel the moment somebody had an unsent message.
int? oldestDeliveredSeq(List<Message> rows) {
  int? oldest;
  for (final row in rows) {
    if (row.seq <= 0) continue;
    if (oldest == null || row.seq < oldest) oldest = row.seq;
  }
  return oldest;
}
