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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

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
class BatchProfilesController
    extends StateNotifier<Map<String, api.UserProfile?>> {
  BatchProfilesController(this._ref) : super(const {});

  final Ref _ref;

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
}

/// Kept for the screen's lifetime (not `autoDispose`): a moderation queue
/// commonly repeats a reporter across several reports, and losing this
/// between rebuilds would re-fetch a profile the caller already has.
final batchProfilesControllerProvider =
    StateNotifierProvider<
      BatchProfilesController,
      Map<String, api.UserProfile?>
    >((ref) => BatchProfilesController(ref));
