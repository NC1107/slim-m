// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:slimm_app/src/desktop/self_update/self_update.dart';
import 'package:slimm_app/src/desktop/self_update/self_update_controller.dart';
import 'package:slimm_app/src/desktop/self_update/self_update_failure.dart';
import 'package:slimm_app/src/desktop/self_update/windows_layout.dart';
import 'package:slimm_platform/platform.dart';

void _makeVersion(Directory root, String version) {
  Directory('${root.path}/app-$version').createSync(recursive: true);
  File('${root.path}/app-$version/slimm_app.exe').writeAsStringSync(version);
}

void _pointer(Directory root, String name, String version) =>
    File('${root.path}/$name').writeAsStringSync(version);

String? _read(Directory root, String name) {
  final file = File('${root.path}/$name');
  return file.existsSync() ? file.readAsStringSync() : null;
}

Future<void> _fakeUnpack(File archive, Directory into) async =>
    File('${into.path}/slimm_app.exe').writeAsStringSync('new');

VerifiedUpdate _update(Directory root, String version) {
  final file = File('${root.path}/.staging/pkg-$version.zip')
    ..createSync(recursive: true);
  return VerifiedUpdate.forTest(
    version: version,
    tag: 'client-v$version',
    file: file,
  );
}

void main() {
  late Directory root;
  late WindowsInstallLayout layout;

  setUp(() {
    root = Directory.systemTemp.createTempSync('slimm-windows-install-');
    _makeVersion(root, '0.88.0');
    File('${root.path}/slim-m.exe').writeAsStringSync('launcher');
    _pointer(root, 'current', '0.88.0');
    layout = WindowsInstallLayout(root);
  });
  tearDown(() => root.deleteSync(recursive: true));

  group('SelfUpdateController on windows', () {
    ProviderContainer containerWith(FetchUpdate fetch) {
      final container = ProviderContainer(
        overrides: [
          selfUpdateProvider.overrideWith(
            (ref) => SelfUpdateController(
              ref,
              fetch: fetch,
              unpack: _fakeUnpack,
              newClient: http.Client.new,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test(
      'fetches the windows-x64 artifact into the layout and stages it',
      () async {
        String? key;
        Directory? staging;
        final container = containerWith(({
          required currentVersion,
          required platformKey,
          required stagingDir,
          required client,
        }) async {
          key = platformKey;
          staging = stagingDir;
          return _update(root, '0.89.0');
        });
        final version = await container
            .read(selfUpdateProvider)
            .install(
              currentVersion: '0.88.0',
              format: InstallFormat.tarball,
              resolvedExecutable: '${root.path}/app-0.88.0/slimm_app.exe',
              os: 'windows',
            );
        expect(version, '0.89.0');
        expect(key, 'windows-x64');
        expect(staging?.path, layout.stagingDir.path);
        expect(_read(root, 'current'), '0.89.0');
        expect(container.read(stagedUpdateVersionProvider), '0.89.0');
      },
    );

    test(
      'a machine-wide or MSIX install refuses without touching the network',
      () async {
        var fetched = false;
        final container = containerWith(({
          required currentVersion,
          required platformKey,
          required stagingDir,
          required client,
        }) async {
          fetched = true;
          return null;
        });
        for (final exe in [
          r'C:\Program Files\slim-m\app-0.88.0\slimm_app.exe',
          r'C:\Program Files\WindowsApps\Slimm_1.0_x64__abc\slimm_app.exe',
          '${root.path}/slimm_app.exe',
        ]) {
          await container
              .read(selfUpdateProvider)
              .install(
                currentVersion: '0.88.0',
                format: InstallFormat.tarball,
                resolvedExecutable: exe,
                os: 'windows',
              );
          expect(
            container.read(selfUpdateFailureProvider)?.kind,
            SelfUpdateFailureKind.unsupportedInstall,
          );
        }
        expect(fetched, isFalse);
        expect(_read(root, 'current'), '0.88.0');
      },
    );

    test(
      'confirmStart reports a launcher rollback and prunes after settling',
      () async {
        _makeVersion(root, '0.80.0');
        _pointer(root, 'rolled-back', '0.89.0');
        final container = containerWith(
          ({
            required currentVersion,
            required platformKey,
            required stagingDir,
            required client,
          }) async => null,
        );
        await container
            .read(selfUpdateProvider)
            .confirmStart(
              resolvedExecutable: '${root.path}/app-0.88.0/slimm_app.exe',
              os: 'windows',
              settle: Duration.zero,
            );
        expect(
          container.read(selfUpdateFailureProvider)?.kind,
          SelfUpdateFailureKind.rolledBack,
        );
        expect(Directory('${root.path}/app-0.80.0').existsSync(), isFalse);
      },
    );
  });
}
