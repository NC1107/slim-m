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
