// SPDX-License-Identifier: Apache-2.0
/// Direct-message conversations.
///
/// A DM is an ordinary channel once opened (`GET /channels/{id}/messages`,
/// search, and `/sync` all work on it unchanged), so this file does not give
/// DMs a parallel data model. It exists only to get one into the local store
/// under the same [api.Channel] shape every other channel arrives as.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'providers.dart';

/// The wire kind a DM channel's local row is stored under. Matches the
/// server's own `kind = 'dm'` column value (see `store/dms.rs`), so a
/// restored local row and a freshly synced one agree.
const String dmChannelKind = 'dm';

/// The name a personal space's channel row is given locally: a DM opened with
/// yourself (`store/dms.rs` no longer refuses `caller == target`), used for
/// private notes that still sync across every signed-in device the way any
/// other channel does. [channelFromDm] is the only place a `dm`-kind
/// channel's name is ever written locally, so this string can only land on
/// the row it actually names.
const String personalSpaceName = 'Notes to self';

/// Turns a DM listing into the same [api.Channel] shape an ordinary channel
/// arrives as. The server stores a DM channel's own `name` as empty (a DM
/// has no name of its own), so the other participant's display name stands
/// in for it here - except when that participant is the caller: a personal
/// space labelled with your own name would read as a DM with yourself
/// rather than what it is. Every screen that shows a channel's name already
/// reads it off the local store rather than the server's channel list, so
/// this is the only place that substitution needs to happen.
api.Channel channelFromDm(api.DmConversation dm, {required String? selfId}) =>
    api.Channel(
      id: dm.channelId,
      name: dm.user.id == selfId ? personalSpaceName : dm.user.displayName,
      kind: dmChannelKind,
      createdAt: dm.createdAt,
    );

/// Opens (or returns) the DM with [userId] - or, passing your own id, your
/// personal space - and gets it into the local store, so the screen this
/// navigates to has a name and kind to render immediately rather than
/// waiting on the next reconnect's channel refresh.
///
/// Takes a [ProviderContainer] rather than a [WidgetRef]: a caller that
/// dismisses its own surface before this answers (the member popover's
/// "Message" row) needs a handle that outlives that surface, and a container
/// is exactly that.
Future<String> openDirectMessage(
  ProviderContainer container,
  String userId,
) async {
  final client = container.read(apiProvider);
  final conversation = await client.openDirectMessage(userId);
  final store = await container.read(storeProvider.future);
  await store.upsertChannels([
    channelFromDm(conversation, selfId: client.session.tokens?.userId),
  ]);
  return conversation.channelId;
}
