// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The dnf path decision 0025 gives an rpm install: check the COPR repo is
/// there, enable it if it is not, then upgrade - every privileged step
/// through `pkexec`, so the system's own prompt is the consent.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/rpm_updater.dart';

/// One scripted `Process.run`, recording what it was asked to do.
class _Runner {
  _Runner(this.responses);

  final Map<String, ProcessResult> responses;
  final calls = <List<String>>[];

  Future<ProcessResult> call(String executable, List<String> arguments) async {
    calls.add([executable, ...arguments]);
    final key = [executable, ...arguments].join(' ');
    for (final entry in responses.entries) {
      if (key.contains(entry.key)) return entry.value;
    }
    return ProcessResult(0, 0, '', '');
  }
}

ProcessResult _ok([String out = '']) => ProcessResult(0, 0, out, '');
ProcessResult _fail(String err) => ProcessResult(0, 1, '', err);

void main() {
  group('repoListed', () {
    test('matches the repo id, not the description column', () {
      expect(
        repoListed(
          'repo id                    repo name\n'
          '$coprRepoId    Copr repo for slim-m\n'
          'fedora                     Fedora 44',
        ),
        isTrue,
      );
    });

    test('an enabled list without it is not a match', () {
      expect(repoListed('fedora  Fedora 44\nupdates  Updates'), isFalse);
    });
  });

  group('lastLines', () {
    test('keeps the tail and drops the blank lines between', () {
      expect(lastLines('one\n\ntwo\nthree\nfour\n'), 'two\nthree\nfour');
    });

    test('shorter output survives whole', () {
      expect(lastLines('only this'), 'only this');
    });
  });

  group('apply', () {
    test('upgrades straight away when the repo is already enabled', () async {
      final runner = _Runner({'repolist': _ok(coprRepoId)});
      final result = await RpmUpdater(run: runner.call).apply();

      expect(result.ok, isTrue);
      expect(
        runner.calls.any((c) => c.join(' ').contains('copr enable')),
        isFalse,
        reason: 'a repo already there must not be re-enabled',
      );
      expect(runner.calls.last, [
        'pkexec',
        'dnf',
        'upgrade',
        '--refresh',
        '-y',
        rpmPackage,
      ]);
    });

    test('enables the repo first when it is missing', () async {
      final runner = _Runner({'repolist': _ok('fedora  Fedora 44')});
      final result = await RpmUpdater(run: runner.call).apply();

      expect(result.ok, isTrue);
      expect(runner.calls[1], [
        'pkexec',
        'dnf',
        'copr',
        'enable',
        '-y',
        coprProject,
      ]);
      expect(runner.calls.last.contains('upgrade'), isTrue);
    });

    test('a refused prompt stops before the upgrade, and says why', () async {
      final runner = _Runner({
        'repolist': _ok('fedora  Fedora 44'),
        'copr enable': _fail('Error executing command as another user'),
      });
      final result = await RpmUpdater(run: runner.call).apply();

      expect(result.ok, isFalse);
      expect(result.detail, contains('another user'));
      expect(
        runner.calls.any((c) => c.contains('upgrade')),
        isFalse,
        reason: 'no point upgrading from a repo that is not there',
      );
    });

    test('a failed upgrade reports dnf\'s own last words', () async {
      final runner = _Runner({
        'repolist': _ok(coprRepoId),
        'upgrade': _fail('Error: Transaction failed\nNothing to do'),
      });
      final result = await RpmUpdater(run: runner.call).apply();

      expect(result.ok, isFalse);
      expect(result.detail, contains('Transaction failed'));
    });

    test('no dnf on this box is a failure, not a crash', () async {
      Future<ProcessResult> missing(String e, List<String> a) =>
          throw const ProcessException('dnf', [], 'No such file');
      final result = await RpmUpdater(run: missing).apply();

      expect(result.ok, isFalse);
    });
  });
}
