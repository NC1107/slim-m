// SPDX-License-Identifier: Apache-2.0
/// Advancing a channel's read marker: the local write, the server call, and
/// the guard that keeps a busy channel from re-sending a seq it has already
/// recorded.
///
/// Split out of `channel_screen.dart`, which was the only thing that ever
/// held this and had no room left to grow.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import '../providers/providers.dart';

/// Records what has been read, up to the newest delivered message in a
/// channel ([VisibleTranscript.newestSeq]).
///
/// Pending sends are excluded there: they carry seq 0 until the server
/// acknowledges them, so treating one as "read" would either no-op or, once
/// the real send lands with its assigned seq, immediately look unread again
/// for a message the user already sees on screen. A blocked author's message
/// counts, since it was received rather than never sent.
///
/// The local write and the network call are both monotonic and idempotent
/// (`MessageStore.setReadMarker`, the server's `PUT .../read`), so a redundant
/// call is harmless; the per-channel guard exists only to keep a busy channel
/// from re-sending the same seq on every unrelated rebuild. It is keyed by
/// channel because one instance outlives a channel switch: `ConversationPane`
/// builds `ChannelScreen` with no key, so navigating between channels reuses
/// the same `State`.
///
/// Callers own the scroll gate: this only knows the seq to advance to, never
/// whether the viewport is actually showing it.
class ReadMarker {
  ReadMarker(this._ref);

  final WidgetRef _ref;
  final Map<String, int> _sent = {};

  void advance(String channelId, {required int seq, required int lastReadSeq}) {
    if (seq == 0) return;
    if (seq <= lastReadSeq) return;
    if ((_sent[channelId] ?? 0) >= seq) return;
    _sent[channelId] = seq;
    unawaited(_write(channelId, seq));
  }

  Future<void> _write(String channelId, int seq) async {
    final store = await _ref.read(storeProvider.future);
    await store.setReadMarker(channelId, seq);
    try {
      await _ref.read(apiProvider).markRead(channelId: channelId, seq: seq);
    } on api.ApiException {
      // Best-effort: the local marker already advanced, so the UI is correct.
    }
  }
}
