// SPDX-License-Identifier: Apache-2.0
/// The conversation's app bar at compact width.
///
/// `ChannelHeader` is only built when both panes show (see
/// `channel_screen.dart`), and it is the sole host of in-channel search, the
/// channel topic, the pinned-messages sheet and the member list. On a phone
/// that header never exists, so all four were unreachable. This is the same
/// four affordances laid into the app bar the compact layout already has,
/// driving the same providers and the same sheet rather than a second copy
/// of any of them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/channel_search_controller.dart';
import '../providers/pins_controller.dart';
import '../providers/providers.dart';
import '../screens/canvas/canvas_open_button.dart';
import '../screens/dm_call_button.dart';
import 'channel_notification_menu_button.dart';
import 'pinned_messages_sheet.dart';
import 'threads_sheet.dart';

/// The compact conversation app bar: back, the channel's name and topic, and
/// the search, pins and members actions.
///
/// The member action opens the scaffold's end drawer, which is where
/// [AppMemberPane] lives at this width; there is no room to dock it beside
/// the conversation, so the expanded layout's visibility toggle would have
/// nothing to show.
class CompactChannelAppBar extends ConsumerWidget
    implements PreferredSizeWidget {
  const CompactChannelAppBar({
    super.key,
    required this.channelId,
    required this.onBack,
  });

  final String channelId;
  final VoidCallback onBack;

  /// 48 rather than kToolbarHeight's 56: the bar carries one line and three
  /// icons, and on a phone it sits under a 59pt status inset already.
  static const double height = 48;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final storeAsync = ref.watch(storeProvider);
    return storeAsync.maybeWhen(
      orElse: () => _bar(null, tokens),
      data: (store) => StreamBuilder<List<Channel>>(
        stream: store.watchChannels(),
        builder: (context, snapshot) => _bar(
          snapshot.data
              ?.where((c) => c.id == channelId)
              .cast<Channel?>()
              .firstOrNull,
          tokens,
        ),
      ),
    );
  }

  // `ChannelHeader` and the wide voice header draw this hairline on a `Container`; a Material `AppBar` needs its own.
  AppBar _bar(Channel? channel, AppTokens tokens) {
    final isVoice = channel?.kind == 'voice';
    // See `ChannelHeader.isDm`'s own doc comment for why.
    final isDm = channel?.kind == 'dm';
    return AppBar(
      toolbarHeight: height,
      shape: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      leading: IconButton(
        icon: const Icon(AppIcons.back),
        tooltip: 'Back to channels',
        onPressed: onBack,
      ),
      titleSpacing: 0,
      title: _Title(
        name: channel?.name ?? '',
        topic: channel?.topic,
        isVoice: isVoice,
      ),
      // A voice channel has neither a message to find nor a message to pin,
      // so those two would be controls that cannot do anything.
      actions: [
        if (!isVoice) ChannelSearchAction(channelId: channelId),
        if (!isVoice) _PinsAction(channelId: channelId),
        if (!isVoice) _ThreadsAction(channelId: channelId),
        DmCallButton(channelId: channelId),
        CanvasOpenButton(channelId: channelId, isVoice: isVoice),
        ChannelNotificationMenuButton(channelId: channelId),
        if (!isDm) const _MembersAction(),
        const SizedBox(width: AppSpacing.s8),
      ],
    );
  }
}

/// Name over topic, the same two pieces of text the wide header puts side by
/// side. One line each: the toolbar is 56 high, which two lines of body text
/// would not fit, and a long topic ellipsizes here exactly as it does there.
class _Title extends StatelessWidget {
  const _Title({
    required this.name,
    required this.topic,
    required this.isVoice,
  });

  final String name;
  final String? topic;
  final bool isVoice;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final topic = this.topic;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
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
                style: AppText.body.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: AppWeights.medium,
                ),
              ),
            ),
          ],
        ),
        if (topic != null && topic.isNotEmpty)
          Text(
            topic,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
      ],
    );
  }
}

/// The search toggle, shared with `thread_screen.dart`'s `ThreadScreen`
/// since a thread's messages are searchable the same way a real channel's are.
class ChannelSearchAction extends ConsumerWidget {
  const ChannelSearchAction({super.key, required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(
      channelSearchProvider(channelId).select((s) => s.open),
    );
    return AppIconButton(
      icon: AppIcons.search,
      semanticLabel: 'Search messages',
      tooltip: 'Search',
      active: open,
      touch: true,
      onPressed: () =>
          ref.read(channelSearchProvider(channelId).notifier).toggle(),
    );
  }
}

/// The pill's live count has nowhere to sit in a toolbar, so it goes into the
/// accessible name instead of being dropped.
class _PinsAction extends ConsumerWidget {
  const _PinsAction({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pins = ref.watch(pinsControllerProvider(channelId));
    return AppIconButton(
      icon: AppIcons.pin,
      semanticLabel: pins.pinned == null
          ? 'Pinned messages, loading'
          : 'Pinned messages, ${pins.pinned!.length}',
      tooltip: 'Pinned messages',
      touch: true,
      onPressed: () => showPinnedMessagesSheet(context, channelId),
    );
  }
}

/// Unlike [_PinsAction] this carries no live count in its accessible name:
/// `threadsListProvider` is only fetched once the sheet actually opens (see
/// `providers/threads.dart`'s own doc comment on why it is not wired to a
/// live event), so there is nothing cheap to read here ahead of that.
class _ThreadsAction extends StatelessWidget {
  const _ThreadsAction({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context) => AppIconButton(
    icon: AppIcons.thread,
    semanticLabel: 'Threads',
    tooltip: 'Threads',
    touch: true,
    onPressed: () => showThreadsSheet(context, channelId),
  );
}

class _MembersAction extends StatelessWidget {
  const _MembersAction();

  @override
  Widget build(BuildContext context) => AppIconButton(
    icon: AppIcons.members,
    semanticLabel: 'Show members',
    tooltip: 'Members',
    touch: true,
    onPressed: () => Scaffold.of(context).openEndDrawer(),
  );
}
