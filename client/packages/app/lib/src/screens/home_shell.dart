// SPDX-License-Identifier: Apache-2.0
/// The signed-in shell: channel list beside, or instead of, a conversation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../providers/sync_controller.dart';
import '../routing/breakpoints.dart';
import 'channel_screen.dart';

/// Which channel is open. Null means none is selected yet, which on a narrow
/// window is the list on its own.
final selectedChannelProvider = StateProvider<String?>((ref) => null);

/// The shell. One widget handles every width: at compact widths it shows one
/// pane at a time, and above that both at once. The panes themselves are the
/// same widgets either way, so behaviour cannot drift between layouts.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = LayoutClass.of(context);
    final selected = ref.watch(selectedChannelProvider);

    if (layout.showsBothPanes) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: layout == LayoutClass.expanded ? 280 : 240,
              child: const _ChannelList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: selected == null
                  ? const _NothingSelected()
                  : _Conversation(channelId: selected),
            ),
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
            onPressed: () =>
                ref.read(selectedChannelProvider.notifier).state = null,
          ),
          title: _ChannelTitle(channelId: selected),
        ),
        body: ChannelScreen(channelId: selected),
      );
    }
    return const Scaffold(body: _ChannelList());
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ConversationHeader(channelId: channelId),
        Expanded(child: ChannelScreen(channelId: channelId)),
      ],
    );
  }
}

class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({required this.channelId});

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

/// The channel list, with the connection state shown honestly at the bottom.
class _ChannelList extends ConsumerWidget {
  const _ChannelList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final storeAsync = ref.watch(storeProvider);
    final selected = ref.watch(selectedChannelProvider);

    return Container(
      color: tokens.surfaceRaised,
      child: Column(
        children: [
          const _ShellHeader(),
          Expanded(
            child: storeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (store) => StreamBuilder<List<Channel>>(
                stream: store.watchChannels(),
                builder: (context, snapshot) {
                  final channels = snapshot.data ?? const <Channel>[];
                  if (channels.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.s16),
                        child: Text(
                          'No channels yet.',
                          style: TextStyle(color: tokens.textSecondary),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: channels.length,
                    itemBuilder: (context, i) {
                      final channel = channels[i];
                      return _ChannelTile(
                        channel: channel,
                        selected: channel.id == selected,
                        onTap: () => ref
                            .read(selectedChannelProvider.notifier)
                            .state = channel.id,
                      );
                    },
                  );
                },
              ),
            ),
          ),
          const _ConnectionBar(),
        ],
      ),
    );
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader();

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
      child: Text(
        'slim-m',
        style:
            TextStyle(color: tokens.textPrimary, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.selected,
    required this.onTap,
  });

  final Channel channel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          // 48 high keeps the target at the accessibility baseline.
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
          color: selected ? tokens.accent.withValues(alpha: 0.12) : null,
          child: Row(
            children: [
              Icon(
                channel.kind == 'voice' ? AppIcons.voice : AppIcons.hash,
                size: 16,
                color: selected ? tokens.accent : tokens.textSecondary,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  channel.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? tokens.textPrimary : tokens.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Says plainly whether messages are arriving. Silently going stale is worse
/// than admitting the connection dropped.
class _ConnectionBar extends ConsumerWidget {
  const _ConnectionBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;
    if (status == SyncStatus.live) return const SizedBox.shrink();

    final label = switch (status) {
      SyncStatus.connecting => 'Connecting',
      SyncStatus.offline => 'Offline, retrying',
      SyncStatus.live => '',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Semantics(
        liveRegion: true,
        child: Text(
          label,
          style: TextStyle(color: tokens.textSecondary, fontSize: 12),
        ),
      ),
    );
  }
}
