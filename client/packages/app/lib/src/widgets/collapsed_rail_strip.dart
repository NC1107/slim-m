// SPDX-License-Identifier: Apache-2.0
/// The channel rail collapsed to a narrow icon strip, standing in for the
/// bottom controls [ChannelRail] would otherwise carry away with it:
/// settings, mic and deafen.
///
/// Deliberately not [ChannelRail] itself rendered at
/// [ChannelRail.collapsedWidth]: `channelRailVisibleProvider`'s own doc is
/// why the rail unmounts rather than shrinking to zero width -
/// [ChannelRail]'s `StreamBuilder`s poll the channel and category rosters
/// while built, and a hidden pane must not keep fetching. This widget only
/// reads voice *control* state (mic enabled, deafened) and the settings
/// route, neither of which touches a roster stream, so it stays lightweight
/// even mounted the whole time the rail is gone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/voice_controller.dart';
import 'channel_rail.dart';
import 'channel_rail_frame.dart';

/// Mirrors [RailUserFooter]'s three controls in a column instead of a row.
///
/// Carries no expand button of its own: [RailDragHandle] already renders
/// beside this strip the whole time the rail is collapsed and is the
/// published "only way back" (see its own doc, and the discoverability
/// test that pins it), including [AppIcons.sidebar] as its glyph. A second
/// control here would duplicate that exact icon and label on screen at
/// once, which is what `rail_drag_handle_test.dart`'s own single-match
/// assertions on both exist to catch - so this strip stays a pure control
/// panel and leaves expansion to the handle already doing that job.
class CollapsedRailStrip extends ConsumerWidget {
  const CollapsedRailStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final voice = ref.watch(voiceControllerProvider);
    final voiceController = ref.read(voiceControllerProvider.notifier);

    final buttons = [
      ...railVoiceToggleButtons(voice: voice, voiceController: voiceController),
      railSettingsButton(context),
    ];

    return Container(
      width: ChannelRail.collapsedWidth,
      color: tokens.surfaceSunken,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
          child: Column(
            children: [
              for (final button in buttons) ...[
                button,
                const SizedBox(height: AppSpacing.s8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
