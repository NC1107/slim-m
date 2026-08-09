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
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// Shows [message] in a plain SnackBar.
///
/// `maybeOf` rather than `.of`: no call site's message actually depends on
/// throwing when a `ScaffoldMessenger` is missing, and one already guarded
/// against exactly that with a null check of its own.
void showAppSnackbar(BuildContext context, String message) => _showOn(
  ScaffoldMessenger.maybeOf(context),
  reduceMotion: AppMotion.isReduced(context),
  message: message,
);

/// The same show, for a caller that has already resolved its own
/// [messenger] and [reduceMotion] before an `await` that leaves its
/// `BuildContext` unsafe to read again - `personal_space_menu.dart`'s own
/// shape, where the row this menu belongs to can be gone by the time the
/// request it is awaiting on answers.
void showResolvedSnackbar(
  ScaffoldMessengerState? messenger, {
  required bool reduceMotion,
  required String message,
}) => _showOn(messenger, reduceMotion: reduceMotion, message: message);

void _showOn(
  ScaffoldMessengerState? messenger, {
  required bool reduceMotion,
  required String message,
}) {
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(content: Text(message)),
    snackBarAnimationStyle: reduceMotion ? AnimationStyle.noAnimation : null,
  );
}
