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
