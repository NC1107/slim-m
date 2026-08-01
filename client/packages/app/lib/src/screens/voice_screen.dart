// SPDX-License-Identifier: Apache-2.0
/// A voice channel: the join step, and the call once you are in it.
///
/// Joining is never silent. A voice channel opens on a preview with the mic and
/// camera pre-toggles and an explicit Join, because connecting the moment
/// somebody clicks a channel means an open microphone they did not ask for.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/member_presence.dart' show membersProvider, presenceOf;
import '../providers/presence_controller.dart';
import '../providers/voice_controller.dart';
import '../widgets/call_participant_tiles.dart';
import '../widgets/member_profile.dart';
import '../widgets/local_screen_share_banner.dart';
import '../widgets/screen_share_stage.dart';
import '../widgets/user_avatar.dart';
import 'voice_call_controls.dart';
import 'voice_join_preview.dart';

class VoiceScreen extends ConsumerWidget {
  const VoiceScreen({required this.channelId, this.isDm = false, super.key});

  final String channelId;

  /// Whether this is a DM's call rather than a real voice channel's, so the
  /// join preview can say "Call" instead of "Voice channel". The in-call
  /// surface below needs no equivalent: nothing on it names a channel kind.
  final bool isDm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final voice = ref.watch(voiceControllerProvider);
    final inThisChannel = voice.channelId == channelId;

    // Keyed by branch so each step of joining - preview, connecting, in-call - fades through rather than snapping.
    final stage = switch (voice.state) {
      VoiceSessionState.connected when inThisChannel => 'in-call',
      VoiceSessionState.connecting when inThisChannel => 'connecting',
      _ => 'preview',
    };
    return Container(
      color: tokens.surfaceBase,
      child: AppFadeIn(
        key: ValueKey('voice-$stage'),
        child: switch (voice.state) {
          VoiceSessionState.connected when inThisChannel => _InCall(
            channelId: channelId,
          ),
          VoiceSessionState.connecting when inThisChannel =>
            const VoiceConnecting(),
          _ => VoiceJoinPreview(channelId: channelId, isDm: isDm),
        },
      ),
    );
  }
}

/// In the call: who is here, and the controls.
class _InCall extends ConsumerWidget {
  const _InCall({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final voice = ref.watch(voiceControllerProvider);
    final controller = ref.read(voiceControllerProvider.notifier);

    // The first remote share gets the stage; your own is not echoed back
    // (the banner already says so), and two at once is not worth a grid at
    // this product's size - the second waits its turn.
    final sharer = voice.participants
        .where((p) => p.isScreenSharing && !p.isLocal)
        .firstOrNull;

    return Column(
      children: [
        // Pinned above the roster: a per-row glyph is too easy to scroll past.
        if (voice.screenSharing)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s16,
              AppSpacing.s16,
              0,
            ),
            child: LocalScreenShareBanner(),
          ),
        if (sharer != null)
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s16,
                AppSpacing.s16,
                AppSpacing.s16,
                0,
              ),
              child: ScreenShareStage(
                sharerName: sharer.name,
                child: controller.screenShareViewFor(sharer.identity),
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.s16),
            children: [
              Row(
                children: [
                  Text(
                    '${voice.participants.length} in call',
                    style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                  ),
                  if (voice.connectedAt != null) ...[
                    Text(
                      ' · ',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    CallDuration(since: voice.connectedAt!),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              // Tiles centred like a call when the pane is theirs; compact
              // rows when a share stage has taken the room.
              if (sharer == null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s24),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.s16,
                    runSpacing: AppSpacing.s16,
                    children: [
                      for (final p in voice.participants)
                        CallParticipantTile(
                          participant: p,
                          onTap: () => _openProfile(context, ref, p),
                        ),
                    ],
                  ),
                )
              else
                for (final p in voice.participants)
                  _ParticipantRow(participant: p),
              if (voice.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s16),
                  child: AppErrorState(message: voice.error!),
                ),
            ],
          ),
        ),
        CallControls(controller: controller, voice: voice),
      ],
    );
  }
}

/// Opens a caller's profile from their tile, which is the only route to the
/// per-participant volume control that does not go via the member pane.
///
/// The roster carries an identity and a name, not a profile, so the member
/// list is where the rest comes from. Absent from it (a member past the
/// page cap) means no profile to show rather than a wrong one, so nothing
/// opens - the alternative is a popover whose moderation half is missing
/// with no way to tell that it is.
void _openProfile(
  BuildContext context,
  WidgetRef ref,
  VoiceParticipant participant,
) {
  if (participant.isLocal) return;
  final profile = ref
      .read(membersProvider)
      .valueOrNull
      ?.where((m) => m.id == participant.identity)
      .firstOrNull;
  if (profile == null) return;

  showMemberProfile(
    context,
    ref,
    profile: profile,
    status: presenceOf(ref.read(presenceControllerProvider)[profile.id]),
  );
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.participant});

  final VoiceParticipant participant;

  /// What a screen reader hears for this row. The visual states are all bare
  /// icons, so without this the flagship feature announced only names:
  /// muted, speaking and sharing were entirely silent.
  String get _semanticLabel {
    final parts = <String>[
      participant.isLocal ? '${participant.name}, you' : participant.name,
      participant.isMuted ? 'muted' : 'microphone on',
      if (participant.isSpeaking) 'speaking',
      if (participant.isScreenSharing) 'sharing their screen',
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      container: true,
      label: _semanticLabel,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
          child: Row(
            children: [
              // Speaking is a ring, and never the only cue: the muted icon repeats it.
              AuthorAvatar(
                name: participant.name,
                userId: participant.identity,
                size: 32,
                speaking: participant.isSpeaking,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  participant.isLocal
                      ? '${participant.name} (you)'
                      : participant.name,
                  style: TextStyle(color: tokens.textPrimary),
                ),
              ),
              if (participant.isScreenSharing)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.s8),
                  child: Icon(
                    AppIcons.screenShare,
                    size: 16,
                    color: tokens.accent,
                  ),
                ),
              Icon(
                participant.isMuted ? AppIcons.micOff : AppIcons.mic,
                size: 16,
                color: participant.isMuted
                    ? tokens.textSecondary
                    : tokens.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
