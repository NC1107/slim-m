// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/self_update/self_update_controller.dart';
import 'package:slimm_app/src/desktop/self_update/self_update_failure.dart';
import 'package:slimm_platform/platform.dart';

void _makeBundle(String path, String marker) {
  File('$path/Contents/MacOS/slimm_app')
    ..createSync(recursive: true)
    ..writeAsStringSync(marker);
}

void main() {
  late Directory root;
  late String exe;
  late String home;
  late int restarts;

  setUp(() {
    root = Directory.systemTemp.createTempSync('slimm-macos-controller-');
    _makeBundle('${root.path}/Applications/slim-m.app', 'new');
    _makeBundle('${root.path}/Applications/.slim-m.app.previous', 'old');
    exe = '${root.path}/Applications/slim-m.app/Contents/MacOS/slimm_app';
    home = '${root.path}/home';
    restarts = 0;
  });
  tearDown(() => root.deleteSync(recursive: true));

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        selfUpdateProvider.overrideWith(
          (ref) => SelfUpdateController(ref, restart: () async => restarts++),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Directory stateDir() =>
      Directory('$home/Library/Application Support/slim-m/self-update')
        ..createSync(recursive: true);

  test('selfApplyTarget takes a user bundle and refuses the rest', () {
    stateDir();
    final target = selfApplyTarget(
      format: InstallFormat.tarball,
      resolvedExecutable: exe,
      os: 'macos',
      home: home,
    );
    expect(target?.platformKey, 'macos');
    expect(target?.launcher.path, exe);
    for (final refused in [
      '/Volumes/slim-m/slim-m.app/Contents/MacOS/slimm_app',
      '/System/Applications/Foo.app/Contents/MacOS/foo',
    ]) {
      expect(
        selfApplyTarget(
          format: InstallFormat.tarball,
          resolvedExecutable: refused,
          os: 'macos',
          home: home,
        ),
        isNull,
      );
    }
    expect(
      selfApplyTarget(
        format: InstallFormat.rpm,
        resolvedExecutable: exe,
        os: 'macos',
        home: home,
      ),
      isNull,
    );
  });

  test(
    'a third start of an unconfirmed bundle restores and restarts',
    () async {
      final state = stateDir();
      File('${state.path}/pending').writeAsStringSync('0.89.0');
      File('${state.path}/pending.tries').writeAsStringSync('2');
      final c = container();
      await c
          .read(selfUpdateProvider)
          .confirmStart(
            resolvedExecutable: exe,
            os: 'macos',
            home: home,
            settle: Duration.zero,
          );
      expect(restarts, 1);
      expect(File(exe).readAsStringSync(), 'old');
      expect(File('${state.path}/rolled-back').readAsStringSync(), '0.89.0');
    },
  );

  test(
    'the restored version reports the rollback and keeps the previous bundle',
    () async {
      final state = stateDir();
      File('${state.path}/rolled-back').writeAsStringSync('0.89.0');
      final c = container();
      await c
          .read(selfUpdateProvider)
          .confirmStart(
            resolvedExecutable: exe,
            os: 'macos',
            home: home,
            settle: Duration.zero,
          );
      expect(restarts, 0);
      expect(
        c.read(selfUpdateFailureProvider)?.kind,
        SelfUpdateFailureKind.rolledBack,
      );
      expect(
        Directory(
          '${root.path}/Applications/.slim-m.app.previous',
        ).existsSync(),
        isTrue,
      );
    },
  );

  test('install refuses a disk-image copy before any network call', () async {
    var fetched = false;
    final c = ProviderContainer(
      overrides: [
        selfUpdateProvider.overrideWith(
          (ref) => SelfUpdateController(
            ref,
            fetch:
                ({
                  required currentVersion,
                  required platformKey,
                  required stagingDir,
                  required client,
                }) async {
                  fetched = true;
                  return null;
                },
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    await c
        .read(selfUpdateProvider)
        .install(
          currentVersion: '0.88.0',
          format: InstallFormat.tarball,
          resolvedExecutable:
              '/Volumes/slim-m/slim-m.app/Contents/MacOS/slimm_app',
          os: 'macos',
        );
    expect(fetched, isFalse);
    expect(
      c.read(selfUpdateFailureProvider)?.kind,
      SelfUpdateFailureKind.unsupportedInstall,
    );
  });
}
