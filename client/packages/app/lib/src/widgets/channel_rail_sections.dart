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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Text(
        text.toUpperCase(),
        style: AppText.label.copyWith(color: tokens.textSecondary),
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
  const DirectMessagesSection(
      {super.key, required this.channels, required this.selectedId});

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
                horizontal: AppSpacing.s8, vertical: AppSpacing.s4),
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
  const TextChannelsSection(
      {super.key, required this.channels, required this.selectedId});

  final List<Channel> channels;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Text'),
        for (final channel in channels)
          AppListRow(
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
      ],
    );
  }
}

class VoiceChannelsSection extends ConsumerWidget {
  const VoiceChannelsSection(
      {super.key, required this.channels, required this.selectedId});

  final List<Channel> channels;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Voice'),
        for (final channel in channels)
          _VoiceChannelRow(
            channel: channel,
            selected: channel.id == selectedId,
            voice: voice,
          ),
      ],
    );
  }
}

class _VoiceChannelRow extends StatelessWidget {
  const _VoiceChannelRow(
      {required this.channel, required this.selected, required this.voice});

  final Channel channel;
  final bool selected;
  final VoiceState voice;

  bool get _inCall =>
      voice.state == VoiceSessionState.connected &&
      voice.channelId == channel.id;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final iconColor =
        _inCall ? tokens.accent : tokens.textSecondary.withValues(alpha: 0.7);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppListRow(
          label: channel.name,
          selected: selected,
          unread: _inCall,
          leading:
              Icon(AppIcons.voice, size: AppSizes.icon16, color: iconColor),
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
        // TODO(ui-backend): for any voice channel besides the one the caller
        // has actually joined, there is no way to know who (if anyone) is in
        // it: the server exposes no per-channel voice roster, only the
        // participants of a room already joined. So this strip renders only
        // for [voice]'s own channel, sourced from real participant data,
        // and nothing at all otherwise.
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
