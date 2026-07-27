// SPDX-License-Identifier: Apache-2.0
/// Prompts for a report's reason before filing one: the one piece of free
/// text `POST /reports` requires alongside what is being reported.
library;

import 'package:flutter/material.dart';

/// Asks why [subjectLabel] is being reported. Returns the trimmed reason,
/// or null if the caller cancelled. The server rejects a blank reason
/// anyway, so the submit button stays disabled until there is one.
Future<String?> promptReportReason(
  BuildContext context, {
  required String subjectLabel,
}) async {
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report $subjectLabel'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 2000,
          decoration: const InputDecoration(hintText: 'What is wrong with it?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => FilledButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(value.text.trim()),
              child: const Text('Report'),
            ),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}
