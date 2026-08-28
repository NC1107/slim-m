// SPDX-License-Identifier: Apache-2.0
/// The deployment's custom emoji as the render side needs them: a name-to-id
/// index for resolving `:shortcode:`, and one emoji's image bytes.
///
/// Named `emoji_catalog_provider` rather than `emoji_catalog` because
/// `widgets/emoji_catalog.dart` already holds the unicode picker's catalog,
/// which is a different thing entirely: that one ships with the app, this one
/// is whatever the deployment uploaded.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart';

import 'admin_providers.dart';
import 'providers.dart';

/// Emoji name (already lower-case, the server normalises it) to emoji id, for
/// resolving a `:shortcode:` while rendering a message.
///
/// Reads [customEmojiProvider] rather than fetching `GET /emoji` again, so the
/// administration screen and every message row share one list and one
/// invalidation: uploading or deleting an emoji there invalidates that
/// provider, and the next frame renders through this index. Two providers over
/// the same endpoint would leave a freshly uploaded emoji unrenderable until
/// relaunch.
///
/// This provider is not `autoDispose`, which also keeps the (`autoDispose`)
/// list alive for the session: message rows come and go as a list scrolls, and
/// letting the last one out of the tree drop the set would refetch it as soon
/// as the next one arrived.
///
/// Empty while the set is loading and empty if the fetch failed, which is the
/// same answer in both cases on purpose: an unresolved shortcode renders as
/// the literal text the member typed, so a slow or broken emoji list degrades
/// to plain text rather than to a gap.
final customEmojiIndexProvider = Provider<Map<String, String>>((ref) {
  final emoji = ref.watch(customEmojiProvider).valueOrNull ?? const [];
  return {for (final e in emoji) e.name: e.id};
});

/// One emoji's image bytes, by emoji id.
///
/// Not `autoDispose`, for the reason above and because the same emoji recurs
/// down a transcript: evicting it the moment it scrolls out would refetch it
/// on the way back. Bounded rather than unbounded, unlike an attachment cache:
/// the set is capped at 500 (`MAX_CUSTOM_EMOJI`, `store/emoji.rs:15`) and each
/// image at 1 MiB (`MAX_IMAGE_BYTES`, `emoji.rs:34`).
///
/// The emoji settings screen builds every row's image widget at once
/// (`emoji_screen.dart`'s `_EmojiRow` list is not lazily built), so importing
/// a pack larger than `Class::Asset`'s burst (`ratelimit/class.rs`, sized for
/// one member page's avatars, not a few hundred emoji at once) fires more
/// concurrent fetches than that budget admits in one instant, and some of
/// them draw a [RateLimitedException] rather than a missing or broken image.
/// Retried with backoff the same way `CanvasSync._fetchPage` retries a
/// rate-limited page fetch, so a burst that trips the limiter resolves once
/// the budget refills, rather than caching that single 429 as this emoji's
/// image forever - which is what a broken-image placeholder that never
/// recovers on reload actually was.
final customEmojiImageProvider = FutureProvider.family<Uint8List, String>((
  ref,
  emojiId,
) async {
  final api = ref.watch(apiProvider);
  var delay = const Duration(milliseconds: 250);
  for (var attempt = 0; ; attempt++) {
    try {
      final fetched = await api.fetchCustomEmojiImage(emojiId);
      return fetched.bytes;
    } on RateLimitedException {
      if (attempt >= 3) rethrow;
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }
});
