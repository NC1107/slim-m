// SPDX-License-Identifier: Apache-2.0
/// The rail's three scrollable sections: direct messages, text channels, and
/// voice channels.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/voice_controller.dart';
import '../routing/routes.dart';
import 'create_channel_sheet.dart';
import 'manage_channel_sheet.dart';

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
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 10, onAdd != null ? 4 : 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: AppText.label.copyWith(color: tokens.textSecondary),
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
/// DM from here directly; that lives on a member's row in [AppMemberPane],
/// which is where a person already is when they decide to message someone.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Direct messages'),
        if (channels.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s4,
            ),
            child: Text(
              'No direct messages yet. Open one from a member in the list.',
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          )
        else
          for (final channel in channels)
            AppListRow(
              label: channel.name,
              selected: channel.id == selectedId,
              unread: channel.cursor > channel.lastReadSeq,
              leading: AppAvatar(name: channel.name, size: 20),
              onTap: () => context.go(Routes.channel(channel.id)),
            ),
      ],
    );
  }
}

class TextChannelsSection extends StatelessWidget {
  const TextChannelsSection({
    super.key,
    required this.channels,
    required this.selectedId,
    this.canManage = false,
  });

  final List<Channel> channels;
  final String? selectedId;

  /// Whether the signed-in member holds MANAGE_CHANNELS (read from `GET
  /// /me` by the caller). Gates every create/manage affordance below.
  final bool canManage;

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
        for (final channel in channels)
          _ManagedChannelRow(
            canManage: canManage,
            channel: channel,
            row: AppListRow(
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
              onTap: () => context.go(Routes.channel(channel.id)),
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
    this.canManage = false,
  });

  final List<Channel> channels;
  final String? selectedId;
  final bool canManage;

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
        for (final channel in channels)
          _ManagedChannelRow(
            canManage: canManage,
            channel: channel,
            row: _VoiceChannelRow(
              channel: channel,
              selected: channel.id == selectedId,
              voice: voice,
            ),
          ),
      ],
    );
  }
}

/// Pairs a channel row with its manage-sheet trigger, kept as a sibling
/// rather than [AppListRow.trailing] so it never displaces that slot's own
/// job (the unread dot, the voice channel's live head count).
class _ManagedChannelRow extends StatelessWidget {
  const _ManagedChannelRow({
    required this.canManage,
    required this.channel,
    required this.row,
  });

  final bool canManage;
  final Channel channel;
  final Widget row;

  @override
  Widget build(BuildContext context) {
    if (!canManage) return row;
    return Row(
      children: [
        Expanded(child: row),
        AppIconButton(
          icon: AppIcons.moreVertical,
          semanticLabel: 'Manage ${channel.name}',
          size: AppIconButtonSize.sm,
          onPressed: () => showManageChannelSheet(context, channel),
        ),
      ],
    );
  }
}

/// The participant strip renders only for the channel the caller has actually
/// joined, sourced from real participant data, and not at all otherwise: the
/// server exposes no per-channel voice roster, only the participants of a room
/// already joined, so for any other voice channel there is no way to know who
/// (if anyone) is in it. See the `TODO(ui-backend)` in [build].
class _VoiceChannelRow extends StatelessWidget {
  const _VoiceChannelRow({
    required this.channel,
    required this.selected,
    required this.voice,
  });

  final Channel channel;
  final bool selected;
  final VoiceState voice;

  bool get _inCall =>
      voice.state == VoiceSessionState.connected &&
      voice.channelId == channel.id;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final iconColor = _inCall
        ? tokens.accent
        : tokens.textSecondary.withValues(alpha: 0.7);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppListRow(
          label: channel.name,
          selected: selected,
          unread: _inCall,
          leading: Icon(
            AppIcons.voice,
            size: AppSizes.icon16,
            color: iconColor,
          ),
          trailing: _inCall
              ? Text(
                  '${voice.participants.length}',
                  style: AppText.micro.copyWith(
                    color: tokens.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                )
              : null,
          onTap: () => context.go(Routes.channel(channel.id)),
        ),
        // TODO(ui-backend): no per-channel voice roster on the server, so only
        // the joined channel can show one. See this class's doc.
        if (_inCall) _ParticipantStrip(participants: voice.participants),
      ],
    );
  }
}

class _ParticipantStrip extends StatelessWidget {
  const _ParticipantStrip({required this.participants});

  final List<VoiceParticipant> participants;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 2, 8, 4),
      child: Row(
        children: [
          for (final participant in participants.take(8))
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s4),
              child: participant.isSpeaking
                  ? Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: tokens.accentFill, width: 2),
                      ),
                      child: AppAvatar(name: participant.name, size: 20),
                    )
                  : AppAvatar(name: participant.name, size: 20),
            ),
          if (participants.any((p) => p.isScreenSharing))
            Icon(AppIcons.screenShare, size: 13, color: tokens.textSecondary),
        ],
      ),
    );
  }
}
