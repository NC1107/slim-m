// SPDX-License-Identifier: Apache-2.0
/// The left rail: server header, search, the three channel sections, and
/// the signed-in user's footer bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/dms.dart';
import '../providers/providers.dart';
import '../routing/routes.dart';
import 'channel_rail_frame.dart';
import 'channel_rail_sections.dart';

/// The route the router puts a channel id into; read here to highlight the
/// selected row, and by [HomeShell] to decide which pane to show.
String? selectedChannelId(BuildContext context) {
  final path = GoRouterState.of(context).uri.path;
  const prefix = '${Routes.channels}/';
  if (!path.startsWith(prefix)) return null;
  final id = path.substring(prefix.length);
  return id.isEmpty ? null : id;
}

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
  final _searchController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final storeAsync = ref.watch(storeProvider);
    final selected = selectedChannelId(context);

    return Container(
      color: tokens.surfaceSunken,
      child: Column(
        children: [
          const RailHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            // Stands in for the design's command palette, which this client
            // does not have yet (no quick switcher exists): typing here
            // live-filters the sections below by name instead of opening a
            // modal search.
            child: AppInput(
              controller: _searchController,
              size: AppInputSize.sm,
              placeholder: 'Search',
              icon: Icon(AppIcons.search,
                  size: AppSizes.icon16, color: tokens.textSecondary),
              // AppKbd draws one keycap; a chained shortcut is composed by
              // the caller, per that widget's own doc comment.
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppKbd('Ctrl'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text('+',
                        style:
                            AppText.micro.copyWith(color: tokens.textDisabled)),
                  ),
                  const AppKbd('K'),
                ],
              ),
              onChanged: (value) =>
                  setState(() => _filter = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: storeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (store) => StreamBuilder<List<Channel>>(
                stream: store.watchChannels(),
                builder: (context, snapshot) {
                  final channels = snapshot.data ?? const <Channel>[];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    children: [
                      DirectMessagesSection(
                        channels: channels
                            .where((c) => c.kind == dmChannelKind)
                            .where(
                                (c) => c.name.toLowerCase().contains(_filter))
                            .toList(),
                        selectedId: selected,
                      ),
                      TextChannelsSection(
                        channels: channels
                            .where((c) => c.kind == 'text')
                            .where(
                                (c) => c.name.toLowerCase().contains(_filter))
                            .toList(),
                        selectedId: selected,
                      ),
                      VoiceChannelsSection(
                        channels: channels
                            .where((c) => c.kind == 'voice')
                            .where(
                                (c) => c.name.toLowerCase().contains(_filter))
                            .toList(),
                        selectedId: selected,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const RailConnectionBar(),
          const RailUserFooter(),
        ],
      ),
    );
  }
}
