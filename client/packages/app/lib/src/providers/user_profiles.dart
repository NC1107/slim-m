// SPDX-License-Identifier: Apache-2.0
/// Resolves one user's public profile by id, for a caller that only holds an
/// author id (a message, a pin) rather than the full profile it rides on,
/// and needs the avatar cache key ([api.UserProfile.avatarUpdatedAt]) that
/// comes with it.
///
/// A direct fetch rather than a shortcut through the member pane's
/// already-loaded list: that would make this file depend on a widget-layer
/// provider, and the family cache below already means a given author is
/// only ever fetched once per session regardless of how many of their
/// messages are on screen.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import '../widgets/author_label.dart' show AuthorResolution;
import 'live_events.dart';
import 'providers.dart';

/// Null for a deleted or anonymized account (a 404), exactly like
/// [api.SlimmApiUsers.getUser] itself.
final userProfileProvider = FutureProvider.autoDispose
    .family<api.UserProfile?, String>((ref, userId) async {
      try {
        return await ref.watch(apiProvider).getUser(userId);
      } on api.NotFoundException {
        return null;
      }
    });

/// Resolves several ids in one round trip, for a caller that needs more than
/// one at a time (a report card needs its reporter and, for a user report,
/// its subject) and would otherwise cost one request per id.
///
/// A `Map` rather than a list of futures: an id present with a null value is
/// a confirmed miss (matching [api.SlimmApiUsers.listUsers]'s own "absent
/// means gone" contract), while an id absent from the map has simply not
/// been resolved yet, which is what lets a caller tell "still loading" apart
/// from "this account no longer exists".
///
/// Also the live cache a message row's author name is resolved against (see
/// `widgets/author_label.dart`): a [api.ProfileChanged] frame evicts the
/// renamed id so the next [resolve] re-asks for it, rather than carrying the
/// new name on the frame itself, which would make this map a second place
/// the value could be wrong.
class BatchProfilesController
    extends StateNotifier<Map<String, api.UserProfile?>> {
  BatchProfilesController(this._ref) : super(const {}) {
    _sub = _ref.read(liveEventsProvider).listen((event) {
      if (event is api.ProfileChanged && state.containsKey(event.userId)) {
        state = {...state}..remove(event.userId);
      }
    });
  }

  final Ref _ref;
  late final StreamSubscription<api.ServerEvent> _sub;

  /// Fetches whichever of [ids] are not already known. Best-effort: a failed
  /// call leaves those ids unresolved rather than wrongly reading a network
  /// error as "account deleted".
  Future<void> resolve(Iterable<String> ids) async {
    final missing = ids.where((id) => !state.containsKey(id)).toSet();
    if (missing.isEmpty) return;
    try {
      final found = await _ref.read(apiProvider).listUsers(missing.toList());
      final byId = {for (final profile in found) profile.id: profile};
      state = {...state, for (final id in missing) id: byId[id]};
    } on api.ApiException {
      // Left unresolved; whoever asked can retry on the next build.
    }
  }

  /// Forgets every cached profile, for a session that may have missed
  /// [api.ProfileChanged] frames while disconnected: [SyncController.start]
  /// calls this on every (re)connect, since there is no cursor over renames
  /// to catch up from and asking fresh is always correct.
  void clear() => state = const {};

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}

/// Kept for the screen's lifetime (not `autoDispose`): a moderation queue
/// commonly repeats a reporter across several reports, and losing this
/// between rebuilds would re-fetch a profile the caller already has.
final batchProfilesControllerProvider =
    StateNotifierProvider<
      BatchProfilesController,
      Map<String, api.UserProfile?>
    >((ref) => BatchProfilesController(ref));

/// [authorId]'s own slice of [profiles], for a caller that wants to
/// `.select` [batchProfilesControllerProvider] rather than watch the whole
/// map: a row watching the map outright rebuilds on every other author's
/// resolve too, since [BatchProfilesController.resolve] replaces the map's
/// identity on every call. Selecting this record instead means the row only
/// rebuilds when its own author's entry actually changes - see
/// `widgets/author_label.dart`'s [authorLabelResolved], which consumes it.
AuthorResolution authorResolution(
  Map<String, api.UserProfile?> profiles,
  String authorId,
) => (present: profiles.containsKey(authorId), profile: profiles[authorId]);

/// Kicks off resolving whichever of [authorIds] this session does not
/// already have cached. Safe to call on every rebuild a message list
/// produces: [BatchProfilesController.resolve] itself skips ids it already
/// knows, so a screen that renders the same authors every frame costs one
/// scan of already-known ids, not a repeated fetch.
void resolveAuthorProfiles(WidgetRef ref, Iterable<String?> authorIds) {
  final ids = authorIds.whereType<String>().toSet();
  if (ids.isEmpty) return;
  unawaited(ref.read(batchProfilesControllerProvider.notifier).resolve(ids));
}
