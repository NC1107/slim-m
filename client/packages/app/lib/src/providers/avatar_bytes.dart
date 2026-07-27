// SPDX-License-Identifier: Apache-2.0
/// Fetches and caches one user's avatar bytes.
///
/// Keyed by (userId, avatarUpdatedAt) rather than userId alone: an upload
/// changes the timestamp, which mints a new family key and triggers a fresh
/// fetch with no manual cache invalidation required. In-memory only and
/// `autoDispose`, the same tradeoff `attachment_bytes.dart` makes, so a long
/// member list evicts what nobody is looking at rather than growing forever.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart';

import 'providers.dart';

/// [updatedAt] is null when the caller does not know whether an avatar
/// exists at all (a server older than the field). The fetch is still
/// attempted; there is just no cache-busting key of its own to key it by.
typedef AvatarKey = ({String userId, int? updatedAt});

/// Null both while there is genuinely no avatar (a 404) and, transiently,
/// while the fetch is in flight; callers fall back to initials either way.
final avatarBytesProvider =
    FutureProvider.autoDispose.family<Uint8List?, AvatarKey>((ref, key) async {
  try {
    final fetched = await ref.watch(apiProvider).fetchAvatar(key.userId);
    return fetched.bytes;
  } on NotFoundException {
    return null;
  }
});
