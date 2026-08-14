// SPDX-License-Identifier: Apache-2.0
/// The rail's sections: direct messages, and every channel category (plus
/// the implicit uncategorised one) grouped and reordered as one list. See
/// docs/decisions/0006-channel-categories.md.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' show ChannelOrderGroup;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/channel_notification_overrides_controller.dart';
import '../routing/routes.dart';
import 'channel_grouping.dart';
import 'channel_rail_channel_rows.dart';
import 'channel_rail_reorder.dart';
import 'channel_rail_selection_marker.dart';
import 'dm_row.dart';
import 'personal_space_row.dart';

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      // Announced in its natural case and as a heading: the uppercase is a
      // visual treatment, and some screen readers spell such a word out.
      child: text.isEmpty
          ? const SizedBox.shrink()
          : Semantics(
              container: true,
              header: true,
              label: text,
              child: ExcludeSemantics(
                child: Text(
                  text.toUpperCase(),
                  style: AppText.label.copyWith(color: tokens.textSecondary),
                ),
              ),
            ),
    );
  }
}

/// A DM is stored locally as an ordinary [Channel] under `kind == 'dm'` (see
/// `providers/dms.dart`), so this reads the same channel stream the
/// category sections do, filtered to that one kind. There is still no way to
/// start a new DM with someone else from here directly; that lives on a
/// member's row in [AppMemberPane], which is where a person already is when
/// they decide to message someone.
///
/// A DM with yourself - your personal space - is the one exception: it gets
/// its own always-present [PersonalSpaceRow] rather than being something you
/// find by searching your own name in the member list. [splitPersonalSpace]
/// reads [Channel.isPersonalSpace], not [Channel.name]: another member can
/// freely set their own display name to [personalSpaceName], and their DM
/// must still render, and open, as an ordinary row rather than as this one.
/// `orderedChannels` (`channel_grouping.dart`) calls the same function, so
/// the next/previous-channel shortcuts cycle in the order shown here.
class DirectMessagesSection extends StatelessWidget {
  const DirectMessagesSection({
    super.key,
    required this.channels,
    required this.selectedId,
  });

  final List<Channel> channels;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final split = splitPersonalSpace(channels);
    final personal = split.personal;
    final others = split.others;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Direct messages'),
        SelectionMarkerTarget(
          selected: personal != null && personal.id == selectedId,
          child: PersonalSpaceRow(
            channel: personal,
            selected: personal != null && personal.id == selectedId,
          ),
        ),
        if (others.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s4,
            ),
            child: Text(
              'Start one from the member list.',
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          )
        else
          for (final channel in others)
            SelectionMarkerTarget(
              selected: channel.id == selectedId,
              child: DmRow(
                channel: channel,
                selected: channel.id == selectedId,
              ),
            ),
      ],
    );
  }
}

/// Every non-DM channel, grouped by category and reorderable across every
/// section in one drag - a channel of any kind may be filed under any
/// category, since a category decides placement only (see
/// docs/decisions/0006-channel-categories.md). The implicit uncategorised
/// section is labelled "Channels", the same treatment
/// [DirectMessagesSection] gives its own header (backlog item 55: a "+"
/// with no header above it read as unexplained chrome). Creating a channel
/// or a category is [SpaceMenuButton]'s job now, not a header button here;
/// every named category is exactly the ones [SpaceSettingsSection]'s
/// "Channel categories" screen manages.
class ChannelCategorySections extends ConsumerWidget {
  const ChannelCategorySections({
    super.key,
    required this.channels,
    required this.categories,
    required this.selectedId,
    required this.onReorder,
    this.canManage = false,
  });

  final List<Channel> channels;
  final List<ChannelCategoryRow> categories;
  final String? selectedId;
  final bool canManage;

  /// Called with the whole rail's new arrangement, grouped by category, once
  /// a drag settles.
  final ValueChanged<List<ChannelOrderGroup>> onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byCategory = channelsByCategory(channels);
    // An empty category is a drop target for a manager and a dead header for
    // anyone else; migration 0031's unconditional Text/Voice seed gives every
    // fresh deployment two of them (the 2026-08-11 review's M8).
    final sections = <ChannelSection>[
      for (final section in <ChannelSection>[
        (null, byCategory[null] ?? const []),
        for (final category in categories)
          (category, byCategory[category.id] ?? const []),
      ])
        if (canManage || section.$2.isNotEmpty) section,
    ];

    Widget row(Channel channel, bool longPressDrags, int? dragHandleIndex) =>
        SelectionMarkerTarget(
          selected: channel.id == selectedId,
          child: ManagedChannelRow(
            canManage: canManage,
            reorderable: longPressDrags,
            dragHandleIndex: dragHandleIndex,
            channel: channel,
            row: (kebab) => channel.kind == 'voice'
                ? VoiceChannelRow(
                    channel: channel,
                    selected: channel.id == selectedId,
                    trailingExtra: kebab,
                  )
                : _TextChannelRow(
                    channel: channel,
                    selected: channel.id == selectedId,
                    trailingExtra: kebab,
                  ),
          ),
        );

    Widget header(ChannelCategoryRow? category) =>
        _SectionLabel(category?.name ?? 'Channels');

    return ReorderableChannelRows(
      sections: sections,
      canManage: canManage,
      onReorder: onReorder,
      rowBuilder: row,
      headerBuilder: header,
    );
  }
}

class _TextChannelRow extends ConsumerWidget {
  const _TextChannelRow({
    required this.channel,
    required this.selected,
    this.trailingExtra,
  });

  final Channel channel;
  final bool selected;
  final Widget? trailingExtra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // Read state (`unread` below) is untouched by this; only the glyph replaces the dot.
    final muted = ref.watch(
      channelNotificationOverridesProvider.select((s) => s.isMuted(channel.id)),
    );
    return AppListRow(
      label: channel.name,
      selected: selected,
      unread: channel.cursor > channel.lastReadSeq,
      muted: muted,
      leading: Icon(
        AppIcons.hash,
        size: AppSizes.icon16,
        color: selected ? tokens.accent : tokens.textSecondary,
      ),
      trailing: muted
          ? Icon(
              AppIcons.notificationsOff,
              size: AppSizes.icon16,
              color: tokens.textSecondary,
            )
          : null,
      trailingExtra: trailingExtra,
      onTap: () => context.go(Routes.channel(channel.id)),
    );
  }
}
