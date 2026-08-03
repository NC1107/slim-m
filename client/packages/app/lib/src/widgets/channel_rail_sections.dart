// SPDX-License-Identifier: Apache-2.0
/// The rail's three scrollable sections: direct messages, text channels, and
/// voice channels.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/voice_controller.dart';
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
            child: Semantics(
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
/// `providers/dms.dart`), so this reads the same channel stream
/// [TextChannelsSection] and [VoiceChannelsSection] do, filtered the same
/// way they filter to their own kind. There is still no way to start a new
/// DM with someone else from here directly; that lives on a member's row in
/// [AppMemberPane], which is where a person already is when they decide to
/// message someone.
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

class TextChannelsSection extends StatelessWidget {
  const TextChannelsSection({
    super.key,
    required this.channels,
    required this.selectedId,
    required this.onReorder,
    this.canManage = false,
  });

  final List<Channel> channels;
  final String? selectedId;

  /// Whether the signed-in member holds MANAGE_CHANNELS (read from `GET
  /// /me` by the caller). Gates every create/manage affordance below,
  /// including whether a row can be dragged at all.
  final bool canManage;

  /// Called with every text channel's id, in the order a drag within this
  /// section produced. The caller (`ChannelRail`) is the one that knows
  /// where the voice section's channels sit in the server's shared order,
  /// so it is the one that splices this back into a full submission.
  final ValueChanged<List<String>> onReorder;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          'Text',
          onAdd: canManage
              ? () => showCreateChannelSheet(context, initialKind: 'text')
              : null,
          addSemanticLabel: 'Create a text channel',
        ),
        ReorderableChannelRows(
          channels: channels,
          canManage: canManage,
          onReorder: onReorder,
          rowBuilder: (channel) => ManagedChannelRow(
            canManage: canManage,
            channel: channel,
            row: (kebab) => AppListRow(
              label: channel.name,
              selected: channel.id == selectedId,
              unread: channel.cursor > channel.lastReadSeq,
              leading: Icon(
                AppIcons.hash,
                size: AppSizes.icon16,
                color: channel.id == selectedId
                    ? tokens.accent
                    : tokens.textSecondary,
              ),
              trailingExtra: kebab,
              onTap: () => context.go(Routes.channel(channel.id)),
            ),
          ),
        ),
      ],
    );
  }
}

class VoiceChannelsSection extends ConsumerWidget {
  const VoiceChannelsSection({
    super.key,
    required this.channels,
    required this.selectedId,
    required this.onReorder,
    this.canManage = false,
  });

  final List<Channel> channels;
  final String? selectedId;
  final bool canManage;

  /// See [TextChannelsSection.onReorder].
  final ValueChanged<List<String>> onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          'Voice',
          onAdd: canManage
              ? () => showCreateChannelSheet(context, initialKind: 'voice')
              : null,
          addSemanticLabel: 'Create a voice channel',
        ),
        ReorderableChannelRows(
          channels: channels,
          canManage: canManage,
          onReorder: onReorder,
          rowBuilder: (channel) => ManagedChannelRow(
            canManage: canManage,
            channel: channel,
            row: (kebab) => VoiceChannelRow(
              channel: channel,
              selected: channel.id == selectedId,
              voice: voice,
              trailingExtra: kebab,
            ),
          ),
        ),
      ],
    );
  }
}
