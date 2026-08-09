// SPDX-License-Identifier: Apache-2.0
/// Every SnackBar this app shows, in one place.
///
/// `ScaffoldMessengerState.showSnackBar` drives its own entrance and exit
/// with a plain `AnimationController` the messenger creates once and keys to
/// nothing this app controls - the identical gap the motion pass already
/// closed for `showDialog` and `showModalBottomSheet` inside `showAppSheet`
/// (`sheet.dart`). `snackBarAnimationStyle` is the framework's own documented
/// escape hatch for exactly this, the same one `showAppSheet` already reaches
/// for, so a call through here honours `AppMotion.isReduced` rather than only
/// the platform's own reduce-motion switch.
///
/// Fourteen call sites reached `ScaffoldMessenger` directly before this, one
/// of them (`personal_space_menu.dart`) already resolving it through
/// `maybeOf` rather than `.of` for no reason tied to its own behaviour, and
/// none customising duration, an action, or the default
/// `SnackBarBehavior.fixed` - so there was nothing to standardise there
/// beyond routing every one of them through here. A raw
/// [ScaffoldMessengerState.showSnackBar] call anywhere else in this app
/// silently drops the motion override; call [showAppSnackbar] instead, and
/// `reduce_motion_gate_test.dart` fails if a new one appears.
///
/// `HomeShell` puts the rail, the conversation pane and the member pane in
/// one shared `Scaffold` at wide layout, so a floating `SnackBar` triggered
/// from the rail or a popover positions itself against the whole shell's own
/// bottom edge - the same band `canvas_call_dock.dart`'s call controls float
/// in whenever a call is open. Every show here reads
/// `bottomDockReservationProvider` and pads the bottom by that much, so the
/// snackbar clears the dock instead of covering its leave-call button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/dock_reservation.dart';

/// Shows [message] in a plain SnackBar.
///
/// `maybeOf` rather than `.of`: no call site's message actually depends on
/// throwing when a `ScaffoldMessenger` is missing, and one already guarded
/// against exactly that with a null check of its own.
void showAppSnackbar(BuildContext context, String message) => _showOn(
  ScaffoldMessenger.maybeOf(context),
  reduceMotion: AppMotion.isReduced(context),
  reserveBottom: _reservedBottom(context),
  message: message,
);

/// 0 outside this app's own `ProviderScope` - `app_snackbar_test.dart` pumps
/// a bare `Scaffold` on purpose to isolate the motion behaviour this file
/// exists for, and that surface must keep working exactly as `maybeOf`
/// already lets a missing `ScaffoldMessenger` keep working.
double _reservedBottom(BuildContext context) {
  try {
    return ProviderScope.containerOf(
      context,
      listen: false,
    ).read(bottomDockReservationProvider);
  } on StateError {
    return 0;
  }
}

/// The same show, for a caller that has already resolved its own
/// [messenger], [reduceMotion] and [reserveBottom] before an `await` that
/// leaves its `BuildContext` unsafe to read again - `personal_space_menu.dart`'s
/// own shape, where the row this menu belongs to can be gone by the time the
/// request it is awaiting on answers.
void showResolvedSnackbar(
  ScaffoldMessengerState? messenger, {
  required bool reduceMotion,
  required String message,
  double reserveBottom = 0,
}) => _showOn(
  messenger,
  reduceMotion: reduceMotion,
  reserveBottom: reserveBottom,
  message: message,
);

/// Matches the framework's own floating default (`EdgeInsets.fromLTRB(15, 5,
/// 15, 10)`) whenever nothing needs reserving, and only departs from it on
/// the bottom edge, the one side a dock ever shares with this snackbar.
void _showOn(
  ScaffoldMessengerState? messenger, {
  required bool reduceMotion,
  required double reserveBottom,
  required String message,
}) {
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      margin: reserveBottom > 0
          ? EdgeInsets.fromLTRB(15, 5, 15, reserveBottom + AppSpacing.s16)
          : null,
    ),
    snackBarAnimationStyle: reduceMotion ? AnimationStyle.noAnimation : null,
  );
}
