// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A fenced code block's shared run result: the output everyone viewing the
/// message sees, keyed by the block's index within the message.
///
/// One shape for both the REST field on a message and the live
/// `code_run.changed` event, because - unlike a reaction, whose `reacted` flag
/// is per-viewer - a run's output is the same fact for everyone who can see
/// the message, so there is nothing per-viewer to keep on a separate type.
library;

class CodeRun {
  const CodeRun({
    required this.blockIndex,
    required this.moduleId,
    required this.command,
    required this.ok,
    required this.output,
    required this.ranBy,
    required this.ranAt,
  });

  /// Which fenced code block in the message this is the result of.
  final int blockIndex;
  final String moduleId;
  final String command;

  /// Whether the run succeeded; [output] is the module's output when true, or
  /// its error message when false.
  final bool ok;
  final String output;

  /// Who ran it, or null once their account is anonymized.
  final String? ranBy;
  final int ranAt;

  factory CodeRun.fromJson(Map<String, dynamic> json) => CodeRun(
        blockIndex: json['block_index'] as int,
        moduleId: json['module_id'] as String,
        command: json['command'] as String,
        ok: json['ok'] as bool,
        output: json['output'] as String,
        ranBy: json['ran_by'] as String?,
        ranAt: json['ran_at'] as int,
      );
}
