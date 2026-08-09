// SPDX-License-Identifier: Apache-2.0
/// The signed-in shell: channel rail beside, or instead of, a conversation,
/// plus the member pane wherever it has room to dock
/// ([LayoutClass.fitsMemberPane]).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

import 'package:go_router/go_router.dart';

import '../providers/blocks_controller.dart';
import '../providers/composer_focus.dart';
import '../providers/notification_sound_controller.dart';
import '../providers/providers.dart';
import '../providers/voice_controller.dart';
import '../routing/breakpoints.dart';
import '../routing/routes.dart';
import '../widgets/channel_grouping.dart';
import '../widgets/channel_rail.dart';
import '../widgets/channel_rail_drawer.dart';
import '../widgets/channel_rail_frame.dart';
import '../widgets/command_palette.dart';
import '../widgets/compact_channel_app_bar.dart';
import '../widgets/member_pane.dart';
import '../widgets/rail_drag_handle.dart';
import '../widgets/voice_strip_indicator.dart';
import '../widgets/whats_new_gate.dart';
import 'canvas/canvas_open_button.dart';
import 'canvas/canvas_pane.dart';
import 'channel_screen.dart';
import 'dm_call_pane.dart';
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
    final width = MediaQuery.sizeOf(context).width;
    final selected = selectedChannelId(context);
    // With the shell, or the first surface to consult it filters against none.
    ref.watch(blocksProvider);
    // Forces creation for the session; nothing here reads its own state.
    ref.watch(notificationSoundControllerProvider);
    // CanvasBar is the only header while open (ConversationPane's doc); the compact app bar below would otherwise stack a second one above it.
    final canvasOpen =
        selected != null && ref.watch(canvasOpenProvider) == selected;
    // DmCallBar is the same: a DM's call pane replaces the header too.
    final dmCallOpen =
        selected != null && ref.watch(dmCallOpenProvider) == selected;
    // Whatever the header toggle says: it can only hide the pane, not summon
    // room for it that is not there (see LayoutClass.fitsMemberPane's doc).
    final membersFit = layout.fitsMemberPane(width);
    final showMembers = membersFit && ref.watch(memberPaneVisibleProvider);
    final showRail = ref.watch(channelRailVisibleProvider);

    final railWidth = layout == LayoutClass.expanded
        ? ChannelRail.expandedWidth
        : ChannelRail.mediumWidth;

    final Widget scaffold;
    if (layout.showsBothPanes) {
      scaffold = Scaffold(
        body: Row(
          children: [
            // Collapsing gives the transcript the rail's width back. The rail
            // unmounts rather than sitting at zero width, the same reasoning
            // the member pane's slot carries: it polls voice rosters while
            // built, and a hidden pane must not keep fetching.
            ClipRect(
              child: AnimatedContainer(
                duration: AppMotion.reduced(context, AppMotion.base),
                curve: AppMotion.entrance,
                width: showRail ? railWidth : 0,
                child: showRail
                    ? OverflowBox(
                        minWidth: railWidth,
                        maxWidth: railWidth,
                        alignment: Alignment.centerRight,
                        child: const ChannelRail(),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            // Always present, even collapsed - it is the only way back.
            const RailDragHandle(),
            // Its own semantics node, or the modal barrier inside this pane's
            // navigator blocks everything painted before it, which is the
            // whole rail: no channel row, section or search field reached a
            // screen reader at all. The member pane paints after it and so
            // was never affected, which is what made this look like a rail bug.
            Expanded(child: Semantics(container: true, child: child)),
            // The pane comes from the edge it lives on: the slot's width
            // animates while the content slides in and fades (motion spec
            // 05). Hidden, the pane itself unmounts rather than sitting at
            // opacity zero - it fetches while built, and home_shell_test pins
            // exactly that - so the exit is the gap closing over the panel
            // duration while the entrance gets the full slide.
            if (membersFit)
              ClipRect(
                child: AnimatedContainer(
                  duration: AppMotion.reduced(context, AppMotion.base),
                  curve: AppMotion.entrance,
                  width: showMembers ? AppMemberPane.width : 0,
                  child: showMembers
                      ? OverflowBox(
                          minWidth: AppMemberPane.width,
                          maxWidth: AppMemberPane.width,
                          alignment: Alignment.centerLeft,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: AppMotion.reduced(
                              context,
                              AppMotion.base,
                            ),
                            curve: AppMotion.entrance,
                            builder: (context, t, child) => Opacity(
                              opacity: t,
                              child: Transform.translate(
                                offset: Offset(16 * (1 - t), 0),
                                child: child,
                              ),
                            ),
                            child: const AppMemberPane(),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
          ],
        ),
      );
    } else if (selected != null) {
      // No rail here to carry the strip, so a call elsewhere gets its own row.
      final voice = ref.watch(voiceControllerProvider);
      final showVoiceStrip =
          voice.state == VoiceSessionState.connected &&
          voice.channelId != selected;
      // Compact: the conversation replaces the list, with a way back.
      final replacesHeader = canvasOpen || dmCallOpen;
      scaffold = Scaffold(
        appBar: replacesHeader
            ? null
            : CompactChannelAppBar(
                channelId: selected,
                onBack: () => context.go(Routes.channels),
              ),
        // Withheld with the back button above: the open pane claims the edge.
        drawer: replacesHeader
            ? null
            : CompactChannelRailDrawer(selectedChannelId: selected),
        // The roster slides in from the right instead of docking beside the
        // conversation, which is the only pane there is at this width.
        endDrawer: const Drawer(
          width: AppMemberPane.width,
          child: SafeArea(child: AppMemberPane()),
        ),
        // No rail here, so the connection bar mounts under the app bar; one SafeArea wraps the whole column, so no child insets itself and opens a gap or a dead band.
        body: SafeArea(
          child: Column(
            children: [
              const RailConnectionBar(),
              Expanded(child: child),
              if (showVoiceStrip) const VoiceStripIndicator(),
            ],
          ),
        ),
      );
    } else {
      scaffold = const Scaffold(body: ChannelRail());
    }

    // Binds the shared shortcut table's own keys, so a future remap reaches every one of these.
    final quickSwitch = activatorFor(AppAction.quickSwitch);
    final focusComposer = activatorFor(AppAction.focusComposer);
    final openSettings = activatorFor(AppAction.openSettings);
    final nextChannel = activatorFor(AppAction.nextChannel);
    final previousChannel = activatorFor(AppAction.previousChannel);
    return WhatsNewGate(
      child: CallbackShortcuts(
        bindings: {
          if (quickSwitch != null)
            quickSwitch: () => openCommandPalette(context),
          if (focusComposer != null)
            focusComposer: () =>
                ref.read(composerFocusNodeProvider)?.requestFocus(),
          if (openSettings != null)
            openSettings: () => context.push(Routes.personalSettings),
          if (nextChannel != null)
            nextChannel: () => unawaited(_cycleChannel(context, ref, 1)),
          if (previousChannel != null)
            previousChannel: () => unawaited(_cycleChannel(context, ref, -1)),
        },
        // CallbackShortcuts only fires for a focused descendant, so this
        // default makes the shortcut work the instant the app opens.
        child: Focus(autofocus: true, child: scaffold),
      ),
    );
  }

  /// Moves selection to the channel [direction] (1 or -1) away from the one
  /// currently open, in [orderedChannels]' order, wrapping at either end.
  Future<void> _cycleChannel(
    BuildContext context,
    WidgetRef ref,
    int direction,
  ) async {
    final store = ref.read(storeProvider).valueOrNull;
    if (store == null) return;
    final ordered = orderedChannels(
      await store.allChannels(),
      await store.allCategories(),
    );
    if (ordered.isEmpty || !context.mounted) return;
    final current = selectedChannelId(context);
    final index = ordered.indexWhere((c) => c.id == current);
    final target = index == -1
        ? ordered.first
        : ordered[(index + direction) % ordered.length];
    context.go(Routes.channel(target.id));
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
/// way, so this still supplies a minimal one at wide layouts, as before. The
/// canvas replaces all of that: [HomeShell] omits [CompactChannelAppBar]
/// while it is open, and [_VoiceConversationHeader] below is skipped the same
/// way, so [CanvasBar] is the only header at every width. `DmCallPane`
/// follows the identical shape for a DM's call, carrying its own bar.
class ConversationPane extends ConsumerWidget {
  const ConversationPane({required this.channelId, super.key});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = LayoutClass.of(context);
    final storeAsync = ref.watch(storeProvider);

    return storeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => const Center(child: Text('Could not load this screen.')),
      data: (store) => StreamBuilder<List<Channel>>(
        stream: store.watchChannels(),
        builder: (context, snapshot) {
          final channel = snapshot.data
              ?.where((c) => c.id == channelId)
              .cast<Channel?>()
              .firstOrNull;
          final isVoice = channel?.kind == 'voice';
          final canvasOpen = ref.watch(canvasOpenProvider) == channelId;
          final dmCallOpen =
              channel?.kind == 'dm' &&
              ref.watch(dmCallOpenProvider) == channelId;
          // Keyed by stage, so each pane fades through the one it replaces.
          final stage = canvasOpen
              ? 'canvas'
              : isVoice
              ? 'voice'
              : dmCallOpen
              ? 'dm-call'
              : 'text';
          final body = AppFadeIn(
            key: ValueKey('pane-$stage'),
            child: canvasOpen
                ? CanvasPane(channelId: channelId)
                : isVoice
                ? VoiceScreen(channelId: channelId)
                : dmCallOpen
                ? DmCallPane(channelId: channelId)
                : ChannelScreen(channelId: channelId),
          );

          if (!layout.showsBothPanes || !isVoice || canvasOpen) return body;
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
      child: Row(
        children: [
          Expanded(child: _ChannelTitle(channelId: channelId)),
          CanvasOpenButton(channelId: channelId),
        ],
      ),
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
                size: AppSizes.icon16,
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                channel?.name ?? '',
                style: const TextStyle(fontWeight: AppWeights.semi),
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
