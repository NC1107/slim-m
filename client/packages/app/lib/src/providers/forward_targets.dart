// SPDX-License-Identifier: Apache-2.0
/// Where a message may be forwarded to: every ordinary channel the caller
/// holds SEND_MESSAGES in, plus every DM they have open, each already
/// resolved to a channel id the ordinary send route works on unchanged.
///
/// Forwarding has no wire shape of its own - see `buildForwardedContent`
/// in `widgets/forward_message.dart` for why a plain send with a client-side
/// quote block is the honest design rather than stretching `reply_to_id`
/// across channels, which the server refuses outright
/// (`SendError::InvalidReplyTarget` in `crates/slimm-server/src/store/
/// messages.rs`: a reply's parent must exist in the exact same channel).
/// This file exists only to answer "where can this go", the one question a
/// forward genuinely needs the server for.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Unprefixed: `listChannels`/`listDirectMessages` are extension methods, only
// visible where the library declaring them is imported - see api.dart's own
// `show` list comment.
import 'package:slimm_api/api.dart';

import '../permissions.dart';
import 'blocks_controller.dart';
import 'dms.dart' show personalSpaceName;
import 'providers.dart';

/// One place a message could be forwarded to.
class ForwardTarget {
  const ForwardTarget({
    required this.channelId,
    required this.label,
    required this.isDm,
  });

  final String channelId;

  /// The channel's own name, or the DM partner's display name (or
  /// [personalSpaceName] for the caller's own personal space).
  final String label;

  /// Whether this is a DM rather than an ordinary channel - the picker's own
  /// choice of leading glyph, nothing that changes how a send to it works.
  final bool isDm;
}

/// Every target for forwarding a message currently in [excludeChannelId] -
/// forwarding into the channel a message already sits in is excluded, since
/// that would just be a duplicate of a message already on screen.
///
/// Fetched fresh on every watch, matching `myVisibleChannelsProvider` and
/// `invitesProvider`: this is a picker's own one-shot list, not long-lived
/// state a live event needs to keep current.
final forwardTargetsProvider = FutureProvider.autoDispose
    .family<List<ForwardTarget>, String>((ref, excludeChannelId) async {
      final client = ref.watch(apiProvider);
      final channels = await client.listChannels();
      final dms = await client.listDirectMessages();
      final blocked = ref.watch(blocksProvider).ids;
      final selfId = ref.watch(sessionProvider).tokens?.userId;

      return [
        for (final channel in channels)
          if (channel.id != excludeChannelId &&
              (channel.permissions ?? 0).hasPermission(Perm.sendMessages))
            ForwardTarget(
              channelId: channel.id,
              label: channel.name,
              isDm: false,
            ),
        for (final dm in dms)
          // A blocked party's DM is frozen server-side in both directions
          // (`store/dms.rs`'s `BLOCKED_DENY`), so offering it here would be a
          // row that looks reachable and would just come back a 403.
          if (dm.channelId != excludeChannelId && !blocked.contains(dm.user.id))
            ForwardTarget(
              channelId: dm.channelId,
              label: dm.user.id == selfId
                  ? personalSpaceName
                  : dm.user.displayName,
              isDm: true,
            ),
      ];
    });
