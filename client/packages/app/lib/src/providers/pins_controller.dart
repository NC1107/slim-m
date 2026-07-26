// SPDX-License-Identifier: Apache-2.0
/// A channel's pinned messages: fetched once per channel, refreshed whenever
/// a live `message.pinned`/`message.unpinned` event says the set changed.
///
/// Kept as the full list rather than just a count: the header pill only
/// needs the length, but the same state also backs the sheet that lists
/// them, and a second fetch there would just be the same request twice.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'live_events.dart';
import 'providers.dart';

/// A channel's pinned messages, newest pin first (matching the endpoint).
/// Null means not yet loaded, distinct from an empty list: the header pill
/// shows a dash for the former and "0" for the latter.
class PinsController extends StateNotifier<List<api.PinnedMessage>?> {
  PinsController(this._ref, this._channelId) : super(null) {
    _sub = _ref.read(liveEventsProvider).listen((event) {
      final matches = switch (event) {
        api.MessagePinned(:final channelId) => channelId == _channelId,
        api.MessageUnpinned(:final channelId) => channelId == _channelId,
        _ => false,
      };
      // A full refetch rather than an incremental patch: the live frame
      // carries only the one message id, and the list is small enough
      // (self-hosted friend groups, not a public forum) that re-fetching it
      // whole is simpler than reconstructing pin order from a delta.
      if (matches) unawaited(refresh());
    });
    unawaited(refresh());
  }

  final Ref _ref;
  final String _channelId;
  late final StreamSubscription<api.ServerEvent> _sub;

  Future<void> refresh() async {
    try {
      final pinned =
          await _ref.read(apiProvider).listPinnedMessages(_channelId);
      state = pinned;
    } on api.ApiException {
      // Leave whatever was last known rather than blanking a pill that was
      // already showing a real number over one failed refresh.
    }
  }

  Future<void> unpin(String messageId) async {
    await _ref.read(apiProvider).unpinMessage(
          channelId: _channelId,
          messageId: messageId,
        );
    await refresh();
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

final pinsControllerProvider = StateNotifierProvider.autoDispose
    .family<PinsController, List<api.PinnedMessage>?, String>(
        (ref, channelId) => PinsController(ref, channelId));
