// SPDX-License-Identifier: Apache-2.0
/// The rail's channel rows: the manage-sheet pairing, the voice row and the
/// participant strip beneath it.
///
/// Split out of `channel_rail_sections.dart` when that file crossed the
/// 300-line review budget; the sections there own layout and permissions,
/// these own one row each.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/voice_controller.dart';
import '../routing/routes.dart';
import 'manage_channel_sheet.dart';
import 'user_avatar.dart';

/// Pairs a channel row with its manage-sheet trigger, kept as a sibling
/// rather than [AppListRow.trailing] so it never displaces that slot's own
/// job (the unread dot, the voice channel's live head count).
class ManagedChannelRow extends StatelessWidget {
  const ManagedChannelRow({
    super.key,
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
      // Centring floats the button between a voice row and its strip below.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: row),
        SizedBox(
          height: AppListRow.heightFor(context),
          child: Center(
            child: AppIconButton(
              icon: AppIcons.moreVertical,
              semanticLabel: 'Manage ${channel.name}',
              size: AppIconButtonSize.sm,
              onPressed: () => showManageChannelSheet(context, channel),
            ),
          ),
        ),
      ],
    );
  }
}

class VoiceChannelRow extends StatelessWidget {
  const VoiceChannelRow({
    super.key,
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
        if (_inCall) _ParticipantStrip(participants: voice.participants),
      ],
    );
  }
}

/// Who is in a voice channel, rendered only for the one the caller has
/// actually joined.
///
/// TODO(ui-backend): for any other voice channel there is no way to know who
/// (if anyone) is in it, because the server exposes no per-channel voice
/// roster, only the participants of a room already joined. So this strip is
/// sourced from real participant data for that one channel, and shows
/// nothing at all otherwise.
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
              child: AuthorAvatar(
                name: participant.name,
                userId: participant.identity,
                size: 20,
                speaking: participant.isSpeaking,
              ),
            ),
          if (participants.any((p) => p.isScreenSharing))
            Icon(AppIcons.screenShare, size: 13, color: tokens.textSecondary),
        ],
      ),
    );
  }
}
