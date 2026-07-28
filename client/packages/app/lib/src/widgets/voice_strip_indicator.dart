// SPDX-License-Identifier: Apache-2.0
/// The collapsed call bar: shown wherever the app is while a call stays
/// connected in the background, so leaving it does not mean forgetting it.
///
/// Its own file so a caller outside `screens/voice_screen.dart` (the channel
/// rail) can show it without a screens-to-widgets import running backwards.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/voice_controller.dart';

/// Whether a call is live and worth surfacing, regardless of which channel
/// is on screen. The caller decides *where* it renders; this decides *if*.
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
          // Collapsed is exactly when a live share is easiest to forget.
          if (voice.screenSharing)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s8),
              child: Tooltip(
                message: 'You are sharing your screen',
                child: Icon(
                  AppIcons.screenShare,
                  size: 16,
                  color: tokens.accent,
                ),
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
