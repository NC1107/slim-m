// SPDX-License-Identifier: Apache-2.0
/// The step before a voice call: connecting, and the join preview itself.
///
/// Split out of `voice_screen.dart` to keep that file under the review
/// budget; these three widgets are the pre-call screen and share no state
/// with the in-call surface that stayed behind.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/voice_controller.dart';
import '../providers/voice_roster.dart';
import '../widgets/user_avatar.dart';

class VoiceConnecting extends StatelessWidget {
  const VoiceConnecting({super.key});

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

/// The step before the mic and camera open.
class VoiceJoinPreview extends ConsumerWidget {
  const VoiceJoinPreview({
    required this.channelId,
    this.isDm = false,
    super.key,
  });

  final String channelId;

  /// See [VoiceScreen.isDm]: swaps the heading and icon for a DM's call.
  final bool isDm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final voice = ref.watch(voiceControllerProvider);
    final controller = ref.read(voiceControllerProvider.notifier);

    // One controller for the whole app: an error is whichever channel tried last, so it must not leak here.
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
                    Icon(
                      isDm ? AppIcons.startCall : AppIcons.voice,
                      size: 32,
                      color: tokens.textSecondary,
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    Text(
                      isDm ? 'Call' : 'Voice channel',
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
                    _PreToggle(
                      icon: voice.cameraEnabled
                          ? AppIcons.camera
                          : AppIcons.cameraOff,
                      label: 'Camera',
                      value: voice.cameraEnabled ? 'on' : 'off',
                      enabled: voice.cameraEnabled,
                      onChanged: controller.setCameraPreference,
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                        child: AppErrorState(message: error),
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
