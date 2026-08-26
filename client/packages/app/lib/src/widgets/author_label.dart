// SPDX-License-Identifier: Apache-2.0
/// The single place a message author's display name is resolved, closing the
/// recorded debt that a renamed author's already-cached messages never
/// reconciled: `message_row_identity.dart`, `channel_search.dart`,
/// `pinned_messages_sheet.dart` and `command_palette_items.dart` used to each
/// carry their own copy of the "cached name, or a fallback for a missing
/// author" rule and none of them ever refreshed it.
library;

import 'package:slimm_api/api.dart' as api;

/// [authorId]'s name as of the last time [profiles] was asked about them.
///
/// A `null` [authorId] is an author already anonymized before this row was
/// even fetched. A [profiles] entry present but `null` is the same fact
/// learned live - the batch lookup asked and nobody answered - and that must
/// win over [cachedDisplayName], or a rename that resolves to "gone" would
/// keep showing the deleted account's last-known name forever, which is
/// exactly the resurrection the local cache is not allowed to cause. An id
/// absent from [profiles] entirely just means nobody has asked yet, so the
/// row's own cached copy (accurate as of whenever it was written) is the
/// best answer available until [profiles] catches up.
String authorLabel({
  required String? authorId,
  required String? cachedDisplayName,
  required Map<String, api.UserProfile?> profiles,
}) {
  if (authorId == null) return 'Deleted user';
  if (profiles.containsKey(authorId)) {
    return profiles[authorId]?.displayName ?? 'Deleted user';
  }
  return cachedDisplayName ?? 'Unknown';
}
