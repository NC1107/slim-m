// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Discovering and running an installed module's command, per
/// `docs/decisions/0021-modules-and-the-dock.md`'s module-agnostic
/// principle: nothing here knows what any command does, only that a
/// `(module_id, command)` pair exists and how to POST to it.
///
/// Split out of models.dart purely to stay under this repo's line budget.
library;

/// One `(module_id, command)` pair this caller may POST to via
/// `runModuleCommand`, from `GET /modules/code-block-runners`.
class CodeBlockRunner {
  const CodeBlockRunner({required this.moduleId, required this.command});

  final String moduleId;
  final String command;

  factory CodeBlockRunner.fromJson(Map<String, dynamic> json) =>
      CodeBlockRunner(
        moduleId: json['module_id'] as String,
        command: json['command'] as String,
      );
}

/// The module ABI's own outcome, echoed straight through by `POST
/// /modules/{moduleId}/commands/{command}`: either [output] on success, or
/// [error] - the module's own declared failure, or a clean description of a
/// host-level refusal (a resource limit, say). Never thrown as an API
/// exception: only a transport-level failure (network, permission, gating)
/// is.
class RunModuleCommandResult {
  const RunModuleCommandResult({required this.ok, this.output, this.error});

  final bool ok;
  final String? output;
  final String? error;

  factory RunModuleCommandResult.fromJson(Map<String, dynamic> json) =>
      RunModuleCommandResult(
        ok: json['ok'] as bool,
        output: json['output'] as String?,
        error: json['error'] as String?,
      );
}
