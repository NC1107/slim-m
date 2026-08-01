// SPDX-License-Identifier: Apache-2.0
/// The centre column's channel header: name, topic, pin pill, and the two
/// toggles that live beside it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../screens/canvas/canvas_open_button.dart';
import '../routing/breakpoints.dart';
import 'member_pane.dart';
import 'channel_rail.dart';
import 'pinned_messages_sheet.dart';

class ChannelHeader extends ConsumerWidget {
  const ChannelHeader({
    super.key,
    required this.channelId,
    required this.name,
    required this.isVoice,
    this.topic,
    required this.searchOpen,
    required this.onToggleSearch,
  });

  final String channelId;
  final String name;
  final bool isVoice;

  /// Null for no topic; the server never stores a blank one.
  final String? topic;
  final bool searchOpen;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final membersVisible = ref.watch(memberPaneVisibleProvider);
    // The member pane only exists at expanded width, so the toggle only does
    // there; at medium width it would sit lit over a pane that never appears.
    final canToggleMembers = LayoutClass.of(context) == LayoutClass.expanded;

    return Container(
      height: 52,
      // Matches the message rows and composer below it.
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.paneGutter),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        children: [
          // One Expanded around the whole title block, not a Flexible name
          // beside a Spacer: two flex children split the free space evenly,
          // which left the actions mid-pane with dead air to their right.
          Expanded(
            child: Row(
              children: [
                Icon(
                  isVoice ? AppIcons.voice : AppIcons.hash,
                  size: AppSizes.icon16,
                  color: tokens.textSecondary,
                ),
                const SizedBox(width: AppSpacing.s8),
                Flexible(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    // The design's 17px header left the scale
                    // (app_typography.dart): it differed from body only in
                    // weight, so weight alone carries it.
                    style: AppText.body.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: AppWeights.medium,
                    ),
                  ),
                ),
                if (topic != null && topic!.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.s12),
                  Container(width: 1, height: 20, color: tokens.borderSubtle),
                  const SizedBox(width: AppSpacing.s12),
                  Flexible(
                    flex: 2,
                    child: Text(
                      topic!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          AppIconButton(
            icon: AppIcons.pin,
            semanticLabel: 'Pinned messages',
            onPressed: () => showPinnedMessagesSheet(context, channelId),
          ),
          const SizedBox(width: AppSpacing.s4),
          CanvasOpenButton(channelId: channelId),
          const SizedBox(width: AppSpacing.s4),
          if (canToggleMembers)
            AppIconButton(
              icon: AppIcons.sidebar,
              semanticLabel: 'Toggle channel list',
              active: ref.watch(channelRailVisibleProvider),
              onPressed: () =>
                  ref.read(channelRailVisibleProvider.notifier).state = !ref
                      .read(channelRailVisibleProvider),
            ),
          if (canToggleMembers) const SizedBox(width: AppSpacing.s4),
          AppIconButton(
            icon: AppIcons.search,
            semanticLabel: 'Search messages',
            active: searchOpen,
            onPressed: onToggleSearch,
          ),
          if (canToggleMembers) ...[
            const SizedBox(width: AppSpacing.s4),
            AppIconButton(
              icon: AppIcons.members,
              semanticLabel: 'Toggle member list',
              active: membersVisible,
              onPressed: () =>
                  ref.read(memberPaneVisibleProvider.notifier).state =
                      !membersVisible,
            ),
          ],
        ],
      ),
    );
  }
}
