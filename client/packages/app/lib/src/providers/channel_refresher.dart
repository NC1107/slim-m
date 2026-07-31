// SPDX-License-Identifier: Apache-2.0
/// Keeps the channel listing (and each channel's read marker) current,
/// deduplicating a concurrent refresh into the one already running.
///
/// Split out of `sync_controller.dart`: unlike catch-up and the live socket,
/// this never touches the connection's own state, so it is a seam that does
/// not disturb the reconnect logic around it.
library;

import 'package:slimm_api/api.dart';
import 'package:slimm_data/data.dart';

import 'dms.dart';

/// Refreshes both channel listings the server keeps apart, and hydrates
/// their read markers, deduplicating a concurrent caller into the refresh
/// already running rather than starting a second.
class ChannelRefresher {
  Future<void>? _inFlight;

  /// Refreshes both channel listings the server keeps apart: the
  /// deployment's own channels, and the caller's DM conversations (which
  /// `GET /channels` deliberately excludes). Both land in the same local
  /// channel table under the same shape, so everything downstream (the
  /// rail, sync cursors, read state) treats a DM exactly like any other
  /// channel once it is here. Also prunes any channel the server no longer
  /// lists, so one whose view was just revoked leaves the rail rather than
  /// sitting there until sign-out.
  ///
  /// Also hydrates each channel's read marker from the server. `ScopeDelta`
  /// carries no read state, so `/sync` can never do this, and
  /// `MessageStore.clear()` wipes the local marker on every sign-out; without
  /// this, a reinstall or a second device shows every channel unread
  /// forever, however recently it was actually read elsewhere.
  Future<void> refresh(SlimmApi api, MessageStore store) async {
    final channels = await api.listChannels();
    final dms = await api.listDirectMessages();
    final selfId = api.session.tokens?.userId;
    final all = [
      ...channels,
      ...dms.map((dm) => channelFromDm(dm, selfId: selfId)),
    ];
    await store.replaceChannels(all);

    /// Per channel: the server has no bulk read-state endpoint, and one
    /// channel's failure must not stop the rest from hydrating.
    await Future.wait(
      all.map((channel) async {
        try {
          final read = await api.readState(channel.id);
          await store.setReadMarker(channel.id, read.lastReadSeq);
        } on ApiException {
          // Best-effort: the next refresh retries; until then it just reads as unread.
        }
      }),
    );
  }

  /// [refresh], but a concurrent caller joins the one already running
  /// instead of starting a second.
  Future<void> refreshOnce(SlimmApi api, MessageStore store) {
    return _inFlight ??= refresh(api, store).whenComplete(() {
      _inFlight = null;
    });
  }
}
