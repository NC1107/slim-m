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

/// Turns a DM listing into the same [api.Channel] shape an ordinary channel
/// arrives as. The server stores a DM channel's own `name` as empty (a DM
/// has no name of its own), so the other participant's display name stands
/// in for it here; every screen that shows a channel's name already reads it
/// off the local store rather than the server's channel list, so this is
/// the only place that substitution needs to happen.
api.Channel channelFromDm(api.DmConversation dm) => api.Channel(
  id: dm.channelId,
  name: dm.user.displayName,
  kind: dmChannelKind,
  createdAt: dm.createdAt,
);

/// Opens (or returns) the DM with [userId] and gets it into the local store,
/// so the screen this navigates to has a name and kind to render
/// immediately rather than waiting on the next reconnect's channel refresh.
///
/// Takes a [ProviderContainer] rather than a [WidgetRef]: a caller that
/// dismisses its own surface before this answers (the member popover's
/// "Message" row) needs a handle that outlives that surface, and a container
/// is exactly that.
Future<String> openDirectMessage(
  ProviderContainer container,
  String userId,
) async {
  final conversation = await container
      .read(apiProvider)
      .openDirectMessage(userId);
  final store = await container.read(storeProvider.future);
  await store.upsertChannels([channelFromDm(conversation)]);
  return conversation.channelId;
}
