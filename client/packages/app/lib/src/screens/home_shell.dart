// SPDX-License-Identifier: Apache-2.0
/// The signed-in shell: channel rail beside, or instead of, a conversation,
/// plus the member pane at expanded width.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../routing/breakpoints.dart';
import '../routing/routes.dart';
import '../widgets/channel_rail.dart';
import '../widgets/command_palette.dart';
import '../widgets/compact_channel_app_bar.dart';
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
    // Never below expanded width, whatever the header toggle says: it can only
    // hide the pane, not summon room for it that is not there.
    final showMembers =
        layout == LayoutClass.expanded && ref.watch(memberPaneVisibleProvider);

    final Widget scaffold;
    if (layout.showsBothPanes) {
      scaffold = Scaffold(
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
    } else if (selected != null) {
      // Compact: the conversation replaces the list, with a way back.
      scaffold = Scaffold(
        appBar: CompactChannelAppBar(
          channelId: selected,
          onBack: () => context.go(Routes.channels),
        ),
        // The roster slides in from the right instead of docking beside the
        // conversation, which is the only pane there is at this width.
        endDrawer: const Drawer(
          width: AppMemberPane.width,
          child: SafeArea(child: AppMemberPane()),
        ),
        body: child,
      );
    } else {
      scaffold = const Scaffold(body: ChannelRail());
    }

    // Binds the shared shortcut table's own key rather than a second,
    // hardcoded `Ctrl K`, so a remap of quickSwitch is honoured here too.
    final quickSwitch = activatorFor(AppAction.quickSwitch);
    return CallbackShortcuts(
      bindings: {
        if (quickSwitch != null) quickSwitch: () => openCommandPalette(context),
      },
      // CallbackShortcuts only fires for a focused descendant, so this default
      // makes the shortcut work the instant the app opens.
      child: Focus(autofocus: true, child: scaffold),
    );
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
/// [ChannelScreen] renders its own full header (search, the pin pill, the
/// member-pane toggle) at any width that shows it. At compact width there is
/// no room for one, and [CompactChannelAppBar] carries the same four
/// affordances instead. Voice channels have no header of their own either
/// way, so this still supplies a minimal one at wide layouts, as before.
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
              Icon(
                channel?.kind == 'voice' ? AppIcons.voice : AppIcons.hash,
                size: 16,
              ),
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
