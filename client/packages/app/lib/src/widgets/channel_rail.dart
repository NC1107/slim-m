// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The left rail: server header, search, direct messages, every channel
/// category, and the signed-in user's footer bar.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../permissions.dart';
import '../providers/channel_order_controller.dart';
import '../providers/dms.dart';
import '../providers/providers.dart';
import '../routing/routes.dart';
import 'channel_rail_frame.dart';
import 'channel_rail_selection_marker.dart';
import 'channel_rail_sections.dart';
import 'command_palette.dart';
import 'context_menu_region.dart';
import 'create_channel_sheet.dart';

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

  /// [CollapsedRailStrip]'s own width: narrow enough to read as "collapsed"
  /// rather than a third rail size, wide enough for one [AppIconButton]
  /// column with real breathing room either side.
  static const double collapsedWidth = 48;

  @override
  ConsumerState<ChannelRail> createState() => _ChannelRailState();
}

class _ChannelRailState extends ConsumerState<ChannelRail> {
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final storeAsync = ref.watch(storeProvider);
    final selected = selectedChannelId(context);
    final me = ref.watch(effectiveMeProvider);
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
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: AppErrorState(
                    message: 'Could not load channels.',
                    onRetry: () => ref.invalidate(storeProvider),
                  ),
                ),
              ),
              data: (store) => StreamBuilder<List<Channel>>(
                // Deduped to what the rail draws; see MessageStore.watchRailChannels.
                stream: store.watchRailChannels(),
                builder: (context, channelSnapshot) {
                  return StreamBuilder<List<ChannelCategoryRow>>(
                    stream: store.watchCategories(),
                    builder: (context, categorySnapshot) {
                      final categories =
                          categorySnapshot.data ?? const <ChannelCategoryRow>[];
                      final channels = _withPendingOrder(
                        channelSnapshot.data ?? const <Channel>[],
                        orderState.pendingOrder,
                      );
                      final nonDm = channels
                          .where((c) => c.kind != dmChannelKind)
                          .toList(growable: false);
                      // A scroll view over one column, not a ListView: the selection marker layer has to span both sections to slide between them.
                      final list = SingleChildScrollView(
                        // The right inset is load-bearing beyond its own look: RailDragHandle's reach cap assumes a row's own edge sits exactly here.
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.s8,
                          6,
                          AppSpacing.s8,
                          0,
                        ),
                        child: SelectionMarkerLayer(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DirectMessagesSection(
                                channels: channels
                                    .where((c) => c.kind == dmChannelKind)
                                    .toList(),
                                selectedId: selected,
                              ),
                              ChannelCategorySections(
                                channels: nonDm,
                                categories: categories,
                                selectedId: selected,
                                canManage: canManageChannels,
                                onReorder: (groups) =>
                                    unawaited(orderController.reorder(groups)),
                              ),
                            ],
                          ),
                        ),
                      );
                      if (!canManageChannels) return list;
                      // Wraps the whole viewport so the space under the last row is a target too; a row's own menu sits deeper and wins the arena.
                      return ContextMenuRegion(
                        // Pointer-only on purpose: a long press here would fight the scroll, and touch has the section headers' own + instead.
                        enableLongPress: false,
                        itemsBuilder: (context, close) => [
                          AppMenuItem(
                            label: 'Create channel...',
                            leading: AppIcons.add,
                            onTap: () {
                              close();
                              showCreateChannelSheet(
                                context,
                                initialKind: 'text',
                              );
                            },
                          ),
                        ],
                        child: list,
                      );
                    },
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
/// refused) over [channels], rather than the plain arrangement the local
/// store still holds - the store is not rewritten until the server confirms
/// it. A channel [pending] does not name (a DM, or one that arrived
/// concurrently) keeps its stored category and position.
List<Channel> _withPendingOrder(
  List<Channel> channels,
  List<api.ChannelOrderGroup>? pending,
) {
  if (pending == null) return channels;
  final byId = {for (final channel in channels) channel.id: channel};
  final named = <String>{};
  final overridden = <Channel>[];
  for (final group in pending) {
    for (var i = 0; i < group.channelIds.length; i++) {
      final original = byId[group.channelIds[i]];
      if (original == null) continue;
      named.add(original.id);
      overridden.add(
        original.repositioned(categoryId: group.categoryId, position: i),
      );
    }
  }
  return [
    ...overridden,
    for (final channel in channels)
      if (!named.contains(channel.id)) channel,
  ];
}
