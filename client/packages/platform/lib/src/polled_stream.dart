// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The shared shape of a rich-presence source: nothing runs until someone
/// listens, and cancelling stops every read (decision 0044).
library;

import 'dart:async';

/// Thrown by a read that has no fresh answer (a rate limit, say), so the
/// last value stands instead of flickering to null.
class PollSkip implements Exception {
  const PollSkip();
}

/// Reads now and then every [interval], emitting only when the answer
/// changes. Any other failure reads as "nothing", never as an error.
Stream<T?> polledStream<T>({
  required Duration interval,
  required Future<T?> Function() read,
  Future<void> Function()? onCancel,
}) {
  Timer? timer;
  T? last;
  var first = true;
  late final StreamController<T?> controller;

  Future<void> poll() async {
    T? current;
    try {
      current = await read();
    } on PollSkip {
      return;
    } on Object {
      current = null;
    }
    if (controller.isClosed || (!first && current == last)) return;
    first = false;
    last = current;
    controller.add(current);
  }

  controller = StreamController<T?>(
    onListen: () {
      unawaited(poll());
      timer = Timer.periodic(interval, (_) => unawaited(poll()));
    },
    onCancel: () async {
      timer?.cancel();
      await onCancel?.call();
    },
  );
  return controller.stream;
}
