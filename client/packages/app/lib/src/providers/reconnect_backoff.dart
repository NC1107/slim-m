// SPDX-License-Identifier: Apache-2.0
/// The delay `SyncController` waits between reconnect attempts.
library;

import 'dart:math';

/// Exponential backoff with jitter, so a server restart does not bring every
/// client back online in the same instant (a thundering herd).
///
/// Attempt N (1-indexed) waits `2^(N-1)` seconds, capped at [maxSeconds] once
/// [maxAttempt] is reached, plus a uniformly random jitter in
/// `[0, jitterMs)` milliseconds. [random] is injectable so a test can seed
/// or fake the draw; production leaves it as the real `Random()`.
class ReconnectBackoff {
  ReconnectBackoff({
    Random? random,
    this.maxAttempt = 6,
    this.maxSeconds = 32,
    this.jitterMs = 1000,
  }) : _random = random ?? Random();

  final Random _random;
  final int maxAttempt;
  final int maxSeconds;
  final int jitterMs;
  int _attempt = 0;

  /// The delay before the next reconnect attempt. Advances the sequence, so
  /// each call backs off further until [maxSeconds] is reached.
  Duration next() {
    _attempt = (_attempt + 1).clamp(1, maxAttempt);
    final seconds = (1 << (_attempt - 1)).clamp(1, maxSeconds);
    final jitter = Duration(milliseconds: _random.nextInt(jitterMs));
    return Duration(seconds: seconds) + jitter;
  }

  /// A successful connection resets the sequence, so the next drop backs off
  /// from the first step again rather than from wherever it last left off.
  void reset() => _attempt = 0;
}
