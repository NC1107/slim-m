// SPDX-License-Identifier: Apache-2.0
/// The rail's channel rows: the manage-sheet pairing, the voice row and the
/// participant strip beneath it.
///
/// Split out of `channel_rail_sections.dart` when that file crossed the
/// 300-line review budget; the sections there own layout and permissions,
/// these own one row each.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/voice_controller.dart';
import '../providers/voice_roster.dart';
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
    // Mirrors _SectionLabel's own trailing inset so this glyph and the
    // section's add glyph share a right edge; both are AppIconButtonSize.sm.
    final trailingPad = AppTouchTargets.of(context) ? 0.0 : 4.0;
    return Padding(
      padding: EdgeInsets.only(right: trailingPad),
      child: Row(
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
      ),
    );
  }
}

class VoiceChannelRow extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final iconColor = _inCall
        ? tokens.accent
        : tokens.textSecondary.withValues(alpha: 0.7);

    // A joined call already has this live; an unjoined one polls for it below.
    final participants = _inCall
        ? voice.participants
        : ref
                  .watch(voiceRosterProvider(channel.id))
                  .valueOrNull
                  ?.map(_asVoiceParticipant)
                  .toList(growable: false) ??
              const <VoiceParticipant>[];

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
          trailing: participants.isEmpty
              ? null
              : Text(
                  '${participants.length}',
                  style: AppText.micro.copyWith(
                    color: tokens.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
          onTap: () => context.go(Routes.channel(channel.id)),
        ),
        if (participants.isNotEmpty)
          _ParticipantStrip(participants: participants),
      ],
    );
  }
}

/// A roster snapshot carries no live speaking or screen-share signal, only
/// who is connected, so every derived flag here is false rather than guessed.
VoiceParticipant _asVoiceParticipant(api.VoiceRosterParticipant p) =>
    VoiceParticipant(
      identity: p.userId,
      name: p.displayName,
      isSpeaking: false,
      isMuted: false,
      isLocal: false,
      isScreenSharing: false,
    );

/// Who is in a voice channel: real-time for the one the caller has joined,
/// a periodic snapshot ([voiceRosterProvider]) for every other one.
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
