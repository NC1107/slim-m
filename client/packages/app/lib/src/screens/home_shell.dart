// SPDX-License-Identifier: Apache-2.0
/// The signed-in shell: channel rail beside, or instead of, a conversation,
/// plus the member pane at expanded width.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../routing/breakpoints.dart';
import '../routing/routes.dart';
import '../widgets/channel_rail.dart';
import '../widgets/member_pane.dart';
import 'channel_screen.dart';
import 'voice_screen.dart';

/// The shell. One widget handles every width: at compact widths it shows one
/// pane at a time, and above that both at once. The panes themselves are the
/// same widgets either way, so behaviour cannot drift between layouts.
class HomeShell extends ConsumerWidget {
  const HomeShell({required this.child, super.key});

  /// The routed pane: either the empty state or a conversation.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = LayoutClass.of(context);
    final selected = selectedChannelId(context);
    // The member pane never shows below expanded width, whatever the toggle
    // in the channel header says; the toggle can only hide it, not summon
    // room for it that is not there.
    final showMembers =
        layout == LayoutClass.expanded && ref.watch(memberPaneVisibleProvider);

    if (layout.showsBothPanes) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: layout == LayoutClass.expanded
                  ? ChannelRail.expandedWidth
                  : ChannelRail.mediumWidth,
              child: const ChannelRail(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
            if (showMembers) const AppMemberPane(),
          ],
        ),
      );
    }

    // Compact: the conversation replaces the list, with a way back.
    if (selected != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(AppIcons.back),
            tooltip: 'Back to channels',
            onPressed: () => context.go(Routes.channels),
          ),
          title: _ChannelTitle(channelId: selected),
        ),
        body: child,
      );
    }
    return const Scaffold(body: ChannelRail());
  }
}

/// Shown in the conversation pane when nothing is open.
class NoChannelSelected extends StatelessWidget {
  const NoChannelSelected({super.key});

  @override
  Widget build(BuildContext context) => const _NothingSelected();
}

/// The routed conversation pane: a text channel reads, a voice channel
/// calls, decided from the local store so it needs no round trip to know
/// which to show.
///
/// [ChannelScreen] owns and renders its own full header (search, the pin
/// pill, the member-pane toggle) at any width that shows it, since only that
/// screen holds the state (search open or not) the header needs. Voice
/// channels have no such header of their own, so this still supplies a
/// minimal one here at wide layouts, unchanged from before.
class ConversationPane extends ConsumerWidget {
  const ConversationPane({required this.channelId, super.key});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = LayoutClass.of(context);
    final storeAsync = ref.watch(storeProvider);

    return storeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (store) => StreamBuilder<List<Channel>>(
        stream: store.watchChannels(),
        builder: (context, snapshot) {
          final channel = snapshot.data
              ?.where((c) => c.id == channelId)
              .cast<Channel?>()
              .firstOrNull;
          final isVoice = channel?.kind == 'voice';
          final body = isVoice
              ? VoiceScreen(channelId: channelId)
              : ChannelScreen(channelId: channelId);

          if (!layout.showsBothPanes || !isVoice) return body;
          return Column(
            children: [
              _VoiceConversationHeader(channelId: channelId),
              Expanded(child: body),
            ],
          );
        },
      ),
    );
  }
}

class _VoiceConversationHeader extends StatelessWidget {
  const _VoiceConversationHeader({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      alignment: Alignment.centerLeft,
      child: _ChannelTitle(channelId: channelId),
    );
  }
}

class _ChannelTitle extends ConsumerWidget {
  const _ChannelTitle({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(storeProvider);
    return storeAsync.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (store) => StreamBuilder<List<Channel>>(
        stream: store.watchChannels(),
        builder: (context, snapshot) {
          final channel = snapshot.data
              ?.where((c) => c.id == channelId)
              .cast<Channel?>()
              .firstWhere((c) => true, orElse: () => null);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(channel?.kind == 'voice' ? AppIcons.voice : AppIcons.hash,
                  size: 16),
              const SizedBox(width: AppSpacing.s8),
              Text(
                channel?.name ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Center(
      child: Text(
        'Pick a channel to start reading.',
        style: TextStyle(color: tokens.textSecondary),
      ),
    );
  }
}
