// SPDX-License-Identifier: Apache-2.0
/// The non-connected states of a voice screen: connecting, needing to
/// confirm a switch between two calls, and needing an explicit rejoin.
///
/// Split out of `voice_screen.dart` to keep that file under the review
/// budget; these widgets share no state with the in-call surface that
/// stayed behind. This file used to hold the join lobby (a mic/camera
/// pre-toggle behind an explicit Join button) that `voice_screen.dart`'s own
/// doc now explains was removed: clicking a voice channel joins directly,
/// and these are what a screen shows when direct joining is not the answer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/call_recap.dart';
import '../providers/voice_roster.dart';
import '../widgets/call_recap_card.dart';
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

/// Shown instead of an automatic join when the caller is already connected
/// (or connecting) somewhere else: switching has to leave that call, so it
/// asks first rather than silently moving them, the one place a voice
/// channel arrival still needs an explicit decision.
class VoiceSwitchPrompt extends StatelessWidget {
  const VoiceSwitchPrompt({super.key, required this.onSwitch});

  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
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
                'Already in a call',
                textAlign: TextAlign.center,
                style: AppText.heading.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: AppWeights.semi,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                "You're in a call somewhere else. Switching leaves it and "
                'joins this one instead.',
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: AppSpacing.s16),
              FilledButton(
                onPressed: onSwitch,
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.accentFill,
                  foregroundColor: tokens.accentOn,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
                ),
                child: const Text('Switch to this call'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown after a hang-up (no error, just left) or a failed automatic join
/// (an error the caller can read and, if [canRetry], act on). The only
/// remaining manual step in a voice channel's whole flow.
class VoiceRejoinScreen extends StatelessWidget {
  const VoiceRejoinScreen({
    super.key,
    required this.channelId,
    required this.isDm,
    required this.canRetry,
    required this.onRetry,
    this.errorMessage,
    this.recap,
  });

  final String channelId;
  final bool isDm;
  final bool canRetry;
  final VoidCallback onRetry;
  final String? errorMessage;

  /// The call that just ended here, already checked against this channel by
  /// the caller. Rendered only when [errorMessage] is null and
  /// [CallRecap.isWorthShowing] - a failed rejoin attempt keeps the error
  /// as the one thing on screen, and a mis-click or a call spent alone gets
  /// nothing, not a summary of noise.
  final CallRecap? recap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
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
                      style: AppText.heading.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: AppWeights.semi,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    _WhoIsHere(channelId: channelId),
                    const SizedBox(height: AppSpacing.s16),
                    if (errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                        child: AppErrorState(message: errorMessage!),
                      )
                    else if (recap case final recap? when recap.isWorthShowing)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                        child: CallRecapCard(recap: recap),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                        child: Text(
                          'You left this call.',
                          textAlign: TextAlign.center,
                          style: AppText.caption.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                    // No button for a failure a retry cannot fix.
                    if (canRetry)
                      FilledButton(
                        onPressed: onRetry,
                        style: FilledButton.styleFrom(
                          backgroundColor: tokens.accentFill,
                          foregroundColor: tokens.accentOn,
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.s16,
                          ),
                        ),
                        child: Text(
                          errorMessage != null ? 'Try again' : 'Rejoin call',
                        ),
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

/// Who is already in the call, above the rejoin button.
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
