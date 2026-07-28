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

import '../providers/voice_controller.dart';
import '../widgets/user_avatar.dart';
import 'voice_call_controls.dart';

class VoiceScreen extends ConsumerWidget {
  const VoiceScreen({required this.channelId, super.key});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final voice = ref.watch(voiceControllerProvider);
    final inThisChannel = voice.channelId == channelId;

    return Container(
      color: tokens.surfaceBase,
      child: switch (voice.state) {
        VoiceSessionState.connected when inThisChannel => _InCall(
          channelId: channelId,
        ),
        VoiceSessionState.connecting when inThisChannel => const _Connecting(),
        _ => _JoinPreview(channelId: channelId),
      },
    );
  }
}

class _Connecting extends StatelessWidget {
  const _Connecting();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: AppSpacing.s16),
          Text('Connecting', style: TextStyle(color: tokens.textSecondary)),
        ],
      ),
    );
  }
}

/// The step before the mic opens.
class _JoinPreview extends ConsumerWidget {
  const _JoinPreview({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final voice = ref.watch(voiceControllerProvider);
    final controller = ref.read(voiceControllerProvider.notifier);

    // One controller for the whole app: its error belongs to whichever
    // channel it last tried, so a denial there must not leak in here.
    final showingLastAttempt = voice.channelId == channelId;
    final error = showingLastAttempt ? voice.error : null;
    final canRetry = !showingLastAttempt || voice.retryable;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(AppIcons.voice, size: 32, color: tokens.textSecondary),
              const SizedBox(height: AppSpacing.s16),
              Text(
                'Voice channel',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                'Joining connects you and opens your microphone. '
                'Nothing is sent before you join.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.s24),
              _PreToggle(
                icon: voice.microphoneEnabled ? AppIcons.mic : AppIcons.micOff,
                label: 'Microphone',
                value: voice.microphoneEnabled ? 'on' : 'muted',
                enabled: voice.microphoneEnabled,
                onChanged: controller.setMicrophonePreference,
              ),
              const SizedBox(height: AppSpacing.s8),
              // Camera is deliberately absent rather than shown disabled: there
              // is no camera path yet, and a dead control reads as broken.
              const SizedBox(height: AppSpacing.s16),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                  child: Text(
                    error,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              // No button at all for a failure retrying cannot fix, rather
              // than one that only invites the same failure a second time.
              if (canRetry)
                FilledButton(
                  onPressed:
                      showingLastAttempt &&
                          voice.state == VoiceSessionState.connecting
                      ? null
                      : () => controller.join(channelId),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.accentFill,
                    foregroundColor: tokens.accentOn,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s16,
                    ),
                  ),
                  child: const Text('Join call'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreToggle extends StatelessWidget {
  const _PreToggle({
    required this.icon,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return InkWell(
      onTap: () => onChanged(!enabled),
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s12,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadii.control),
          color: tokens.surfaceRaised,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: tokens.textSecondary),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Text(label, style: TextStyle(color: tokens.textPrimary)),
            ),
            Text(value, style: TextStyle(color: tokens.textSecondary)),
          ],
        ),
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

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.s16),
            children: [
              Text(
                '${voice.participants.length} in call',
                style: TextStyle(color: tokens.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.s12),
              for (final p in voice.participants)
                _ParticipantRow(participant: p),
              if (voice.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s16),
                  child: Text(
                    voice.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),
        CallControls(controller: controller, voice: voice),
      ],
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.participant});

  final VoiceParticipant participant;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
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
              child: Icon(AppIcons.screenShare, size: 16, color: tokens.accent),
            ),
          Icon(
            participant.isMuted ? AppIcons.micOff : AppIcons.mic,
            size: 16,
            color: participant.isMuted ? tokens.textSecondary : tokens.accent,
          ),
        ],
      ),
    );
  }
}

/// Shown in the channel list for a voice channel the user is in.
class VoiceStripIndicator extends ConsumerWidget {
  const VoiceStripIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider);
    if (voice.state != VoiceSessionState.connected) {
      return const SizedBox.shrink();
    }
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(AppIcons.voice, size: 16, color: tokens.accent),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              '${voice.participants.length} in call',
              style: TextStyle(color: tokens.textPrimary, fontSize: 12),
            ),
          ),
          IconButton(
            iconSize: 16,
            tooltip: 'Leave call',
            icon: const Icon(AppIcons.leaveCall),
            onPressed: ref.read(voiceControllerProvider.notifier).leave,
          ),
        ],
      ),
    );
  }
}
