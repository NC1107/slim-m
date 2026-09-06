// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Every code-block runner this viewer may use: `GET
/// /modules/code-block-runners`. An empty list means no installed and
/// enabled module declares a `code-block-runner` extension point the caller
/// holds the permission for - see docs/decisions/0021-modules-and-the-dock.md's
/// module-agnostic principle. `matchCodeBlockRunner` is the whole of how
/// `message_code_block_runner.dart` decides whether, and which, runner to
/// offer on one fenced block; nothing there knows what running code even
/// means, only how to compare a fence tag against a runner's own declared
/// `language`.
///
/// A deployment can install more than one runner module side by side once
/// each declares its own `language`, which is the point of this file: v1
/// picked the first result unconditionally, so two runner modules could
/// never coexist.
///
/// Invalidated wherever module install/enable/disable or a module
/// permission grant/revoke succeeds (`dock_module_sheet.dart`,
/// `module_permissions_section.dart`), since those are the only things that
/// change what this answers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'providers.dart';

final codeBlockRunnerProvider =
    FutureProvider.autoDispose<List<api.CodeBlockRunner>>(
      (ref) => ref.watch(apiProvider).listCodeBlockRunners(),
    );

/// A short slug on one side maps to the canonical name modules are expected
/// to declare on the other, so a fenced block tagged `js` still finds a
/// runner that declared `javascript`. Deliberately small: this is a display
/// convenience, not a language registry, and a module is always free to
/// declare the exact tag a block already uses.
const Map<String, String> _languageAliases = {
  'js': 'javascript',
  'node': 'javascript',
  'md': 'markdown',
  'py': 'python',
  'sh': 'shell',
  'bash': 'shell',
};

/// Lowercases [value] and resolves it through [_languageAliases], so a
/// block's own fence tag and a runner's declared `language` compare equal
/// regardless of case or which of a few common spellings each used.
String _normalizeLanguage(String value) {
  final lower = value.trim().toLowerCase();
  return _languageAliases[lower] ?? lower;
}

/// The first of [runners], in the order discovery returned them, that
/// matches [blockLanguage]: a runner with no declared `language` is a
/// wildcard and matches any block (including one with no language tag of
/// its own); a runner with one matches only a block whose own tag
/// normalizes to the same value. Null when nothing matches, meaning no Run
/// affordance should be shown for this block.
api.CodeBlockRunner? matchCodeBlockRunner(
  List<api.CodeBlockRunner> runners,
  String? blockLanguage,
) {
  final normalizedBlock = blockLanguage == null
      ? null
      : _normalizeLanguage(blockLanguage);
  for (final runner in runners) {
    final runnerLanguage = runner.language;
    if (runnerLanguage == null) return runner;
    if (normalizedBlock != null &&
        _normalizeLanguage(runnerLanguage) == normalizedBlock) {
      return runner;
    }
  }
  return null;
}
