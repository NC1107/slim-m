// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A version the launcher rolled back from is never installed again.
///
/// Before this, nothing recorded which version had been rolled back, so the
/// next start's update pass saw the bad version as newer than the restored
/// one, swapped `current` back to it and relaunched: a rollback, reinstall and
/// crash cycle on every app open. The fetch fake below honours the real
/// contract (`fetchVerifiedUpdate` returns null unless the candidate is newer
/// than the version it is given), so what is asserted is the whole decision.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimm_app/src/desktop/self_update/self_update.dart';
import 'package:slimm_app/src/desktop/self_update/self_update_controller.dart';
import 'package:slimm_app/src/desktop/update_check.dart' show isNewer;
import 'package:slimm_platform/platform.dart';

Future<void> _fakeUnpack(File archive, Directory into) async {
  File('${into.path}/slimm_app').writeAsStringSync('#!/bin/sh\nexit 0\n');
  File('${into.path}/slim-m').writeAsStringSync('#!/bin/sh\nexit 0\n');
}

void main() {
  late Directory root;
  late List<String> fetchedAgainst;

  setUp(() {
    root = Directory.systemTemp.createTempSync('slimm-rollback-floor-');
    Directory('${root.path}/0.88.0').createSync();
    File('${root.path}/0.88.0/slimm_app').writeAsStringSync('');
    Link('${root.path}/current').createSync('0.88.0');
    fetchedAgainst = [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// The release channel's newest version is [latest].
  ProviderContainer containerFor(String latest) {
    final container = ProviderContainer(
      overrides: [
        selfUpdateProvider.overrideWith(
          (ref) => SelfUpdateController(
            ref,
            unpack: _fakeUnpack,
            newClient: http.Client.new,
            fetch:
                ({
                  required currentVersion,
                  required platformKey,
                  required stagingDir,
                  required client,
                }) async {
                  fetchedAgainst.add(currentVersion);
                  if (!isNewer(latest, currentVersion)) return null;
                  final file = File('${root.path}/.staging/pkg-$latest.tar.gz')
                    ..createSync(recursive: true);
                  return VerifiedUpdate.forTest(
                    version: latest,
                    tag: 'client-v$latest',
                    file: file,
                  );
                },
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<String?> startupInstall(ProviderContainer container) => container
      .read(selfUpdateProvider)
      .install(
        currentVersion: '0.88.0',
        format: InstallFormat.tarball,
        resolvedExecutable: '${root.path}/0.88.0/slimm_app',
      );

  String? currentLink() => Link('${root.path}/current').targetSync();

  test('the start after a rollback does not reinstall the bad version, '
      'before or after the notice is read', () async {
    File('${root.path}/rolled-back').writeAsStringSync('0.89.0\n');

    expect(await startupInstall(containerFor('0.89.0')), isNull);
    expect(currentLink(), '0.88.0');

    final launch = containerFor('0.89.0');
    await launch
        .read(selfUpdateProvider)
        .confirmStart(
          resolvedExecutable: '${root.path}/0.88.0/slimm_app',
          settle: Duration.zero,
        );
    expect(File('${root.path}/rolled-back').existsSync(), isFalse);

    expect(
      await startupInstall(containerFor('0.89.0')),
      isNull,
      reason: 'the marker is consumed by then; the record must outlive it',
    );
    expect(currentLink(), '0.88.0');
  });

  test('a release newer than the one rolled back still installs', () async {
    File('${root.path}/rolled-back').writeAsStringSync('0.89.0');
    final container = containerFor('0.90.0');
    expect(await startupInstall(container), '0.90.0');
    expect(currentLink(), '0.90.0');
  });

  test(
    'with no rollback on record the fetch sees the running version',
    () async {
      await startupInstall(containerFor('0.88.0'));
      expect(fetchedAgainst, ['0.88.0']);
    },
  );
}
