// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Applying a client update to an rpm install, through dnf.
///
/// Decision 0020 fixed the rule: an rpm is root-owned, so the app never
/// replaces its own files; it asks the package manager to. `pkexec` puts
/// the system's own polkit prompt in front of that, which is the consent
/// step - the app never escalates silently. The package comes from the COPR
/// repo `release.yml` publishes on every client release, so the first thing
/// checked is that the repo is enabled at all; without it dnf would report
/// "nothing to do" against a release page it cannot see.
library;

import 'dart:io';

/// How dnf is run, so a test can script exit codes and output.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

Future<ProcessResult> _realRunner(String executable, List<String> arguments) =>
    Process.run(executable, arguments);

/// The COPR project the rpm updates from.
const coprProject = 'nc1107/slim-m';

/// The repo id dnf lists once that project is enabled.
const coprRepoId = 'copr:copr.fedorainfracloud.org:nc1107:slim-m';

const rpmPackage = 'slim-m-client';

/// One dnf step's outcome, kept as the last lines dnf printed so a failure
/// can be shown in the splash verbatim rather than as "update failed".
class RpmUpdateResult {
  const RpmUpdateResult({required this.ok, required this.detail});

  final bool ok;
  final String detail;
}

class RpmUpdater {
  const RpmUpdater({ProcessRunner run = _realRunner}) : _run = run;

  final ProcessRunner _run;

  /// Whether the COPR repo is enabled, read from `dnf repolist --enabled`,
  /// which needs no privilege.
  Future<bool> repoEnabled() async {
    try {
      final result = await _run('dnf', ['repolist', '--enabled']);
      return result.exitCode == 0 && repoListed('${result.stdout}');
    } on ProcessException {
      return false;
    }
  }

  /// Enables the repo if needed, then upgrades the package. Each privileged
  /// step goes through `pkexec`, so the user sees the system's own prompt
  /// once per step; a refused prompt is a non-zero exit like any other.
  Future<RpmUpdateResult> apply() async {
    if (!await repoEnabled()) {
      final enabled = await _privileged([
        'dnf',
        'copr',
        'enable',
        '-y',
        coprProject,
      ]);
      if (!enabled.ok) return enabled;
    }
    return _privileged(['dnf', 'upgrade', '--refresh', '-y', rpmPackage]);
  }

  Future<RpmUpdateResult> _privileged(List<String> command) async {
    try {
      final result = await _run('pkexec', command);
      return RpmUpdateResult(
        ok: result.exitCode == 0,
        detail: lastLines('${result.stdout}\n${result.stderr}'),
      );
    } on ProcessException catch (e) {
      return RpmUpdateResult(ok: false, detail: e.message);
    }
  }
}

/// Whether [repolist] (dnf's `repolist --enabled` output) names the COPR
/// repo. Matched on the id, not the description column, which dnf5 renames.
bool repoListed(String repolist) =>
    repolist.split('\n').any((line) => line.trim().startsWith(coprRepoId));

/// The last few non-empty lines of [output], for a failure detail line.
String lastLines(String output, {int count = 3}) {
  final lines = output
      .split('\n')
      .map((l) => l.trimRight())
      .where((l) => l.trim().isNotEmpty)
      .toList();
  return lines.skip(lines.length > count ? lines.length - count : 0).join('\n');
}
