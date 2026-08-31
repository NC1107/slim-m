// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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

  /// Forgets every cached status, for a session ending.
  ///
  /// This provider is deliberately app-lifetime rather than `autoDispose`, so
  /// nothing else would ever empty it: a sign-out followed by a different
  /// account signing in on the same device would show that account the
  /// previous one's presence - plainly wrong, since a status is per-person
  /// and the two accounts see different people online. Every sibling cache
  /// with this shape either runs its own session listener or is cleared by
  /// `SyncController`; this one had neither.
  void clear() {
    if (mounted) state = const {};
  }

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

/// The caller's own visibility choice as far as this client knows it, or null
/// for "not known", which is the state every launch starts in.
///
/// The preference itself is durable and does not need re-applying: the server
/// stores it in `users.presence_visibility` (migration 0008), so relaunching
/// or reconnecting does not make someone who chose appear-offline visible
/// again. What is missing is a way to read it back. `PATCH /presence` echoes
/// only the value it just set, and `GET /presence` resolves a caller's own id
/// to their true connection state rather than the preference (`presence.rs`'s
/// `status_for`, and its `hidden_reads_as_offline_to_others_but_true_to_self`
/// test), so a hidden user's own client cannot tell hidden from online.
///
/// KNOWN GAP, deliberately left open here: closing it needs a read-back on the
/// server, not a cache on the device. Persisting the last choice locally and
/// re-applying it on connect would let a device holding a stale value silently
/// un-hide someone who chose appear-offline from another device, which is a
/// worse failure than not knowing. Until that endpoint exists, every surface
/// showing this must render null as "no choice known" rather than asserting
/// one, which is why the type is nullable rather than defaulting to online.
final presenceVisibilityDisplayProvider =
    StateProvider<api.PresenceVisibility?>((ref) => null);
