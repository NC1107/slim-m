// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Who is typing in one channel, right now.
///
/// Both halves are real: [TypingController.notifyTyping] sends the `typing`
/// client frame while the user types, and `typing.started`/`typing.stopped`
/// drive what this exposes about everyone else.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'blocks_controller.dart';
import 'live_events.dart';
import 'sync_controller.dart';

/// The server's own typing TTL: `DEFAULT_TTL` in
/// `crates/slimm-server/src/typing.rs`, in seconds.
///
/// Named rather than folded into [_refreshEvery] as a bare 3, so the refresh
/// is derived from it at compile time instead of the two being tied only by a
/// comment claiming to be "comfortably inside" a number it never states. The
/// shape `voice/heartbeat.rs` already uses for the mirror in the other
/// direction. Still hand-updated if the server's value changes, which is the
/// point: one number to change, and `scripts/lib/test_typing_ttl_drift.py`
/// fails if only one side of the mirror moves.
const int _serverTypingTtlSeconds = 6;

/// How long to wait before telling the server again that the user is still
/// typing. Half the server's expiry, so a single dropped refresh still leaves
/// the indicator lit, and far enough apart to stay under the rate limit that
/// would otherwise silently drop it.
const Duration _refreshEvery = Duration(seconds: _serverTypingTtlSeconds ~/ 2);

/// The set of user ids currently typing in one channel.
///
/// No client-side expiry timer: the server guarantees a `typing.stopped`
/// for every `typing.started` it ever sent, even for a client that
/// disconnects mid-typing (`crates/slimm-server/src/typing.rs`), so trusting
/// that pair is enough rather than re-implementing the same TTL here.
class TypingController extends StateNotifier<Set<String>> {
  TypingController(this._ref, this._channelId) : super(const {}) {
    _sub = _ref.read(liveEventsProvider).listen((event) {
      switch (event) {
        // A blocked user never enters the set rather than being filtered out.
        case api.TypingStarted(:final channelId, :final userId)
            when channelId == _channelId &&
                !_ref.read(blocksProvider).contains(userId):
          state = {...state, userId};
        case api.TypingStopped(:final channelId, :final userId)
            when channelId == _channelId:
          state = {...state}..remove(userId);
        default:
          break;
      }
    });
  }

  final Ref _ref;
  final String _channelId;
  late final StreamSubscription<api.ServerEvent> _sub;
  DateTime? _lastSent;

  /// Call on every keystroke. Throttled rather than debounced: the server
  /// wants a periodic refresh, and waiting for a pause would stop telling it
  /// exactly while the user is most obviously typing.
  void notifyTyping() {
    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < _refreshEvery) {
      return;
    }
    _lastSent = now;
    _ref.read(syncControllerProvider.notifier).notifyTyping(_channelId);
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

/// One instance per channel, torn down (and its subscription with it) once
/// nothing is watching that channel's composer any more.
final typingControllerProvider = StateNotifierProvider.autoDispose
    .family<TypingController, Set<String>, String>(
      (ref, channelId) => TypingController(ref, channelId),
    );
