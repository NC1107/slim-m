// SPDX-License-Identifier: Apache-2.0
/// The one message-search call both `ChannelSearchController` (the in-channel
/// search bar) and the command palette's message section make.
///
/// The two had already diverged once - both called `searchMessages` and both
/// independently filtered blocked authors, but only the controller told a 403
/// apart from any other failure. Centralising the call is what stops that
/// happening again: a caller gets both the filtering and the error
/// distinction for free, rather than having to remember to copy them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'blocks_controller.dart';
import 'providers.dart';

/// What running a message search came back with.
///
/// [MessageSearchForbidden] is not transient: the same query fails again
/// until the caller's permissions change, unlike [MessageSearchFailed], which
/// is worth a retry.
sealed class MessageSearchResult {
  const MessageSearchResult();
}

/// Hits with any blocked author already dropped.
class MessageSearchHits extends MessageSearchResult {
  const MessageSearchHits(this.messages);
  final List<api.Message> messages;
}

/// The caller may not search this channel at all.
class MessageSearchForbidden extends MessageSearchResult {
  const MessageSearchForbidden();
}

/// Some other failure; worth a retry.
class MessageSearchFailed extends MessageSearchResult {
  const MessageSearchFailed();
}

/// The one method this needs off `Ref`/`WidgetRef`: reading a provider once.
/// Taking this instead of either ref type directly is what lets both
/// `ChannelSearchController` (a `Ref`) and the command palette (a
/// `WidgetRef`) call the same helper - the two share no common supertype in
/// this Riverpod version, but their `read` methods have identical signatures.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Searches [channelId] for [query] and drops any hit from a blocked author,
/// the same filtering the transcript, pins and typing already apply.
Future<MessageSearchResult> searchChannelMessages(
  ProviderReader read,
  String channelId,
  String query, {
  int? limit,
}) async {
  try {
    final hits = await read(
      apiProvider,
    ).searchMessages(channelId, q: query, limit: limit);
    final blocks = read(blocksProvider);
    return MessageSearchHits(
      hits
          .where((message) => !blocks.contains(message.authorId))
          .toList(growable: false),
    );
  } on api.ForbiddenException {
    return const MessageSearchForbidden();
  } on api.ApiException {
    return const MessageSearchFailed();
  }
}
