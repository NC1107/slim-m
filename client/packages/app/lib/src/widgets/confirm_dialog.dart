// SPDX-License-Identifier: Apache-2.0
/// A destructive-action confirmation, shared by the moderation and
/// administration screens rather than each hand-rolling `settings_screen.dart`'s
/// account-deletion dialog again.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// Asks before a destructive, hard-to-undo action. [message] must state what
/// happens, not just ask "are you sure?".
///
/// [cancelLabel] names the way out where "Cancel" is vaguer than the choice
/// deserves. Its absence is why one caller copied this whole dialog rather
/// than reuse it.
Future<bool> confirmDangerousAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      // Danger is outlined, never filled: the destructive choice must be
      // unmistakable without being the brightest thing in the dialog.
      actions: [
        AppButton(
          label: cancelLabel,
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: confirmLabel,
          variant: AppButtonVariant.danger,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
