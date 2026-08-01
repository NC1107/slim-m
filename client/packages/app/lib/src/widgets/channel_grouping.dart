// SPDX-License-Identifier: Apache-2.0
/// Pure ordering over a channel listing, shared by the rail's sections and
/// the next/previous-channel shortcuts so the two cannot drift apart the way
/// `orderedChannels` and `DirectMessagesSection` once did: this used to
/// duplicate the personal-space split inline, in raw `createdAt` order, so
/// cycling landed on a different channel than the one the rail showed first.
library;

import 'package:slimm_data/data.dart';

import '../providers/dms.dart';

/// [channels] split into the caller's personal space, if present, and every
/// other channel: the first one flagged [Channel.isPersonalSpace] is pulled
/// out, and any channel after it - there should only ever be one - keeps its
/// place in [others] rather than being dropped.
({Channel? personal, List<Channel> others}) splitPersonalSpace(
  List<Channel> channels,
) {
  Channel? personal;
  final others = <Channel>[];
  for (final channel in channels) {
    if (channel.isPersonalSpace && personal == null) {
      personal = channel;
    } else {
      others.add(channel);
    }
  }
  return (personal: personal, others: others);
}

/// [channels] grouped and ordered the way the rail renders them: direct
/// messages (the personal space first, then every other DM in listing
/// order), then text channels, then voice channels, each in its own
/// relative order.
List<Channel> orderedChannels(List<Channel> channels) {
  final dms = splitPersonalSpace(
    channels.where((c) => c.kind == dmChannelKind).toList(),
  );
  return [
    if (dms.personal != null) dms.personal!,
    ...dms.others,
    ...channels.where((c) => c.kind == 'text'),
    ...channels.where((c) => c.kind == 'voice'),
  ];
}

/// Rewrites [fullOrder] (every live, non-DM channel, in the server's one
/// shared position order) so [kind]'s channels take [newKindOrder] while
/// every channel of another kind keeps its exact slot.
///
/// The rail shows text and voice channels as two separate sections, but the
/// server's `position` is one sequence across both, so a drag confined to
/// one section is not itself a valid reorder request - it has to be spliced
/// back into the full order the other section's channels still occupy, or
/// submitting it would silently move every voice channel too.
List<String> spliceKindOrder({
  required List<Channel> fullOrder,
  required String kind,
  required List<String> newKindOrder,
}) {
  var next = 0;
  final result = <String>[];
  for (final channel in fullOrder) {
    if (channel.kind == kind) {
      result.add(newKindOrder[next]);
      next++;
    } else {
      result.add(channel.id);
    }
  }
  return result;
}
