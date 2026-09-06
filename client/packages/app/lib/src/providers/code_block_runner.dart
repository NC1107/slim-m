// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The one code-block runner this viewer may use, if any: `GET
/// /modules/code-block-runners`. Null means no installed and enabled module
/// declares a `code-block-runner` extension point the caller holds the
/// permission for - see docs/decisions/0021-modules-and-the-dock.md's
/// module-agnostic principle. This is the whole of how `message_text.dart`
/// decides whether to offer Run on a fenced code block; nothing there knows
/// what running code even means.
///
/// A deployment could in principle install more than one such module; this
/// client offers only the first discovery returns, matching v1's own
/// single-runner scope.
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
    FutureProvider.autoDispose<api.CodeBlockRunner?>((ref) async {
      final runners = await ref.watch(apiProvider).listCodeBlockRunners();
      return runners.isEmpty ? null : runners.first;
    });
