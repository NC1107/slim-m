// SPDX-License-Identifier: Apache-2.0
/// The command palette's result rows: what counts as a match, and what
/// running one does. Kept apart from the widget so the matching rules are
/// plain top-level functions a test can call without pumping a tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/dms.dart';
import '../providers/personal_space_visibility.dart';
import '../providers/user_profiles.dart';
import '../routing/routes.dart';
import 'author_label.dart';
import 'message_jump.dart';
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
///
/// A personal space's own name is the fixed sentinel [personalSpaceName],
/// not the caller's own display name, so it also matches on
/// [selfDisplayName] when given. That is what makes this the one way back
/// once the row has been removed from the rail via "Remove from list": the
/// rail row is gone, but typing your own name still finds the channel.
bool channelMatchesQuery(
  Channel channel,
  String query, {
  String? selfDisplayName,
}) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase();
  if (channel.name.toLowerCase().contains(q)) return true;
  return channel.isPersonalSpace &&
      selfDisplayName != null &&
      selfDisplayName.toLowerCase().contains(q);
}

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
///
/// [personalSpaceHidden] keeps a removed personal space out of a blank-query
/// browse of everything - the whole point of removing its row - while
/// [selfDisplayName] (via [channelMatchesQuery]) still surfaces it the
/// moment a real query actually names the caller. Selecting it un-hides it:
/// finding it again is also how it comes back onto the rail.
List<PaletteResultItem> buildChannelItems(
  List<Channel> channels,
  String query, {
  String? selfDisplayName,
  bool personalSpaceHidden = false,
}) => [
  for (final channel
      in channels
          .where(
            (c) =>
                query.isNotEmpty || !(c.isPersonalSpace && personalSpaceHidden),
          )
          .where(
            (c) =>
                channelMatchesQuery(c, query, selfDisplayName: selfDisplayName),
          )
          .take(paletteResultLimit))
    PaletteResultItem(
      label: channel.name,
      leading: _channelIcon(channel),
      onSelect: (context, ref) async {
        if (channel.isPersonalSpace) {
          await ref.read(personalSpaceVisibilityProvider.notifier).show();
        }
        if (context.mounted) context.go(Routes.channel(channel.id));
      },
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
///
/// [currentChannelId] is the palette's own `widget.currentChannelId`, taken
/// from the caller rather than read here with `selectedChannelId(context)`:
/// that needs a `GoRouterState`, which only resolves inside a route's own
/// builder subtree, and the palette's context is a dialog sitting outside
/// all of them.
List<PaletteResultItem> buildMessageItems(
  List<api.Message> messages, {
  required String? currentChannelId,
}) => [
  for (final message in messages)
    PaletteResultItem(
      label: message.content,
      trailing: PaletteMessageAuthor(
        authorId: message.authorId,
        cachedDisplayName: message.authorDisplayName,
      ),
      onSelect: (context, ref) async => jumpToMessage(
        GoRouter.of(context),
        ref.read,
        currentChannelId: currentChannelId,
        channelId: message.channelId,
        messageId: message.id,
      ),
    ),
];

/// A message hit's trailing author label: selects only its own author's
/// slice of [batchProfilesControllerProvider], so an unrelated author
/// resolving does not rebuild every row in the palette's result list - see
/// `message_row_identity.dart`.
class PaletteMessageAuthor extends ConsumerWidget {
  const PaletteMessageAuthor({
    super.key,
    required this.authorId,
    required this.cachedDisplayName,
  });

  final String? authorId;
  final String? cachedDisplayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final name = authorLabelResolved(
      authorId: authorId,
      cachedDisplayName: cachedDisplayName,
      resolution: ref.watch(
        batchProfilesControllerProvider.select(
          (m) => authorResolution(m, authorId ?? ''),
        ),
      ),
    );
    return Text(
      name,
      style: AppText.micro.copyWith(color: tokens.textSecondary),
    );
  }
}

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
