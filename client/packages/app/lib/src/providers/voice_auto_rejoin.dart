// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Brings a call back after the network took it away, without anybody
/// having to notice and tap.
///
/// LiveKit retries a dropped connection itself, on its own schedule
/// (`defaultRetryDelaysInMs` in livekit_client 2.10.0: ten attempts spanning
/// 44 seconds). This picks up where that gives up. Until it existed, a
/// client whose transport outlasted that budget landed in
/// [VoiceSessionState.failed] and stayed there: `VoiceController`'s
/// heartbeat stopped, and the only way back into the call was the manual
/// "Try again" on `VoiceRejoinScreen`. That is a reasonable last resort and
/// a poor first one - a phone that changes network in a lift comes back on
/// its own, and the call should too.
///
/// Its own file, the shape `voice_call_heartbeat.dart` already set: a small
/// timer-owning collaborator, so `voice_controller.dart` gains the decision
/// and not the bookkeeping.
///
/// Deliberately bounded. Retrying forever would turn an outage into a
/// battery drain and would keep a screen claiming to reconnect long after
/// anybody watching it had given up, so the attempts run out and the manual
/// surface takes over.
library;

import 'dart:async';

class VoiceAutoRejoin {
  VoiceAutoRejoin({this.delays = defaultDelays});

  /// One entry per attempt, measured from the previous failure.
  ///
  /// Three of them, widening: the first covers the common case where the
  /// network is already back by the time LiveKit stops trying, and the
  /// later two cover a handover that is still settling. Past that the
  /// problem is not one this can retry its way out of.
  static const defaultDelays = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  final List<Duration> delays;

  Timer? _timer;
  int _spent = 0;

  /// Whether an attempt is waiting to run, so a screen can say it is
  /// reconnecting rather than showing an error nothing asked the user to act
  /// on yet.
  bool get pending => _timer != null;

  /// Runs [attempt] after the next delay, and answers whether it scheduled
  /// anything: `false` means the attempts are spent and whoever called this
  /// owns what the user sees next.
  bool schedule(void Function() attempt) {
    if (_spent >= delays.length) return false;
    _timer?.cancel();
    final delay = delays[_spent++];
    _timer = Timer(delay, () {
      _timer = null;
      attempt();
    });
    return true;
  }

  /// Drops a queued attempt without spending or restoring anything, for a
  /// deliberate join that supersedes it. The budget survives on purpose: a
  /// person who taps into a different channel mid-reconnect has not told us
  /// anything about the drop this was recovering from.
  void cancelPending() {
    _timer?.cancel();
    _timer = null;
  }

  /// Drops any pending attempt and restores the full budget, for a call that
  /// ended or reconnected. Both halves matter: a connected call must not be
  /// interrupted by a stale timer, and the next drop is a new problem that
  /// deserves its own three tries rather than whatever this one left over.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _spent = 0;
  }
}
