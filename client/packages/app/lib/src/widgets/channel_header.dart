// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The centre column's channel header: name, topic, pin pill, and the two
/// toggles that live beside it.
///
/// The name outweighs the topic when both compete for space (`Flexible`
/// flex 2 against the topic's implicit 1): the name carries this pane's own
/// identity and the topic is secondary, which flex alone did not enforce
/// while the topic outweighed the name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../screens/canvas/canvas_open_button.dart';
import '../screens/dm_call_button.dart';
import '../routing/breakpoints.dart';
import 'member_pane.dart';
import 'pinned_messages_sheet.dart';
import 'threads_sheet.dart';

class ChannelHeader extends ConsumerWidget {
  const ChannelHeader({
    super.key,
    required this.channelId,
    required this.name,
    required this.isVoice,
    this.isDm = false,
    this.dmParticipantId,
    this.isPersonalSpace = false,
    this.topic,
    required this.searchOpen,
    required this.onToggleSearch,
  });

  final String channelId;
  final String name;

  /// The DM peer's user id, so the header avatar's tint keys off identity
  /// the way every member-naming surface does; see [AppAvatar.tintKey].
  final String? dmParticipantId;
  final bool isVoice;

  /// The self-DM. Its name is "You" (`personalSpaceName`), so it takes the same
  /// notebook glyph the rail's `PersonalSpaceRow` shows rather than an avatar
  /// of those initials. Defaults false; a real DM sets [isDm] instead.
  final bool isPersonalSpace;

  /// A DM has exactly two participants by construction, never the
  /// deployment's roster `membersProvider` answers with, so the toggle for
  /// it hides here rather than opening a pane that implies random Space
  /// members can see a private conversation. Defaults false so every
  /// existing caller (none of them a DM) keeps its toggle.
  final bool isDm;

  /// Null for no topic; the server never stores a blank one.
  final String? topic;
  final bool searchOpen;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final membersVisible = ref.watch(memberPaneVisibleProvider);
    // The pane only docks where LayoutClass.fitsMemberPane says there is
    // room; a toggle shown past that would sit lit over a pane that never appears.
    final canToggleMembers =
        !isDm &&
        LayoutClass.of(
          context,
        ).fitsMemberPane(MediaQuery.sizeOf(context).width);

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
                // A DM is a person: show their avatar like every other member-naming surface. The personal space keeps its notebook, and a text or voice channel its own icon.
                if (isPersonalSpace)
                  Icon(
                    AppIcons.notebook,
                    size: AppSizes.icon16,
                    color: tokens.textSecondary,
                  )
                else if (isDm)
                  AppAvatar(name: name, tintKey: dmParticipantId, size: 24)
                else
                  Icon(
                    isVoice ? AppIcons.voice : AppIcons.hash,
                    size: AppSizes.icon16,
                    color: tokens.textSecondary,
                  ),
                const SizedBox(width: AppSpacing.s8),
                // See the library doc comment above for why flex is 2 here.
                Flexible(
                  flex: 2,
                  child: Text(
                    name,
                    maxLines: 1,
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
          if (!isVoice)
            AppIconButton(
              icon: AppIcons.thread,
              semanticLabel: 'Threads',
              onPressed: () => showThreadsSheet(context, channelId),
            ),
          const SizedBox(width: AppSpacing.s4),
          DmCallButton(channelId: channelId),
          const SizedBox(width: AppSpacing.s4),
          CanvasOpenButton(channelId: channelId, isVoice: isVoice, isDm: isDm),
          const SizedBox(width: AppSpacing.s4),
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
