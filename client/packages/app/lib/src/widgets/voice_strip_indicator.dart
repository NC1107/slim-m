// SPDX-License-Identifier: Apache-2.0
/// The collapsed call strip: what the call looks like once you have navigated
/// away from it.
///
/// **It lives in the rail, not over the content.** Collapsing a call must not
/// cost message space, or people stop collapsing; and in the rail it also
/// survives navigating to another channel, which is the actual requirement -
/// you are in a call, not in a screen. On compact there is no rail, so the
/// shell pins it above the bottom edge instead.
///
/// Its own file so the rail can show it without a screens-to-widgets import
/// running backwards.
///
/// The design's "Open canvas" button is deliberately absent: the Voice Canvas
/// is Phase 6 and there is nothing to open, and a button that does nothing is
/// worse than a missing one. Everything else here acts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/providers.dart';
import '../providers/voice_controller.dart';
import '../routing/routes.dart';
import 'call_participant_tiles.dart';
import 'user_avatar.dart';

/// Whether a call is live and worth surfacing, regardless of which channel is
/// on screen. The caller decides *where* it renders; this decides *if*.
class VoiceStripIndicator extends ConsumerWidget {
  const VoiceStripIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider);
    if (voice.state != VoiceSessionState.connected) {
      return const SizedBox.shrink();
    }
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final controller = ref.read(voiceControllerProvider.notifier);
    final compact = MediaQuery.sizeOf(context).width < kCompactWidth;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      child: compact
          ? _Compact(voice: voice, controller: controller)
          : _Expanded(voice: voice, controller: controller),
    );
  }
}

/// The channel a call is in, read from the local store rather than passed in:
/// callers include this strip, the compact shell, and the rail's own footer
/// (`RailUserFooter`), and none of them holds a channel name for a channel
/// they are not currently showing.
class CallChannelName extends ConsumerWidget {
  const CallChannelName({
    super.key,
    required this.channelId,
    required this.style,
  });

  final String? channelId;
  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = channelId;
    final store = ref.watch(storeProvider).valueOrNull;
    if (id == null || store == null) return Text('In a call', style: style);

    return StreamBuilder<List<Channel>>(
      stream: store.watchChannels(),
      builder: (context, snapshot) {
        final name = snapshot.data
            ?.where((c) => c.id == id)
            .map((c) => c.name)
            .firstOrNull;
        return Text(
          name ?? 'In a call',
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}

/// The rail's version: who is in the call, then the controls beneath.
class _Expanded extends StatelessWidget {
  const _Expanded({required this.voice, required this.controller});

  final VoiceState voice;
  final VoiceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(AppIcons.voice, size: AppSizes.icon16, color: tokens.accent),
            const SizedBox(width: 6),
            Expanded(
              child: CallChannelName(
                channelId: voice.channelId,
                style: AppText.caption.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: AppWeights.medium,
                ),
              ),
            ),
            if (voice.connectedAt case final since?) CallDuration(since: since),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        _Faces(voice: voice),
        // Easiest place of all to miss a live share, so it is said in words.
        if (voice.screenSharing) ...[
          const SizedBox(height: 6),
          Text(
            'Sharing your screen',
            style: AppText.caption.copyWith(color: tokens.accent),
          ),
        ],
        const SizedBox(height: AppSpacing.s8),
        _Controls(voice: voice, controller: controller, compact: false),
      ],
    );
  }
}

/// Up to three faces with their names beneath, the way the design draws them;
/// past that a count, because a rail column has no room for a fourth.
class _Faces extends StatelessWidget {
  const _Faces({required this.voice});

  final VoiceState voice;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final shown = voice.participants.take(3).toList();
    final extra = voice.participants.length - shown.length;

    return Row(
      children: [
        for (final p in shown)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.s8),
            child: SizedBox(
              width: 40,
              child: Column(
                children: [
                  UserAvatar(
                    userId: p.identity,
                    name: p.name,
                    size: 28,
                    speaking: p.isSpeaking,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.isLocal ? 'you' : p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppText.micro.copyWith(color: tokens.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        if (extra > 0)
          Text(
            '+$extra',
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
      ],
    );
  }
}

/// The compact shell's version: one line, because it sits above the composer
/// and every pixel it takes is a pixel of conversation.
class _Compact extends StatelessWidget {
  const _Compact({required this.voice, required this.controller});

  final VoiceState voice;
  final VoiceController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Row(
      children: [
        for (final p in voice.participants.take(2))
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: UserAvatar(
              userId: p.identity,
              name: p.name,
              size: 20,
              speaking: p.isSpeaking,
            ),
          ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              CallChannelName(
                channelId: voice.channelId,
                style: AppText.caption.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: AppWeights.medium,
                ),
              ),
              Row(
                children: [
                  if (voice.connectedAt case final since?)
                    CallDuration(since: since),
                  Text(
                    // Says what the call is, so no unseen share is a mystery.
                    voice.screenSharing ? ' - sharing' : ' - audio only',
                    style: AppText.micro.copyWith(
                      color: voice.screenSharing
                          ? tokens.accent
                          : tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _Controls(voice: voice, controller: controller, compact: true),
      ],
    );
  }
}

/// Mic, deafen and leave, plus a way back to the call itself.
///
/// Screen share is deliberately not here on compact: the picker it opens needs
/// room the strip does not have, and the call screen one tap away has the
/// button already.
class _Controls extends ConsumerWidget {
  const _Controls({
    required this.voice,
    required this.controller,
    required this.compact,
  });

  final VoiceState voice;
  final VoiceController controller;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelId = voice.channelId;

    return Row(
      mainAxisAlignment: compact
          ? MainAxisAlignment.end
          : MainAxisAlignment.spaceEvenly,
      children: [
        AppIconButton(
          icon: voice.microphoneEnabled ? AppIcons.mic : AppIcons.micOff,
          semanticLabel: voice.microphoneEnabled ? 'Mute' : 'Unmute',
          tooltip: voice.microphoneEnabled ? 'Mute' : 'Unmute',
          onPressed: controller.toggleMicrophone,
        ),
        AppIconButton(
          icon: voice.deafened ? AppIcons.speakerOff : AppIcons.headphones,
          semanticLabel: voice.deafened ? 'Undeafen' : 'Deafen',
          tooltip: voice.deafened ? 'Undeafen' : 'Deafen',
          onPressed: controller.toggleDeafen,
        ),
        // Absent with no known channel rather than routing to nothing.
        if (channelId != null)
          AppIconButton(
            icon: AppIcons.back,
            semanticLabel: 'Back to the call',
            tooltip: 'Back to the call',
            onPressed: () => context.go(Routes.channel(channelId)),
          ),
        AppIconButton(
          icon: AppIcons.leaveCall,
          semanticLabel: 'Leave call',
          tooltip: 'Leave call',
          variant: AppIconButtonVariant.danger,
          onPressed: controller.leave,
        ),
      ],
    );
  }
}
