// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The content of the pop-out window: one feed and the two call controls.
///
/// It renders the same `screenShareViewFor`/`cameraViewFor` widget the call
/// screen and mini-player render, in the same engine, so the pop-out is a
/// reparent and never a second subscription. Density follows this window's own
/// width, not the main window's and not the platform
/// (docs/design/desktop-vs-mobile.md, law 1 and law 2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/call_mini_player.dart';
import '../providers/voice_controller.dart';
import '../providers/voice_flags.dart';

const popOutWindowKey = Key('popout_window_view');

class PopOutWindowView extends ConsumerWidget {
  const PopOutWindowView({super.key, required this.feed});

  final MiniPlayerFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final controller = ref.read(voiceControllerProvider.notifier);
    final micOn = ref.watch(
      voiceFlagsProvider.select((f) => f.microphoneEnabled),
    );
    final view = switch (feed.kind) {
      FeedKind.screenShare => controller.screenShareViewFor(feed.identity),
      FeedKind.camera => controller.cameraViewFor(feed.identity),
    };
    final label = switch (feed.kind) {
      FeedKind.screenShare => "${feed.name}'s screen",
      FeedKind.camera => feed.name,
    };

    // The window root has no Navigator above it, and tooltips need an Overlay.
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => Material(
            key: popOutWindowKey,
            color: tokens.surfaceSunken,
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: Colors.black, child: view),
                      Positioned(
                        left: AppSpacing.s8,
                        right: AppSpacing.s8,
                        bottom: AppSpacing.s4,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.micro.copyWith(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: AppSpacing.s16,
                  children: [
                    AppIconButton(
                      icon: micOn ? AppIcons.mic : AppIcons.micOff,
                      semanticLabel: micOn ? 'Mute' : 'Unmute',
                      tooltip: micOn ? 'Mute' : 'Unmute',
                      onPressed: controller.toggleMicrophone,
                    ),
                    AppIconButton(
                      icon: AppIcons.leaveCall,
                      semanticLabel: 'Leave call',
                      tooltip: 'Leave call',
                      variant: AppIconButtonVariant.danger,
                      onPressed: controller.leave,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
