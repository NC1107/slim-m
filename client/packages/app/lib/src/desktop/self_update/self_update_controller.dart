// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Drives one self-update from the UI: download and verify, install into the
/// per-user layout, and keep the outcome where the persistent error banner and
/// the title-bar menu read it. Only the Linux tarball layout applies today.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:slimm_platform/platform.dart';

import 'linux_install.dart';
import 'linux_layout.dart';
import 'self_update.dart';
import 'self_update_failure.dart';

/// Fetch step, injectable so tests need no network.
typedef FetchUpdate =
    Future<VerifiedUpdate?> Function({
      required String currentVersion,
      required String platformKey,
      required Directory stagingDir,
      required http.Client client,
    });

/// The layout this process runs from when it may replace itself, else null.
LinuxInstallLayout? selfApplyLayout({
  InstallFormat? format,
  String? resolvedExecutable,
}) {
  if ((format ?? currentInstallFormat()) != InstallFormat.tarball) return null;
  final layout = detectLinuxLayout(
    resolvedExecutable ?? Platform.resolvedExecutable,
  );
  return layout != null && layoutIsWritable(layout) ? layout : null;
}

/// Whether this process may replace itself; overridable in tests.
final selfApplyAvailableProvider = Provider<bool>(
  (ref) => selfApplyLayout() != null,
);

/// The version installed and waiting for a restart, or null.
final stagedUpdateVersionProvider = StateProvider<String?>((ref) => null);

final selfUpdateInstallingProvider = StateProvider<bool>((ref) => false);

/// The last failure, shown by the persistent banner until dismissed.
final selfUpdateFailureProvider = StateProvider<SelfUpdateFailure?>(
  (ref) => null,
);

final selfUpdateProvider = Provider<SelfUpdateController>(
  SelfUpdateController.new,
);

class SelfUpdateController {
  SelfUpdateController(
    this.ref, {
    FetchUpdate fetch = fetchVerifiedUpdate,
    Unpack unpack = unpackWithTar,
    http.Client Function() newClient = http.Client.new,
  }) : _fetch = fetch,
       _unpack = unpack,
       _newClient = newClient;

  final Ref ref;
  final FetchUpdate _fetch;
  final Unpack _unpack;
  final http.Client Function() _newClient;

  /// Installs the newest verified release and returns its version, or null
  /// when there was nothing to install or it failed; a failure is left in
  /// [selfUpdateFailureProvider].
  Future<String?> install({
    required String currentVersion,
    InstallFormat? format,
    String? resolvedExecutable,
  }) async {
    if (ref.read(selfUpdateInstallingProvider)) return null;
    ref.read(selfUpdateInstallingProvider.notifier).state = true;
    ref.read(selfUpdateFailureProvider.notifier).state = null;
    final client = _newClient();
    try {
      final installFormat = format ?? currentInstallFormat();
      final layout = selfApplyLayout(
        format: installFormat,
        resolvedExecutable: resolvedExecutable,
      );
      if (layout == null) {
        throw const SelfUpdateFailure(
          SelfUpdateFailureKind.unsupportedInstall,
          'This install is updated by its package manager, not by slim-m.',
        );
      }
      final update = await _fetch(
        currentVersion: currentVersion,
        platformKey: 'linux-x64',
        stagingDir: layout.stagingDir,
        client: client,
      );
      if (update == null) return null;
      await installLinuxUpdate(
        update: update,
        format: installFormat,
        layout: layout,
        unpack: _unpack,
      );
      ref.read(stagedUpdateVersionProvider.notifier).state = update.version;
      return update.version;
    } on SelfUpdateFailure catch (failure) {
      ref.read(selfUpdateFailureProvider.notifier).state = failure;
      return null;
    } finally {
      client.close();
      ref.read(selfUpdateInstallingProvider.notifier).state = false;
    }
  }

  /// Startup bookkeeping: report a rollback the launcher performed, and after
  /// [settle] of staying up mark this launch clean so old versions are pruned.
  Future<void> confirmStart({
    String? resolvedExecutable,
    Duration settle = const Duration(seconds: 20),
  }) async {
    if (resolvedExecutable == null && !isDesktopHost) return;
    final layout = detectLinuxLayout(
      resolvedExecutable ?? Platform.resolvedExecutable,
    );
    if (layout == null) return;
    final failed = takeRollbackNotice(layout);
    if (failed != null) {
      ref.read(selfUpdateFailureProvider.notifier).state = SelfUpdateFailure(
        SelfUpdateFailureKind.rolledBack,
        'Version $failed did not start, so slim-m went back to the '
        'previous version.',
      );
    }
    await Future<void>.delayed(settle);
    confirmCleanStart(layout);
  }
}
