// SPDX-License-Identifier: Apache-2.0
/// A destructive-action confirmation, shared by the moderation and
/// administration screens rather than each hand-rolling `settings_screen.dart`'s
/// account-deletion dialog again.
library;

import 'package:flutter/material.dart';

/// Asks before a destructive, hard-to-undo action. [message] must state what
/// happens, not just ask "are you sure?".
Future<bool> confirmDangerousAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
