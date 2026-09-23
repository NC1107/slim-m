// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The splash's update pass (decision 0025): ask once, and from then on
/// install a newer version during the mini splash when the answer was yes.
///
/// Every case drives the prompt the way a person does - by reading the
/// buttons off `startupPromptProvider` and calling one - because the pass
/// genuinely waits on that answer and a test that skipped it would prove
/// nothing about the waiting.
library;

import 'package:http/http.dart' as http;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/desktop/rpm_updater.dart';
import 'package:slimm_app/src/desktop/startup_screen.dart';
import 'package:slimm_app/src/desktop/startup_state.dart';
import 'package:slimm_app/src/desktop/startup_updates.dart';
import 'package:slimm_app/src/desktop/update_check.dart';
import 'package:slimm_app/src/diagnostics/debug_log.dart';
import 'package:slimm_app/src/providers/auto_update_preference.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

ClientUpdate _update([InstallFormat format = InstallFormat.rpm]) =>
    ClientUpdate(
      version: '9.9.9',
      releaseUrl: 'https://example.invalid/release',
      format: format,
    );

/// A check that always finds [found], recording whether it ran at all.
class _Check {
  _Check(this.found);

  final ClientUpdate? found;
  var ran = false;

  Future<ClientUpdate?> call({
    required String currentVersion,
    http.Client? client,
    InstallFormat? format,
  }) async {
    ran = true;
    return found;
  }
}

/// A dnf that reports [ok] without touching the system.
class _Dnf implements RpmUpdater {
  _Dnf({this.ok = true, this.detail = ''});

  final bool ok;
  final String detail;
  var applied = false;

  @override
  Future<RpmUpdateResult> apply() async {
    applied = true;
    return RpmUpdateResult(ok: ok, detail: detail);
  }

  @override
  Future<bool> repoEnabled() async => true;

