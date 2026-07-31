// SPDX-License-Identifier: Apache-2.0
/// The command palette's result rows: what counts as a match, and what
/// running one does. Kept apart from the widget so the matching rules are
/// plain top-level functions a test can call without pumping a tree.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/dms.dart';
import '../routing/routes.dart';
import 'space_settings_section.dart';

/// A running palette result: a label and icon to render, and what selecting
/// it does. [onSelect] receives the still-mounted palette's own context and
/// ref, so it can navigate or await a request before the caller pops it.
class PaletteResultItem {
  const PaletteResultItem({
    required this.label,
    required this.onSelect,
    this.leading,
    this.trailing,
    this.semanticLabel,
  });

  final String label;
  final IconData? leading;
  final Widget? trailing;
  final String? semanticLabel;
  final Future<void> Function(BuildContext context, WidgetRef ref) onSelect;
}

/// Whether [channel] is worth showing for [query]. An empty query matches
/// everything, so a blank field browses the whole list rather than showing
/// nothing until the user types.
bool channelMatchesQuery(Channel channel, String query) =>
    query.isEmpty || channel.name.toLowerCase().contains(query.toLowerCase());

/// Same rule as [channelMatchesQuery], over both a member's display name and
/// their username, since either is a name someone might type to find them.
bool memberMatchesQuery(api.UserProfile member, String query) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase();
  return member.displayName.toLowerCase().contains(q) ||
      member.username.toLowerCase().contains(q);
}

const int paletteResultLimit = 8;

IconData _channelIcon(Channel channel) => switch (channel.kind) {
  'voice' => AppIcons.voice,
  dmChannelKind => AppIcons.account,
  _ => AppIcons.hash,
};

/// Channels and DMs matching [query], text and voice and direct alike: the
/// rail already renders all three from one stream, and the palette does the
/// same rather than picking a kind up front.
List<PaletteResultItem> buildChannelItems(
  List<Channel> channels,
  String query,
) => [
  for (final channel
      in channels
          .where((c) => channelMatchesQuery(c, query))
          .take(paletteResultLimit))
    PaletteResultItem(
      label: channel.name,
      leading: _channelIcon(channel),
      onSelect: (context, ref) async => context.go(Routes.channel(channel.id)),
    ),
];

/// Members matching [query], excluding [selfId]. A DM with yourself is a
/// personal space now and opens fine, but it has its own dedicated row in
/// the rail's Direct messages section - finding it by searching your own
/// name here would be the opposite of obvious.
List<PaletteResultItem> buildMemberItems(
  List<api.UserProfile> members,
  String query,
  String? selfId,
) => [
  for (final member
      in members
          .where((m) => m.id != selfId)
          .where((m) => memberMatchesQuery(m, query))
          .take(paletteResultLimit))
    PaletteResultItem(
      label: member.displayName,
      leading: AppIcons.account,
      semanticLabel: 'Message ${member.displayName}',
      onSelect: (context, ref) async {
        final container = ProviderScope.containerOf(context, listen: false);
        final channelId = await openDirectMessage(container, member.id);
        if (context.mounted) context.go(Routes.channel(channelId));
      },
    ),
];

/// Messages already matched server-side by full-text search, scoped to
/// whichever channel is open (there is no cross-channel search endpoint).
/// [tokens] styles the author trailing label.
List<PaletteResultItem> buildMessageItems(
  List<api.Message> messages,
  AppTokens tokens,
) => [
  for (final message in messages)
    PaletteResultItem(
      label: message.content,
      trailing: Text(
        message.authorDisplayName ?? 'Unknown',
        style: AppText.micro.copyWith(color: tokens.textSecondary),
      ),
      onSelect: (context, ref) async =>
          context.go(Routes.channel(message.channelId)),
    ),
];

/// The palette's static actions, filtered by [query] like everything else.
/// The Space settings action is gated on [permissions] the same way the
/// rail's Space menu is, so the palette never offers a path this caller
/// could not also reach from the rail.
List<PaletteResultItem> buildActionItems(String query, int permissions) {
  final actions = [
    // push, not go: settings float as a modal over the app, so they need the
    // shell left beneath them, exactly as every rail entry point does. go
    // replaced the shell, so closing the modal stranded the user on the empty
    // channel view with the open channel lost. The channel entries above stay
    // on go, since a channel is a shell route and replacing is right there.
    PaletteResultItem(
      label: 'Open personal settings',
      leading: AppIcons.settings,
      onSelect: (context, ref) async => context.push(Routes.personalSettings),
    ),
    if (spaceSettingsReachable(permissions))
      PaletteResultItem(
        label: 'Open Space settings',
        leading: AppIcons.settings,
        onSelect: (context, ref) async => context.push(Routes.spaceSettings),
      ),
  ];
  if (query.isEmpty) return actions;
  final q = query.toLowerCase();
  return actions.where((a) => a.label.toLowerCase().contains(q)).toList();
}
