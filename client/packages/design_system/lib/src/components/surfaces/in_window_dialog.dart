// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The one place the app pushes a modal dialog route.
///
/// With Flutter's `windowing` flag on, which the Linux build enables for the
/// pop-out, `showDialog` opens a native OS window and drops its route builder,
/// so every sheet, select and picker became a floating window. Pushing
/// [DialogRoute] directly keeps them inside the main window. Nothing else in
/// `client/packages/*/lib` may call `showDialog`; a gate enforces it.
library;

import 'package:flutter/material.dart';

import '../../app_motion.dart';

/// Pushes [builder] as an in-window Material dialog on the root navigator.
Future<T?> showInWindowDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  AnimationStyle? animationStyle,
  RouteSettings? routeSettings,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  return navigator.push<T>(
    DialogRoute<T>(
      context: context,
      builder: builder,
      themes: themes,
      barrierColor: DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      barrierDismissible: barrierDismissible,
      settings: routeSettings,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      animationStyle: animationStyle,
    ),
  );
}

/// [showTimePicker], kept in-window: Flutter's own calls `showDialog`.
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showInWindowDialog<TimeOfDay>(
    context: context,
    animationStyle:
        AppMotion.isReduced(context) ? AnimationStyle.noAnimation : null,
    builder: (_) => TimePickerDialog(initialTime: initialTime),
  );
}
