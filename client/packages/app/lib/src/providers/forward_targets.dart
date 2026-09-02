// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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
// Unprefixed extension methods need the declaring library imported - see api.dart's own `show` list comment.
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
    this.userId,
    this.avatarUpdatedAt,
  });

  final String channelId;

  /// The channel's own name, or the DM partner's display name (or
  /// [personalSpaceName] for the caller's own personal space).
  final String label;

  /// Whether this is a DM rather than an ordinary channel - the picker's own
  /// choice of leading glyph, nothing that changes how a send to it works.
  final bool isDm;

  /// The DM partner, so the picker can draw their real picture rather than a
  /// generic person glyph. Null for an ordinary channel, which has none.
  final String? userId;

  /// Cache-busts that picture the way every other avatar in the app does;
  /// without it a changed picture keeps showing the old bytes here.
  final int? avatarUpdatedAt;
}

/// What [forwardTargetsProvider] needs to answer "where can this go": the
/// channel the message already sits in, and whether it carries attachments.
///
/// A record, not a plain `String` key: once forwarding could carry
/// attachments, a channel offering SEND_MESSAGES but not ATTACH_FILES had to
/// stop being offered for those messages specifically, since the send would
/// otherwise reach this list only to 403 on the one permission this provider
/// used to never ask about (`http/messages.rs`'s `send` only demands
/// ATTACH_FILES when the request actually carries an attachment id).
typedef ForwardTargetsQuery = ({String excludeChannelId, bool hasAttachments});

/// Every target for forwarding a message currently in
/// [ForwardTargetsQuery.excludeChannelId] - forwarding into the channel a
/// message already sits in is excluded, since that would just be a
/// duplicate of a message already on screen.
///
/// Fetched fresh on every watch, matching `myVisibleChannelsProvider` and
/// `invitesProvider`: this is a picker's own one-shot list, not long-lived
/// state a live event needs to keep current.
final forwardTargetsProvider = FutureProvider.autoDispose
    .family<List<ForwardTarget>, ForwardTargetsQuery>((ref, query) async {
      final client = ref.watch(apiProvider);
      final channels = await client.listChannels();
      final dms = await client.listDirectMessages();
      final blocked = ref.watch(blocksProvider).ids;
      final selfId = ref.watch(sessionProvider).tokens?.userId;

      return [
        for (final channel in channels)
          if (channel.id != query.excludeChannelId &&
              (channel.permissions ?? 0).hasPermission(Perm.sendMessages) &&
              (!query.hasAttachments ||
                  (channel.permissions ?? 0).hasPermission(Perm.attachFiles)))
            ForwardTarget(
              channelId: channel.id,
              label: channel.name,
              isDm: false,
            ),
        for (final dm in dms)
          // `store/dms.rs`: a blocked party is denied SEND_MESSAGES/ATTACH_FILES both ways, and otherwise a DM always grants both to its two participants, so attachments need no extra check here.
          if (dm.channelId != query.excludeChannelId &&
              !blocked.contains(dm.user.id))
            ForwardTarget(
              channelId: dm.channelId,
              label: dm.user.id == selfId
                  ? personalSpaceName
                  : dm.user.displayName,
              isDm: true,
              userId: dm.user.id,
              avatarUpdatedAt: dm.user.avatarUpdatedAt,
            ),
      ];
    });
