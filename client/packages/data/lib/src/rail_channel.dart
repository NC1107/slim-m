// SPDX-License-Identifier: Apache-2.0
/// The channel-rail projection `MessageStore.watchRailChannels` dedupes
/// against - split out once adding it to `message_store.dart` crossed the
/// review budget.
library;

import 'database.dart';

/// The fields of a [Channel] the channel rail draws from: what
/// `channel_rail.dart` and its row widgets render or group by. Records
/// compare structurally, so two keys are `==` exactly when the rail would
/// render them identically.
///
/// `unread` is the derived boolean the rail shows, not the raw
/// `cursor`/`lastReadSeq` behind it: a channel already unread stays unread
/// through every further message, so only the flip in or out of that state
/// belongs in the key.
typedef RailChannelKey = ({
  String id,
  String name,
  String kind,
  int position,
  String? categoryId,
  bool isPersonalSpace,
  String? dmParticipantId,
  bool unread,
});

RailChannelKey railChannelKey(Channel channel) => (
      id: channel.id,
      name: channel.name,
      kind: channel.kind,
      position: channel.position,
      categoryId: channel.categoryId,
      isPersonalSpace: channel.isPersonalSpace,
      dmParticipantId: channel.dmParticipantId,
      unread: channel.cursor > channel.lastReadSeq,
    );

/// `Stream.distinct`'s callback for `MessageStore.watchRailChannels`: true
/// drops the newer emission, so this is true when [a] and [b] would draw
/// the same rail, row for row and in the same order.
bool railChannelsUnchanged(List<Channel> a, List<Channel> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (railChannelKey(a[i]) != railChannelKey(b[i])) return false;
  }
  return true;
}
