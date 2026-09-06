// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Running a module slash command on send, kept out of the composer's own
/// State so the whole send-a-`/command` path is one testable function rather
/// than more lines on an already-large widget.
///
/// A module is a pure function; there is no bot identity to post as, so the
/// module's own output becomes the composed text and goes out as an ordinary
/// message through the composer's existing send path ([post]). A failure - a
/// 403, or the module's own error - posts nothing and reports through [fail],
/// leaving the `/command` text in the field to retry.
library;

import 'package:flutter/widgets.dart';
import 'package:slimm_api/api.dart';

import '../api_failure.dart';

/// Runs [command] with [args] and applies the outcome: on a non-empty result,
/// replaces the field text with it and [post]s; on an empty-but-ok result,
/// clears the field; on any failure, calls [fail] with a human message.
Future<void> sendSlashCommand({
  required SlimmApi api,
  required SlashCommand command,
  required String args,
  required TextEditingController controller,
  required Future<void> Function() post,
  required void Function(String message) fail,
}) async {
  try {
    final result = await api.runModuleCommand(
      moduleId: command.moduleId,
      command: command.command,
      input: args,
    );
    final output = result.output;
    if (result.ok && output != null && output.trim().isNotEmpty) {
      controller.text = output;
      await post();
    } else if (result.ok) {
      controller.clear();
    } else {
      fail(result.error ?? 'The command did not run.');
    }
  } on ApiException catch (e) {
    fail(describeApiFailure('run /${command.name}', e));
  }
}
