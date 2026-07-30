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
}) => showDialog<String>(
  context: context,
  builder: (context) => _ReportReasonDialog(subjectLabel: subjectLabel),
);

/// Owns its own controller rather than one the caller disposes: the
/// `showDialog` future resolves as soon as the route is popped, well before
/// its exit transition finishes animating this content out, so disposing on
/// the caller's side raced that transition and used the controller after
/// disposing it. A widget's own `dispose()` only runs once the element is
/// actually removed, which is what this needs.
class _ReportReasonDialog extends StatefulWidget {
  const _ReportReasonDialog({required this.subjectLabel});

  final String subjectLabel;

  @override
  State<_ReportReasonDialog> createState() => _ReportReasonDialogState();
}

class _ReportReasonDialogState extends State<_ReportReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Report ${widget.subjectLabel}'),
    content: TextField(
      controller: _controller,
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
        valueListenable: _controller,
        builder: (context, value, _) => FilledButton(
          onPressed: value.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(value.text.trim()),
          child: const Text('Report'),
        ),
      ),
    ],
  );
}
