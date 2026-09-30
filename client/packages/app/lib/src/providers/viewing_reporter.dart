// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tells the server which channels this device has open and focused, so push
/// can skip a message the account is already reading here.
///
/// A device that is not in front of the user reports nothing: an unfocused
/// desktop window or a backgrounded phone must not silence the account's
/// other devices. The server lets a report lapse after 60 seconds, so while
/// anything is open it is re-sent well inside that, and again after every
/// reconnect, because a new socket starts with no report.
///
/// Read once from bootstrap, beside the sync and push controllers, so it is
/// never built by a widget test that has no socket to report over.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_lifecycle.dart';
import 'mounted_channels.dart';
import 'sync_controller.dart';

/// Comfortably inside the server's 60 second lapse.
const viewingRefreshInterval = Duration(seconds: 30);

class ViewingReporter {
  ViewingReporter(
    this._ref, {
    required void Function(Set<String>) send,
    Duration interval = viewingRefreshInterval,
  }) : _send = send,
       _interval = interval {
    _ref.read(mountedChannelsProvider).addListener(refresh);
  }

  final Ref _ref;
  final void Function(Set<String>) _send;
  final Duration _interval;
  Timer? _timer;
  bool _reportedOpen = false;

  Set<String> _open() => _ref.read(appFocusedProvider)
      ? _ref.read(mountedChannelsProvider).openChannelIds
      : const {};

  /// Reports now and restarts the refresh timer; call on anything that can
  /// change what is open or focused, or that gave the server a new socket.
  void refresh() {
    _timer?.cancel();
    final open = _open();
    if (open.isEmpty && !_reportedOpen) return;
    _send(open);
    _reportedOpen = open.isNotEmpty;
    if (open.isNotEmpty) {
      _timer = Timer.periodic(_interval, (_) => _send(_open()));
    }
  }

  void dispose() {
    _timer?.cancel();
    _ref.read(mountedChannelsProvider).removeListener(refresh);
  }
}

final viewingReporterProvider = Provider<ViewingReporter>((ref) {
  final reporter = ViewingReporter(
    ref,
    send: (channels) =>
        ref.read(syncControllerProvider.notifier).notifyViewing(channels),
  );
  ref.listen(appFocusedProvider, (_, _) => reporter.refresh());
  ref.listen(syncControllerProvider, (_, status) {
    if (status == SyncStatus.live) reporter.refresh();
  });
  ref.onDispose(reporter.dispose);
  return reporter;
});
