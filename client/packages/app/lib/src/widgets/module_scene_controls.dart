// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The row of buttons under a module scene.
///
/// Split out of `module_scene_view.dart` when the full-screen presentation
/// pushed that file past the review ceiling. They are free functions taking
/// what they need rather than methods on the view's state, which also makes
/// the set of things a control may touch explicit: the control names, whether
/// play is running, and two callbacks. A control cannot reach anything else.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

List<Widget> sceneControls({
  required List<String> controls,
  required bool playing,
  required VoidCallback onTogglePlay,
  required void Function(String action) onAction,
}) {
  final widgets = <Widget>[];
  for (final control in controls) {
    final button = _controlButton(control, playing, onTogglePlay, onAction);
    if (button != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.s8),
          child: button,
        ),
      );
    }
  }
  return widgets;
}

/// One control, or null for a name this client does not offer.
///
/// Deliberately never disabled on [_busy]. It used to be, and while playing
/// that meant every control greyed out and came back on each generation -
/// a visible flicker at eight times a second, reported as the buttons
/// flashing. A press landing mid-call is already a no-op, because [_send]
/// refuses a second call while one is in flight, so disabling them bought
/// nothing the guard did not already do and cost that.
Widget? _controlButton(
  String control,
  bool playing,
  VoidCallback onTogglePlay,
  void Function(String action) onAction,
) {
  switch (control) {
    case 'play':
      return AppIconButton(
        icon: playing ? AppIcons.pause : AppIcons.play,
        semanticLabel: playing ? 'Pause' : 'Play',
        tooltip: playing ? 'Pause' : 'Play',
        active: playing,
        onPressed: onTogglePlay,
      );
    case 'step':
      return AppIconButton(
        icon: AppIcons.forward,
        semanticLabel: 'Step forward',
        tooltip: 'Step forward',
        onPressed: () => onAction('step'),
      );
    case 'random':
      return AppIconButton(
        icon: AppIcons.highlight,
        semanticLabel: 'Randomise',
        tooltip: 'Randomise',
        onPressed: () => onAction('random'),
      );
    case 'clear':
      return AppIconButton(
        icon: AppIcons.eraser,
        semanticLabel: 'Clear',
        tooltip: 'Clear',
        onPressed: () => onAction('clear'),
      );
    case 'reset':
      return AppIconButton(
        icon: AppIcons.retry,
        semanticLabel: 'Reset',
        tooltip: 'Reset',
        onPressed: () => onAction('reset'),
      );
    default:
      return null;
  }
}
