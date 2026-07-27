// SPDX-License-Identifier: Apache-2.0
/// The in-call control bar: mute, screen share and leave, plus the quality
/// picker sharing opens.
///
/// Its own file because `voice_screen.dart` was over this repo's hard file
/// limit, and the bar is the one part of that screen with no dependency on
/// which channel is being looked at.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import '../providers/voice_controller.dart';

class CallControls extends StatelessWidget {
  const CallControls({
    super.key,
    required this.controller,
    required this.voice,
  });

  final VoiceController controller;
  final VoiceState voice;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // Decoration outside, SafeArea inside, the same shape the rail's bars use:
    // insetting the bar itself would leave a scaffold-coloured band below it.
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceSunken,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s12),
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
        ),
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
