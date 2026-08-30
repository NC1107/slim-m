// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Keeps the server's proof of a live call fresh while [VoiceController]
/// holds one connected.
///
/// Split out of `voice_controller.dart` to keep that file under the review
/// budget: this is already a self-contained concern with its own test file
/// (`voice_call_heartbeat_test.dart`), which drives it entirely through
/// `VoiceController`'s public `join`/`leave` and never reaches in here, so
/// extracting it changes nothing a test could see.
///
/// Independent of `AppLifecycleState` on purpose: a phone call that stopped
/// the moment you switched apps would be useless, so this keeps ticking
/// through backgrounding and only really stops when the process does.
///
/// This bounds how long a killed app's ghost lingers for *other*
/// participants and the server's own bookkeeping; see
/// `crates/slimm-server/src/voice/heartbeat.rs`. It does not, and cannot,
/// bound how this same client renders its own state on its own next launch -
/// that answer lives in `voiceRosterProvider`, which drops this client's own
/// identity from any roster it reads regardless of whether the server has
/// caught up yet.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart';

import '../diagnostics/debug_log.dart';
import 'providers.dart';

class VoiceCallHeartbeat {
  VoiceCallHeartbeat(this._ref, {required this.interval});

  final Ref _ref;
  final Duration interval;
  Timer? _timer;

  /// Starts refreshing the server's proof that this call is still live, if
  /// it is not running already. Guarded rather than assumed single-fire: no
  /// transition in the caller re-emits `connected` after `join`'s own, but
  /// the check costs nothing and removes the assumption that this stays true
  /// forever from something that would otherwise double the interval the
  /// moment it stopped holding.
  void start(String? channelId) {
    if (_timer != null || channelId == null) return;
    unawaited(_send(channelId));
    _timer = Timer.periodic(interval, (_) => unawaited(_send(channelId)));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _send(String channelId) async {
    try {
      await _ref.read(apiProvider).sendVoiceHeartbeat(channelId);
    } catch (e) {
      // Best-effort, but a run of failures is worth seeing in diagnostics.
      _log('Voice heartbeat failed', detail: e);
    }
  }

  /// Tells the server a clean leave happened, so it does not keep a stale
  /// "removed a voice participant with no recent heartbeat" entry around
  /// until the staleness window catches up on its own.
  Future<void> forget(String channelId) async {
    try {
      await _ref.read(apiProvider).forgetVoiceHeartbeat(channelId);
    } catch (e) {
      _log('Could not tell the server this call was left', detail: e);
    }
  }

  void _log(String message, {Object? detail}) => _ref
      .read(debugLogProvider.notifier)
      .record('voice', message, detail: detail);
}
