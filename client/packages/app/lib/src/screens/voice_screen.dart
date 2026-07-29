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
import '../providers/voice_roster.dart';
import '../widgets/local_screen_share_banner.dart';
import '../widgets/screen_share_stage.dart';
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
            const _Connecting(),
          _ => _JoinPreview(channelId: channelId),
        },
      ),
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

    // Scroll-safe and centred: a short viewport (landscape phone) scrolls, a tall one centres via the min-height floor.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
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
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    _WhoIsHere(channelId: channelId),
                    const SizedBox(height: AppSpacing.s16),
                    _PreToggle(
                      icon: voice.microphoneEnabled
                          ? AppIcons.mic
                          : AppIcons.micOff,
                      label: 'Microphone',
                      value: voice.microphoneEnabled ? 'on' : 'muted',
                      enabled: voice.microphoneEnabled,
                      onChanged: controller.setMicrophonePreference,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    // Camera is absent, not disabled: no camera path exists yet and a dead control reads as broken.
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
                    // No button for a failure a retry cannot fix, rather than one that only invites the same failure again.
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
          ),
        ),
      ),
    );
  }
}

/// Who is already in the call, above the button that joins it.
///
/// The rail has shown this for a channel you have not joined since the
/// per-channel roster landed; the preview, which is the screen you are
/// actually looking at when deciding whether to join, did not.
///
/// The three answers the roster can give are rendered as three different
/// things, because collapsing them lies. Not known yet draws nothing rather
/// than an empty room, since a deployment with no SFU configured stays in
/// that state forever and "nobody is here" would be a claim this client
/// never checked.
class _WhoIsHere extends ConsumerWidget {
  const _WhoIsHere({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final roster = ref.watch(voiceRosterProvider(channelId)).valueOrNull;
    if (roster == null) return const SizedBox.shrink();

    if (roster.isEmpty) {
      return Text(
        'Nobody is in this call yet.',
        textAlign: TextAlign.center,
        style: AppText.caption.copyWith(color: tokens.textSecondary),
      );
    }

    final names = roster.map((p) => p.displayName).join(', ');
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.s4,
          children: [
            for (final participant in roster.take(8))
              AuthorAvatar(
                name: participant.displayName,
                userId: participant.userId,
                size: 28,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          roster.length == 1 ? '$names is here' : '$names are here',
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(color: tokens.textSecondary),
          semanticsLabel: roster.length == 1
              ? '$names is in this call'
              : '${roster.length} people in this call: $names',
        ),
      ],
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
