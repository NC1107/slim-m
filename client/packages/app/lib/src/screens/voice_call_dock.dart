// SPDX-License-Identifier: Apache-2.0
/// The floating dock a connected call shows once the canvas is not already
/// open for its own channel: [CallControls] plus, room permitting, a one-tap
/// way into that channel's canvas.
///
/// Before this, the canvas was reachable only from the channel header - real
/// on every width (`CanvasOpenButton`'s own doc), but a participant already
/// mid-call had to look away from the stage to find it. The header stays the
/// only entry point outside a call and still carries the reachability guard
/// (`canvas_pane_test.dart`); this is the second, in-call one.
///
/// [canvasChannelId] is null wherever canvas is not this call's to open at
/// all - a DM, `CanvasOpenButton`'s own self-gating - and null is also what a
/// caller already inside `CanvasCallDock` passes: that dock's own tool strip
/// already carries "Close canvas", so a second canvas control glued onto the
/// call row here would be a redundant close button rather than a new
/// capability, exactly the crowding the owner already complained about this
/// dock for once.
///
/// **Never shrinks a touch target to make room.** [CallDockButton] draws
/// every control at a fixed size regardless of width, and the canvas toggle
/// is the same button. When the row - mic, camera, maybe switch-camera,
/// share, leave, and the toggle - would not fit the available width at that
/// fixed size, the toggle folds into a second row of its own inside the same
/// [FloatingDockCard] instead, the identical "phone stacks two rows" shape
/// `CanvasCallDock` already uses for the call-and-canvas combination. The
/// four call controls never move: they stay the row a hand reaches for
/// without looking, matching `CanvasCallDock`'s own "a call nobody can mute
/// or leave is the one failure this dock must never produce."
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/voice_controller.dart';
import '../widgets/floating_dock_card.dart';
import 'canvas/canvas_pane.dart';
import 'voice_call_controls.dart';

class VoiceCallDock extends StatelessWidget {
  const VoiceCallDock({
    super.key,
    required this.controller,
    required this.voice,
    this.canvasChannelId,
  });

  final VoiceController controller;
  final VoiceState voice;

  /// The channel the toggle opens, or null to omit the toggle entirely -
  /// see this file's own doc for the two reasons that happens.
  final String? canvasChannelId;

  @override
  Widget build(BuildContext context) {
    final channelId = canvasChannelId;
    final callRow = CallControls(controller: controller, voice: voice);
    if (channelId == null) {
      return FloatingDockCard(rows: [callRow]);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final toggle = _CanvasToggleButton(channelId: channelId);
        if (_fitsOneRow(context, constraints.maxWidth, voice.cameraEnabled)) {
          return FloatingDockCard(
            rows: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  callRow,
                  const SizedBox(width: AppSpacing.s8),
                  toggle,
                ],
              ),
            ],
          );
        }
        return FloatingDockCard(
          rows: [
            callRow,
            Center(child: toggle),
          ],
        );
      },
    );
  }
}

/// Whether the call row plus the canvas toggle fit one line at [width],
/// mirroring [CallDockButton]'s own fixed-size formula rather than measuring
/// real render objects - cheap, and exact, since every control here draws at
/// one of exactly two sizes and nothing here ever wraps text.
///
/// Every button sits inside an [AppFocusRing], whose own `Container` adds
/// `focusRingGap` padding plus its border's own `focusRingGap.dimensions` on
/// every edge, reserved whether or not the ring is drawn - the same
/// measured-not-assumed extra `voice_call_controls_density_test.dart`
/// already found for this same chip.
///
/// [FloatingDockCard]'s own `Container` costs an extra 2dp beyond its
/// declared padding too, for the identical reason: `Border.all()`'s default
/// 1dp width is itself `BoxDecoration.padding`, added on top rather than
/// painted over the declared padding.
bool _fitsOneRow(BuildContext context, double width, bool cameraEnabled) {
  final touch = AppTouchTargets.of(context);
  final hitTarget = touch ? AppSizes.rowTouch : AppSizes.rowPointer;
  final chip = AppSizes.controlMd > hitTarget ? AppSizes.controlMd : hitTarget;
  final button = chip + 2 * (focusRingGap + focusRingWidth);
  // mic, camera, [switch camera], share, leave, and the toggle itself.
  final controlCount = (cameraEnabled ? 5 : 4) + 1;
  final cardPadding = AppSpacing.s12 * 2 + 2;
  final needed =
      controlCount * button + (controlCount - 1) * AppSpacing.s8 + cardPadding;
  return needed <= width;
}

/// The toggle itself: [CallDockButton]'s own chip, lit while [channelId]'s
/// canvas is already open (unreachable in practice today, since opening it
/// swaps this whole screen out for `CanvasPane` - kept anyway, so a future
/// change that lets the two coexist inherits a toggle that already answers
/// correctly rather than one that has to be taught to).
class _CanvasToggleButton extends ConsumerWidget {
  const _CanvasToggleButton({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(canvasOpenProvider) == channelId;
    return CallDockButton(
      icon: AppIcons.canvas,
      tooltip: 'Open canvas',
      active: open,
      onPressed: () =>
          ref.read(canvasOpenProvider.notifier).state = open ? null : channelId,
    );
  }
}
