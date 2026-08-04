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

import '../routing/routes.dart';
import 'channel_grouping.dart';
import 'channel_rail_channel_rows.dart';
import 'channel_rail_reorder.dart';
import 'create_channel_sheet.dart';
import 'dm_row.dart';
import 'personal_space_row.dart';

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.onAdd, this.addSemanticLabel});

  final String text;

  /// Present only for a section a caller may create into; absent hides the
  /// affordance entirely rather than showing it disabled.
  final VoidCallback? onAdd;
  final String? addSemanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // The add button's hit box grows around a glyph that does not, so the
    // trailing padding comes off to leave the glyph where the design puts it.
    final addPad = AppTouchTargets.of(context) ? 0.0 : 4.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 10, onAdd != null ? addPad : 8, 6),
      child: Row(
        children: [
          Expanded(
            // Announced in its natural case and as a heading: the uppercase is
            // a visual treatment, and some screen readers spell such a word out.
            child: text.isEmpty
                ? const SizedBox.shrink()
                : Semantics(
                    container: true,
                    header: true,
                    label: text,
                    child: ExcludeSemantics(
                      child: Text(
                        text.toUpperCase(),
                        style: AppText.label.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ),
          ),
          if (onAdd != null)
            AppIconButton(
              icon: AppIcons.add,
              semanticLabel: addSemanticLabel ?? 'Create channel',
              size: AppIconButtonSize.sm,
              onPressed: onAdd,
            ),
        ],
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
        PersonalSpaceRow(
          channel: personal,
          selected: personal != null && personal.id == selectedId,
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
            DmRow(channel: channel, selected: channel.id == selectedId),
      ],
    );
  }
}

/// Every non-DM channel, grouped by category and reorderable across every
/// section in one drag - a channel of any kind may be filed under any
/// category, since a category decides placement only (see
/// docs/decisions/0006-channel-categories.md). The implicit uncategorised
/// section carries the one "create a channel" affordance, unlabelled since
/// it is not a named section; every category above it is exactly the ones
/// [SpaceSettingsSection]'s "Channel categories" screen manages.
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
    final sections = <ChannelSection>[
      (null, byCategory[null] ?? const []),
      for (final category in categories)
        (category, byCategory[category.id] ?? const []),
    ];

    Widget row(Channel channel) => ManagedChannelRow(
      canManage: canManage,
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
    );

    Widget header(ChannelCategoryRow? category) => _SectionLabel(
      category?.name ?? '',
      onAdd: canManage && category == null
          ? () => showCreateChannelSheet(context, initialKind: 'text')
          : null,
      addSemanticLabel: 'Create a channel',
    );

    return ReorderableChannelRows(
      sections: sections,
      canManage: canManage,
      onReorder: onReorder,
      rowBuilder: row,
      headerBuilder: header,
    );
  }
}

class _TextChannelRow extends StatelessWidget {
  const _TextChannelRow({
    required this.channel,
    required this.selected,
    this.trailingExtra,
  });

  final Channel channel;
  final bool selected;
  final Widget? trailingExtra;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return AppListRow(
      label: channel.name,
      selected: selected,
      unread: channel.cursor > channel.lastReadSeq,
      leading: Icon(
        AppIcons.hash,
        size: AppSizes.icon16,
        color: selected ? tokens.accent : tokens.textSecondary,
      ),
      trailingExtra: trailingExtra,
      onTap: () => context.go(Routes.channel(channel.id)),
    );
  }
}
