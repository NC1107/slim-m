// SPDX-License-Identifier: Apache-2.0
/// The rail footer's call-summary line: what its status text becomes while a
/// call is live somewhere other than the channel currently on screen.
///
/// Its own file so `channel_rail_frame.dart` carries the merged dock's
/// wiring without also carrying its content.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

import '../routing/routes.dart';
import 'call_participant_tiles.dart';
import 'voice_strip_indicator.dart';

/// Replaces the footer's own name and status while [RailUserFooter] decides
/// a call elsewhere is more worth the row than its usual identity line.
///
/// Tapping it returns to the call's channel: the standalone strip's separate
/// "back to call" button folds into the text it would otherwise sit beside,
/// since a merged row has no room to keep both.
class RailCallSummary extends StatelessWidget {
  const RailCallSummary({
    super.key,
    required this.channelId,
    required this.connectedAt,
    required this.screenSharing,
  });

  final String channelId;
  final DateTime? connectedAt;
  final bool screenSharing;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      button: true,
      label: 'Back to the call',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go(Routes.channel(channelId)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CallChannelName(
              channelId: channelId,
              style: AppText.ui.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.medium,
                height: 1.25,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (connectedAt case final since?) CallDuration(since: since),
                Flexible(
                  child: Text(
                    screenSharing ? ' - sharing' : ' - in call',
                    overflow: TextOverflow.ellipsis,
                    style: AppText.micro.copyWith(
                      color: screenSharing
                          ? tokens.accent
                          : tokens.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