  @override
  Future<String?> installedVersion() async => '1.0.0';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer container({bool signedIn = true}) {
    final c = ProviderContainer(
      overrides: [
        preferencesProvider.overrideWith(
          (ref) => SharedPreferences.getInstance(),
        ),
        sessionProvider.overrideWithValue(
          api.SessionStore(tokens: signedIn ? _tokens : null),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Answers whatever the pass asks next, once it has asked. Returns the
  /// prompt it answered so a caller can assert on its wording.
  Future<StartupPrompt> answer(
    ProviderContainer c, {
    required bool primary,
  }) async {
    StartupPrompt? prompt;
    for (var i = 0; i < 200 && prompt == null; i++) {
      await Future<void>.delayed(Duration.zero);
      prompt = c.read(startupPromptProvider);
    }
    expect(prompt, isNotNull, reason: 'the splash never asked anything');
    final asked = prompt!;
    primary ? asked.onPrimary() : asked.onSecondary();
    return asked;
  }

  test('an install that has already said no is never asked again, and never '
      'even checks', () async {
    SharedPreferences.setMockInitialValues({autoUpdateKey: false});
    final c = container();
    final check = _Check(_update());

    await runStartupUpdates(
      c,
      check: check.call,
      format: InstallFormat.rpm,
      currentVersion: '1.0.0',
    );

    expect(check.ran, isFalse);
    expect(c.read(startupPromptProvider), isNull);
  });

  test('a signed-out install is not asked here - signup asks it', () async {
    final c = container(signedIn: false);
    final check = _Check(_update());

    await runStartupUpdates(
      c,
      check: check.call,
      format: InstallFormat.rpm,
      currentVersion: '1.0.0',
    );

    expect(c.read(startupPromptProvider), isNull);
    expect(check.ran, isFalse);
    expect(
      (await SharedPreferences.getInstance()).containsKey(autoUpdateKey),
      isFalse,
      reason: 'not asking must not count as an answer',
    );
  });

  test('a signed-in install with no answer yet is asked, and a no is '
      'remembered', () async {
    final c = container();
    final check = _Check(_update());

    final pass = runStartupUpdates(
      c,
      check: check.call,
      format: InstallFormat.rpm,
      currentVersion: '1.0.0',
    );
    final prompt = await answer(c, primary: false);
    await pass;

    expect(prompt.title, 'Keep slim-m up to date automatically?');
    expect(prompt.detail, contains('password'));
    expect(check.ran, isFalse, reason: 'a no stops before the check');
    expect(
      (await SharedPreferences.getInstance()).getBool(autoUpdateKey),
      isFalse,
    );
  });

  test('a dnf install relaunches into the new build without asking', () async {
    SharedPreferences.setMockInitialValues({autoUpdateKey: true});
    final c = container();
    final dnf = _Dnf();
    var relaunched = false;
    final prompts = <StartupPrompt?>[];
    final sub = c.listen(startupPromptProvider, (_, next) => prompts.add(next));

    await runStartupUpdates(
      c,
      check: _Check(_update()).call,
      rpm: dnf,
      relaunch: () async => relaunched = true,
      format: InstallFormat.rpm,
      currentVersion: '1.0.0',
    );
    sub.close();

    expect(dnf.applied, isTrue);
    expect(relaunched, isTrue);
    expect(
      prompts.whereType<StartupPrompt>(),
      isEmpty,
      reason: 'the splash must not stop on a question it answers itself',
    );
    expect(c.read(startupStatusProvider), 'Restarting into 9.9.9');
  });

  test('a dnf that fails falls back to offering the release, and does not '
      'pretend it installed anything', () async {
    SharedPreferences.setMockInitialValues({autoUpdateKey: true});
    final c = container();

    final pass = runStartupUpdates(
      c,
      check: _Check(_update()).call,
      rpm: _Dnf(ok: false, detail: 'Error: Transaction failed'),
      relaunch: () async => fail('nothing was installed to restart into'),
      format: InstallFormat.rpm,
      currentVersion: '1.0.0',
    );
    final prompt = await answer(c, primary: false);
    await pass;

    expect(prompt.title, 'Version 9.9.9 is available');
    expect(
      c.read(debugLogProvider).any((e) => e.message.contains('dnf')),
      isTrue,
      reason: 'the failure has to be diagnosable afterwards',
    );
  });

  test('a format dnf cannot touch is offered, not installed', () async {
    SharedPreferences.setMockInitialValues({autoUpdateKey: true});
    final c = container();
    final dnf = _Dnf();

    final pass = runStartupUpdates(
      c,
      check: _Check(_update(InstallFormat.flatpak)).call,
      rpm: dnf,
      relaunch: () async => fail('a flatpak is never installed from here'),
      format: InstallFormat.flatpak,
      currentVersion: '1.0.0',
    );
    final prompt = await answer(c, primary: false);
    await pass;

    expect(dnf.applied, isFalse);
    expect(prompt.detail, updateActionHint(InstallFormat.flatpak));
  });

  test('nothing newer means nothing is shown at all', () async {
    SharedPreferences.setMockInitialValues({autoUpdateKey: true});
    final c = container();

    await runStartupUpdates(
      c,
      check: _Check(null).call,
      format: InstallFormat.rpm,
      currentVersion: '1.0.0',
    );

    expect(c.read(startupPromptProvider), isNull);
  });

  test('a version turned down is not offered again until something newer '
      'exists', () async {
    SharedPreferences.setMockInitialValues({
      autoUpdateKey: true,
      dismissedUpdateVersionKey: '9.9.9',
    });
    final c = container();

    await runStartupUpdates(
      c,
      check: _Check(_update(InstallFormat.tarball)).call,
      format: InstallFormat.tarball,
      currentVersion: '1.0.0',
    );

    expect(c.read(startupPromptProvider), isNull);
  });

  test('the mechanism note names dnf for a package install and not for a '
      'tarball', () {
    expect(autoUpdateSplashNote(InstallFormat.rpm), contains('package'));
    expect(autoUpdateSplashNote(InstallFormat.tarball), contains('tell you'));
  });
}
