// SPDX-License-Identifier: Apache-2.0
/// The rail footer's call-elsewhere row: a way back to a call live in a
/// channel other than the one currently on screen, plus a way to leave it
/// without navigating there first.
///
/// Its own file so `channel_rail_frame.dart` carries the footer's wiring
/// without also carrying this row's content.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../routing/routes.dart';
import '../screens/dm_call_pane.dart';
import 'call_participant_tiles.dart';

/// A second row under the footer's usual identity line, appearing only
/// while [RailUserFooter] decides a call elsewhere is worth surfacing.
///
/// Given its own row rather than squeezed into the identity row's width: a
/// shared row left the channel name, duration and share cue fighting four
/// icon buttons for 45-53pt, well under the 41pt the share cue needs on its
/// own. Mic and deafen stay on the identity row (they are not repeated
/// here); leave is, since nothing else in the footer offers it.
class RailCallSummary extends ConsumerStatefulWidget {
  const RailCallSummary({
    super.key,
    required this.channelId,
    required this.connectedAt,
    required this.screenSharing,
    required this.onLeave,
  });

  final String channelId;
  final DateTime? connectedAt;
  final bool screenSharing;
  final VoidCallback onLeave;

  @override
  ConsumerState<RailCallSummary> createState() => _RailCallSummaryState();
}

class _RailCallSummaryState extends ConsumerState<RailCallSummary> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final store = ref.watch(storeProvider).valueOrNull;

    return StreamBuilder<List<Channel>>(
      stream: store?.watchChannels() ?? const Stream.empty(),
      builder: (context, snapshot) {
        final name =
            snapshot.data
                ?.where((c) => c.id == widget.channelId)
                .map((c) => c.name)
                .firstOrNull ??
            'a call';

        return Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Back to the call in $name',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => setState(() => _pressed = true),
                  onTapUp: (_) => setState(() => _pressed = false),
                  onTapCancel: () => setState(() => _pressed = false),
                  onTap: () {
                    AppHaptics.selection();
                    // A no-op for a real voice channel; load-bearing for a DM.
                    ref.read(dmCallOpenProvider.notifier).state =
                        widget.channelId;
                    context.go(Routes.channel(widget.channelId));
                  },
                  child: AnimatedOpacity(
                    opacity: _pressed ? 0.6 : 1,
                    duration: AppMotion.reduced(context, AppMotion.fast),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.ui.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: AppWeights.medium,
                            height: 1.25,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.connectedAt case final since?)
                              CallDuration(since: since),
                            Flexible(
                              child: Text(
                                widget.screenSharing
                                    ? ' - sharing'
                                    : ' - in call',
                                overflow: TextOverflow.ellipsis,
                                style: AppText.micro.copyWith(
                                  color: widget.screenSharing
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
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            AppIconButton(
              icon: AppIcons.leaveCall,
              semanticLabel: 'Leave call',
              tooltip: 'Leave call',
              variant: AppIconButtonVariant.danger,
              // Instant: the in-call bar's own leave button asks nothing either.
              onPressed: widget.onLeave,
            ),
          ],
        );
      },
    );
  }
}
