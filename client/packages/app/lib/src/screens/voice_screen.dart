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
        VoiceSessionState.connected when inThisChannel =>
          _InCall(channelId: channelId),
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
                  onPressed: showingLastAttempt &&
                          voice.state == VoiceSessionState.connecting
                      ? null
                      : () => controller.join(channelId),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.accentFill,
                    foregroundColor: tokens.accentOn,
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.s16),
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
        _CallControls(controller: controller, voice: voice),
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
          // Speaking is a ring, and it is never the only cue: the muted icon
          // carries the same information for anyone who cannot see the colour.
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tokens.surfaceRaised,
              border: Border.all(
                color: participant.isSpeaking
                    ? tokens.accentFill
                    : tokens.borderSubtle,
                width: participant.isSpeaking ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              participant.name.isEmpty
                  ? '?'
                  : participant.name.characters.first.toUpperCase(),
              style: TextStyle(color: tokens.textSecondary, fontSize: 12),
            ),
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

class _CallControls extends StatelessWidget {
  const _CallControls({required this.controller, required this.voice});

  final VoiceController controller;
  final VoiceState voice;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ControlButton(
            icon: voice.microphoneEnabled ? AppIcons.mic : AppIcons.micOff,
            tooltip: voice.microphoneEnabled ? 'Mute' : 'Unmute',
            active: voice.microphoneEnabled,
            onPressed: controller.toggleMicrophone,
          ),
          const SizedBox(width: AppSpacing.s12),
          _ControlButton(
            icon: AppIcons.screenShare,
            tooltip: voice.screenSharing
                ? 'Stop sharing'
                : 'Share a screen or window',
            active: voice.screenSharing,
            onPressed: () => _share(context, controller, voice),
          ),
          const SizedBox(width: AppSpacing.s12),
          _ControlButton(
            icon: AppIcons.leaveCall,
            tooltip: 'Leave call',
            active: false,
            destructive: true,
            onPressed: controller.leave,
          ),
        ],
      ),
    );
  }

  Future<void> _share(
    BuildContext context,
    VoiceController controller,
    VoiceState voice,
  ) async {
    if (voice.screenSharing) {
      await controller.setScreenShare(false);
      return;
    }
    final quality = await showDialog<ScreenShareQuality>(
      context: context,
      builder: (context) => const _ShareQualityDialog(),
    );
    if (quality == null) return;
    await controller.setScreenShare(true, quality: quality);
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final bool destructive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final background = destructive
        ? Theme.of(context).colorScheme.error
        : active
            ? tokens.accentSoft
            : tokens.surfaceRaised;
    final foreground = destructive
        ? Theme.of(context).colorScheme.onError
        : active
            ? tokens.accent
            : tokens.textSecondary;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: Container(
            // 44 is the touch minimum; it does not shrink on desktop, because
            // one control size across widths is what "one layout" has to mean.
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadii.control),
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Icon(icon, size: 18, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// Quality is a ceiling, not a preference, so the dialog says what each costs.
class _ShareQualityDialog extends StatelessWidget {
  const _ShareQualityDialog();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return AlertDialog(
      title: const Text('Share a screen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your desktop will ask which screen or window to share.',
            style: TextStyle(color: tokens.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.s16),
          for (final q in ScreenShareQuality.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_label(q)),
              subtitle: Text(
                '${q.width}x${q.height} · ${q.fps}fps · '
                'about ${(q.maxBitrate / 1000000).toStringAsFixed(1)} Mbit/s up',
                style: TextStyle(color: tokens.textSecondary, fontSize: 12),
              ),
              onTap: () => Navigator.of(context).pop(q),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  static String _label(ScreenShareQuality q) => switch (q) {
        ScreenShareQuality.smooth => 'Smooth, for anything moving',
        ScreenShareQuality.balanced => 'Balanced',
        ScreenShareQuality.crisp => 'Crisp, for reading code',
      };
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
