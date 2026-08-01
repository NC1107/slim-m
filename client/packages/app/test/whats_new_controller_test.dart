// SPDX-License-Identifier: Apache-2.0
/// Tests for the three design constraints the what's-new sheet is built
/// around: it shows once after an upgrade, never on a fresh install, and
/// never again for a version already seen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/whats_new_controller.dart';

void _mockVersion(String version) {
  PackageInfo.setMockInitialValues(
    appName: 'slim-m',
    packageName: 'top.npcserver.slimm',
    version: version,
    buildNumber: '1',
    buildSignature: '',
  );
}

/// [fresh] models what `restoreSession` would already have decided by the
/// time anything reads the controller: true only for a genuinely first
/// launch (or an indistinguishable wipe), matching
/// [isFreshInstallProvider]'s own doc.
///
/// Reads [whatsNewControllerProvider] once before returning: it is a lazy
/// `StateNotifierProvider`, so nothing runs its constructor, and therefore
/// nothing starts the async check, until something reads it. A real launch
/// gets that read from `WhatsNewGate`; here it is this helper.
ProviderContainer _container({required bool fresh}) {
  final container = ProviderContainer(
    overrides: [isFreshInstallProvider.overrideWith((ref) => fresh)],
  );
  addTearDown(container.dispose);
  container.read(whatsNewControllerProvider);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'a fresh install never shows anything and records the current version',
    () async {
      _mockVersion('0.17.2');
      final container = _container(fresh: true);
      await pumpEventQueue();

      expect(container.read(whatsNewControllerProvider), isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(lastSeenWhatsNewVersionKey),
        '0.17.2',
        reason:
            'a first launch must record a baseline, or the next real '
            'upgrade would replay every entry ever written as if all of it '
            'were new',
      );
    },
  );

  test('an upgrade with no prior what\'s-new record shows the entries up to '
      'the current version', () async {
    // An existing (not fresh) install with no what's-new key ever written.
    _mockVersion('0.17.2');
    final container = _container(fresh: false);
    await pumpEventQueue();

    final pending = container.read(whatsNewControllerProvider);
    expect(
      pending,
      isNotEmpty,
      reason:
          'the 0.17.2 message-reconciliation note must reach existing '
          'installs, not only fresh ones',
    );
  });

  test('once shown and marked seen, a relaunch on the same version shows '
      'nothing again', () async {
    _mockVersion('0.17.2');
    final first = _container(fresh: false);
    await pumpEventQueue();
    expect(first.read(whatsNewControllerProvider), isNotEmpty);

    await first.read(whatsNewControllerProvider.notifier).markSeen();
    expect(first.read(whatsNewControllerProvider), isEmpty);

    // Models a relaunch: only what was persisted carries forward.
    final relaunch = _container(fresh: false);
    await pumpEventQueue();
    expect(relaunch.read(whatsNewControllerProvider), isEmpty);
  });

  test('marking seen before anything is shown is a no-op, so a stray call '
      'cannot advance the recorded version early', () async {
    _mockVersion('0.17.2');
    final container = _container(fresh: true);
    await pumpEventQueue();

    await container.read(whatsNewControllerProvider.notifier).markSeen();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(lastSeenWhatsNewVersionKey), '0.17.2');
  });
}
