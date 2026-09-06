// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
part of 'client.dart';

/// Discovering and running an installed module's command, per
/// `docs/decisions/0021-modules-and-the-dock.md`'s module-agnostic
/// principle: this client offers no UI hardcoded to a module id, only a
/// general "run this fenced code block through whatever runner discovery
/// hands back" affordance.
extension SlimmApiModuleCommands on SlimmApi {
  /// Every code-block runner this caller may currently use, possibly empty -
  /// an empty list means no installed and enabled module declares one the
  /// caller holds the permission for, so no Run affordance should be shown.
  Future<List<CodeBlockRunner>> listCodeBlockRunners() async {
    final json = await _send('GET', '/modules/code-block-runners');
    return (json as List<dynamic>)
        .map((r) => CodeBlockRunner.fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Runs [moduleId]'s [command] with [input], returning the module ABI's
  /// own outcome. Requires the module to be installed, enabled, and the
  /// caller to hold the permission the command declared.
  Future<RunModuleCommandResult> runModuleCommand({
    required String moduleId,
    required String command,
    required String input,
  }) async {
    final json = await _send(
      'POST',
      '/modules/$moduleId/commands/$command',
      body: {'input': input},
    );
    return RunModuleCommandResult.fromJson(json as Map<String, dynamic>);
  }
}
