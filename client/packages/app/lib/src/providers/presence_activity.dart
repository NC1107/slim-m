// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What each member is listening to or playing, as this connection is told.
///
/// Kept apart from [PresenceController]'s status map so a track change
/// rebuilds only the rows and cards that show one. An absent id means no
/// activity is visible, which is also what a hidden or offline member reads
/// as: the server never sends one for them.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart' show AppIcons;

import 'live_events.dart';

class PresenceActivityController
    extends StateNotifier<Map<String, api.PresenceActivity>> {
  PresenceActivityController(this._ref) : super(const {}) {
    _sub = _ref.read(liveEventsProvider).listen((event) {
      if (event is api.PresenceChanged) {
        _set(event.userId, event.activity);
      }
    });
  }

  final Ref _ref;
  late final StreamSubscription<api.ServerEvent> _sub;

  void _set(String userId, api.PresenceActivity? activity) {
    if (!mounted || state[userId] == activity) return;
    final next = {...state};
    if (activity == null) {
      next.remove(userId);
    } else {
      next[userId] = activity;
    }
    state = next;
  }

  /// Applies a batch lookup: every id it names is now exactly as told.
  void applyBatch(Iterable<api.PresenceStatus> statuses) {
    for (final status in statuses) {
      _set(status.userId, status.activity);
    }
  }

  /// Forgets everything, for a session ending.
  void clear() {
    if (mounted) state = const {};
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

final presenceActivityProvider =
    StateNotifierProvider<
      PresenceActivityController,
      Map<String, api.PresenceActivity>
    >((ref) => PresenceActivityController(ref));

/// One member's visible activity, scoped so other members' changes do not
/// rebuild the watcher.
final memberActivityProvider = Provider.autoDispose
    .family<api.PresenceActivity?, String>(
      (ref, userId) =>
          ref.watch(presenceActivityProvider.select((m) => m[userId])),
    );

/// "Listening to Title - Artist", or "Playing Title".
String describeActivity(api.PresenceActivity activity) {
  final verb = switch (activity.kind) {
    api.ActivityKind.listening => 'Listening to',
    api.ActivityKind.playing => 'Playing',
  };
  final subtitle = activity.subtitle;
  return subtitle == null
      ? '$verb ${activity.title}'
      : '$verb ${activity.title} - $subtitle';
}

/// The Lucide glyph for a kind of activity.
IconData activityIcon(api.ActivityKind kind) => switch (kind) {
  api.ActivityKind.listening => AppIcons.listening,
  api.ActivityKind.playing => AppIcons.playing,
};
