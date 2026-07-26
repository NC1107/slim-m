// SPDX-License-Identifier: Apache-2.0
/// The signed-in shell: channel list beside, or instead of, a conversation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../providers/sync_controller.dart';
import '../routing/breakpoints.dart';
import '../routing/routes.dart';
import 'channel_screen.dart';

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
    final selected = _selectedChannel(context);

    if (layout.showsBothPanes) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: layout == LayoutClass.expanded ? 280 : 240,
              child: const _ChannelList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
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
    return const Scaffold(body: _ChannelList());
  }

  /// The open channel, read from the route rather than held in state, so a
  /// deep link and an in-app tap land in exactly the same place.
  static String? _selectedChannel(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final prefix = '${Routes.channels}/';
    if (!path.startsWith(prefix)) return null;
    final id = path.substring(prefix.length);
    return id.isEmpty ? null : id;
  }
}

/// Shown in the conversation pane when nothing is open.
class NoChannelSelected extends StatelessWidget {
  const NoChannelSelected({super.key});

  @override
  Widget build(BuildContext context) => const _NothingSelected();
}

/// The routed conversation pane.
class ConversationPane extends StatelessWidget {
  const ConversationPane({required this.channelId, super.key});

  final String channelId;

  @override
  Widget build(BuildContext context) {
    // On a narrow window the shell supplies its own header via the app bar.
    final layout = LayoutClass.of(context);
    if (!layout.showsBothPanes) return ChannelScreen(channelId: channelId);
    return _Conversation(channelId: channelId);
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
    final selected = HomeShell._selectedChannel(context);

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
                        // Derived from the read marker, so it cannot drift.
                        unread: channel.cursor > channel.lastReadSeq
                            ? channel.cursor - channel.lastReadSeq
                            : 0,
                        onTap: () => context.go(Routes.channel(channel.id)),
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
    required this.unread,
    required this.onTap,
  });

  final Channel channel;
  final bool selected;
  final int unread;
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
              if (unread > 0) _UnreadBadge(count: unread),
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

/// A count of messages past the read marker. Capped in presentation, because
/// "99+" is as actionable as an exact four-digit number and much easier to read.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      label: '$count unread',
      child: Container(
        margin: const EdgeInsets.only(left: AppSpacing.s8),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: tokens.accent,
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: TextStyle(
            color: tokens.surfaceBase,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
