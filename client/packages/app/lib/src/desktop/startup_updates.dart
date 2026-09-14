// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What the splash does about updates, per the owner's shape in decision
/// 0025: ask once whether this install may update itself, and from then on,
/// when the answer is yes, fetch and install a newer version during the mini
/// splash before the app starts.
///
/// The question is only asked here for an install that already has an
/// account: a new one is asked during signup (`updates_choice_screen.dart`),
/// which an install with a session never passes through again. Both write
/// the same preference, and neither asks twice.
///
/// Nothing here may fail startup. Every step is timeout-bounded or
/// best-effort, and any error falls through to launching the client that is
/// already installed.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:slimm_platform/platform.dart';
import 'package:url_launcher/url_launcher.dart';

import '../diagnostics/debug_log.dart';
import '../providers/auto_update_preference.dart';
import '../providers/providers.dart';
import 'rpm_updater.dart';
import 'startup_screen.dart';
import 'startup_state.dart';
import 'update_check.dart';

/// Replaces the running process with a fresh one, so an installed update is
/// the build actually in memory. Injectable; the real one detaches a new
/// process from this one before it exits, or the exit would take the child
/// with it.
typedef Relaunch = Future<void> Function();

Future<void> _realRelaunch() async {
  await Process.start(
    Platform.resolvedExecutable,
    Platform.executableArguments,
    mode: ProcessStartMode.detached,
  );
  exit(0);
}

/// The splash's whole update pass. [container] carries the providers the
/// splash renders from; every other parameter is a seam for tests.
Future<void> runStartupUpdates(
  ProviderContainer container, {
  CheckForClientUpdate check = checkForClientUpdate,
  RpmUpdater rpm = const RpmUpdater(),
  Relaunch relaunch = _realRelaunch,
  InstallFormat? format,
  String? currentVersion,
}) async {
  if (!isDesktopHost || updateChecksDisabled()) return;
  try {
    final prefs = await container.read(preferencesProvider.future);
    var enabled = loadAutoUpdatePreference(prefs);
    if (enabled == null) {
      if (!container.read(sessionProvider).isSignedIn) return;
      enabled = await _askToEnable(container, format ?? currentInstallFormat());
      await prefs.setBool(autoUpdateKey, enabled);
    }
    if (!enabled) return;

    container.read(startupStatusProvider.notifier).state =
        'Checking for updates';
    final version =
        currentVersion ?? (await PackageInfo.fromPlatform()).version;
    final update = await check(currentVersion: version, format: format);
    if (update == null) return;

    if (update.format == InstallFormat.rpm) {
      await _installWithDnf(container, update, rpm, relaunch);
      return;
    }
    await _offerManually(container, update);
  } catch (error) {
    container
        .read(debugLogProvider.notifier)
        .record('update', 'startup update pass failed: $error');
  } finally {
    container.read(startupPromptProvider.notifier).state = null;
  }
}

/// The one-time question. Answering is the only way past it, which is the
/// point: it is asked once per install and never again.
Future<bool> _askToEnable(
  ProviderContainer container,
  InstallFormat format,
) async {
  final answer = Completer<bool>();
  container.read(startupPromptProvider.notifier).state = StartupPrompt(
    title: 'Keep slim-m up to date automatically?',
    detail: autoUpdateSplashNote(format),
    primaryLabel: 'Turn on',
    onPrimary: () => answer.complete(true),
    secondaryLabel: 'Not now',
    onSecondary: () => answer.complete(false),
  );
  final enabled = await answer.future;
  container.read(startupPromptProvider.notifier).state = null;
  return enabled;
}

/// The rpm path: dnf does the install behind the system's own polkit prompt,
/// and the new files only become the running build after a relaunch, so that
/// is offered rather than assumed - someone who opened slim-m to answer a
/// message can take the update on the next launch instead.
Future<void> _installWithDnf(
  ProviderContainer container,
  ClientUpdate update,
  RpmUpdater rpm,
  Relaunch relaunch,
) async {
  container.read(startupStatusProvider.notifier).state =
      'Installing ${update.version}';
  final result = await rpm.apply();
  if (!result.ok) {
    container
        .read(debugLogProvider.notifier)
        .record('update', 'dnf could not install: ${result.detail}');
    await _offerManually(container, update);
    return;
  }

  final now = Completer<bool>();
  container.read(startupPromptProvider.notifier).state = StartupPrompt(
    title: 'Updated to ${update.version}',
    detail: 'Restart slim-m to start using it.',
    primaryLabel: 'Restart now',
    onPrimary: () => now.complete(true),
    secondaryLabel: 'Later',
    onSecondary: () => now.complete(false),
  );
  final restart = await now.future;
  container.read(startupPromptProvider.notifier).state = null;
  if (restart) await relaunch();
}

/// Every format dnf does not cover, and every dnf run that failed: say the
/// version is there and open the release, which is what decision 0020's
/// notifier already did. A version turned down here is not offered again
/// until something newer exists.
Future<void> _offerManually(
  ProviderContainer container,
  ClientUpdate update,
) async {
  final prefs = await container.read(preferencesProvider.future);
  if (updateWasDismissed(
    dismissed: prefs.getString(dismissedUpdateVersionKey),
    candidate: update.version,
  )) {
    return;
  }

  final answer = Completer<bool>();
  container.read(startupPromptProvider.notifier).state = StartupPrompt(
    title: 'Version ${update.version} is available',
    detail: updateActionHint(update.format),
    primaryLabel: 'Get update',
    onPrimary: () => answer.complete(true),
    secondaryLabel: 'Not now',
    onSecondary: () => answer.complete(false),
  );
  final accepted = await answer.future;
  container.read(startupPromptProvider.notifier).state = null;
  if (!accepted) {
    await prefs.setString(dismissedUpdateVersionKey, update.version);
    return;
  }
  final uri = Uri.tryParse(update.releaseUrl);
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// The mechanism line under the splash question, shorter than the join
/// flow's because the splash has no room for a paragraph.
String autoUpdateSplashNote(InstallFormat format) => switch (format) {
  InstallFormat.rpm || InstallFormat.deb =>
    'Installs with your package manager on each launch. Your system asks '
        'for your password when there is one to install.',
  InstallFormat.flatpak =>
    'slim-m will tell you when a new version is ready and how to get it.',
  InstallFormat.appImage || InstallFormat.tarball || InstallFormat.unknown =>
    'slim-m will tell you when a new version is ready and open it for you.',
};
