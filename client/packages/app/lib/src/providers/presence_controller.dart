// SPDX-License-Identifier: Apache-2.0
/// Live presence: a batch lookup seeded once per member list, kept current
/// by `presence.changed` events for the rest of the session.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'live_events.dart';
import 'providers.dart';

/// Every user this session currently has a presence status for. A user
/// absent from this map is simply unknown yet, never "offline": that
/// distinction belongs to the caller, which is why this holds
/// [api.PresenceState] rather than a design-system [AppPresence] already
/// defaulted to offline.
class PresenceController extends StateNotifier<Map<String, api.PresenceState>> {
  PresenceController(this._ref) : super(const {}) {
    _sub = _ref.read(liveEventsProvider).listen((event) {
      if (event is api.PresenceChanged) {
        state = {...state, event.userId: event.status};
      }
    });
  }

  final Ref _ref;
  late final StreamSubscription<api.ServerEvent> _sub;

  /// Batch-fetches presence for [userIds] and merges it into what is already
  /// known. Best-effort: a failed refresh just leaves the map as it was
  /// rather than surfacing an error the member pane has nowhere to show.
  Future<void> refresh(Iterable<String> userIds) async {
    final ids = userIds.toList(growable: false);
    if (ids.isEmpty) return;
    try {
      final statuses = await _ref.read(apiProvider).listPresence(ids);
      state = {
        ...state,
        for (final status in statuses) status.userId: status.status,
      };
    } on api.ApiException {
      // Nothing useful to do; the next refresh (or a live event) corrects it.
    }
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

/// Kept alive for the app's session rather than `autoDispose`: presence is
/// cheap to hold and reused across the member pane closing and reopening,
/// so there is no reason to lose it and refetch every time the pane toggles.
final presenceControllerProvider =
    StateNotifierProvider<PresenceController, Map<String, api.PresenceState>>(
      (ref) => PresenceController(ref),
    );

/// What the settings screen shows as the caller's own visibility choice.
///
/// There is deliberately no way to read this back from the server: `PATCH
/// /presence` (`setPresenceVisibility`) reports only the value it just set,
/// and `GET /presence` resolves a caller's own id to their true connection
/// state regardless of a `hidden` preference (`presence.rs`'s
/// `status_for`, confirmed by its own `hidden_reads_as_offline_to_others_
/// but_true_to_self` test), never the preference itself. So this is a
/// display-only local echo of the last choice made in this session, not a
/// fetched value; a fresh app launch has no way to know what was chosen
/// last time and defaults to showing "online" rather than guessing.
final presenceVisibilityDisplayProvider = StateProvider<api.PresenceVisibility>(
  (ref) => api.PresenceVisibility.online,
);
