// SPDX-License-Identifier: Apache-2.0
/// The left rail: server header, search, the three channel sections, and
/// the signed-in user's footer bar.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../permissions.dart';
import '../providers/channel_order_controller.dart';
import '../providers/dms.dart';
import '../providers/providers.dart';
import '../routing/routes.dart';
import 'channel_grouping.dart';
import 'channel_rail_frame.dart';
import 'channel_rail_sections.dart';
import 'command_palette.dart';

/// The channel id in [path], or null when [path] is not a channel route.
String? channelIdInPath(String path) {
  const prefix = '${Routes.channels}/';
  if (!path.startsWith(prefix)) return null;
  final id = path.substring(prefix.length);
  return id.isEmpty ? null : id;
}

/// The route the router puts a channel id into; read here to highlight the
/// selected row, and by [HomeShell] to decide which pane to show.
///
/// Only valid under a `RouteBase.builder` subtree. A dialog, sheet or overlay
/// pushed on the root navigator must read [channelIdInPath] off
/// Whether the channel rail is shown beside the conversation.
///
/// Defaults open; `RailDragHandle` flips it at the rail's own edge now,
/// rather than a header button. Collapsing gives the transcript the rail's
/// width back, which is the point - on a laptop the rail is a fifth of the
/// window and most of it is empty most of the time.
///
/// [HomeShell] unmounts the rail rather than holding it at zero width: it
/// polls voice rosters while built, and a hidden pane must not keep fetching.
///
/// In-memory only, like the layout state around it: it resets to open on
/// every fresh launch rather than surviving a restart, which is the same
/// thing this provider already did before `RailDragHandle` replaced its
/// header button.
final channelRailVisibleProvider = StateProvider<bool>((ref) => true);

/// `GoRouter.of(context).state` instead, or [GoRouterState.of] throws a
/// [GoError], which is an `Error` and so escapes every `on ...Exception` catch.
String? selectedChannelId(BuildContext context) =>
    channelIdInPath(GoRouterState.of(context).uri.path);

class ChannelRail extends ConsumerStatefulWidget {
  const ChannelRail({super.key});

  /// The design's measured width at expanded layouts.
  static const double expandedWidth = 248;

  /// Unspecified by the ChatScreen spec (which only covers expanded width);
  /// kept at the app's prior medium-width value.
  static const double mediumWidth = 240;

  @override
  ConsumerState<ChannelRail> createState() => _ChannelRailState();
}

class _ChannelRailState extends ConsumerState<ChannelRail> {
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final storeAsync = ref.watch(storeProvider);
    final selected = selectedChannelId(context);
    final me = ref.watch(meProvider).valueOrNull;
    final canManageChannels =
        me != null && me.permissions.hasPermission(Perm.manageChannels);
    final orderState = ref.watch(channelOrderControllerProvider);
    final orderController = ref.read(channelOrderControllerProvider.notifier);

    return Container(
      color: tokens.surfaceSunken,
      child: Column(
        children: [
          const RailHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            // A real field would take focus and a keyboard; this only opens the
            // palette, so AbsorbPointer stops events and the trigger gets them.
            child: GestureDetector(
              key: const Key('rail-search-trigger'),
              onTap: () => openCommandPalette(context),
              child: AbsorbPointer(
                child: AppInput(
                  // The whole field is the tap target, so it takes the
                  // design's 44pt size rather than its 32pt one on a phone.
                  size: AppTouchTargets.of(context)
                      ? AppInputSize.lg
                      : AppInputSize.sm,
                  placeholder: 'Search',
                  icon: Icon(
                    AppIcons.search,
                    size: AppSizes.icon16,
                    color: tokens.textSecondary,
                  ),
                  // Keycaps only where a keyboard is; a touch layout drops the Ctrl+K hint no finger can press.
                  trailing: AppTouchTargets.of(context)
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppKbd('Ctrl'),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: Text(
                                '+',
                                style: AppText.micro.copyWith(
                                  color: tokens.textDisabled,
                                ),
                              ),
                            ),
                            const AppKbd('K'),
                          ],
                        ),
                  semanticLabel: 'Search channels, members and messages',
                ),
              ),
            ),
          ),
          if (orderState.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: AppErrorState(
                message: orderState.error!,
                onRetry: () => unawaited(orderController.retry()),
                onDismiss: orderController.dismiss,
              ),
            ),
          Expanded(
            child: storeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  const Center(child: Text('Could not load channels.')),
              data: (store) => StreamBuilder<List<Channel>>(
                stream: store.watchChannels(),
                builder: (context, snapshot) {
                  final channels = _withPendingOrder(
                    snapshot.data ?? const <Channel>[],
                    orderState.pendingOrder,
                  );
                  final nonDm = channels
                      .where((c) => c.kind != dmChannelKind)
                      .toList(growable: false);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    children: [
                      DirectMessagesSection(
                        channels: channels
                            .where((c) => c.kind == dmChannelKind)
                            .toList(),
                        selectedId: selected,
                      ),
                      TextChannelsSection(
                        channels: nonDm.where((c) => c.kind == 'text').toList(),
                        selectedId: selected,
                        canManage: canManageChannels,
                        onReorder: (newOrder) => unawaited(
                          orderController.reorder(
                            spliceKindOrder(
                              fullOrder: nonDm,
                              kind: 'text',
                              newKindOrder: newOrder,
                            ),
                          ),
                        ),
                      ),
                      VoiceChannelsSection(
                        channels: nonDm
                            .where((c) => c.kind == 'voice')
                            .toList(),
                        selectedId: selected,
                        canManage: canManageChannels,
                        onReorder: (newOrder) => unawaited(
                          orderController.reorder(
                            spliceKindOrder(
                              fullOrder: nonDm,
                              kind: 'voice',
                              newKindOrder: newOrder,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          RailUserFooter(activeChannelId: selected),
        ],
      ),
    );
  }
}

/// Renders [pending] (a reorder this client is waiting on, or has just had
/// refused) over [channels], rather than the plain order the local store
/// still holds - the store is not rewritten until the server confirms it.
/// Anything [pending] does not name (every DM, or a channel that arrived
/// concurrently) keeps its place among the rest, appended after.
List<Channel> _withPendingOrder(List<Channel> channels, List<String>? pending) {
  if (pending == null) return channels;
  final byId = {for (final channel in channels) channel.id: channel};
  final named = pending.toSet();
  return [
    for (final id in pending)
      if (byId.containsKey(id)) byId[id]!,
    for (final channel in channels)
      if (!named.contains(channel.id)) channel,
  ];
}
