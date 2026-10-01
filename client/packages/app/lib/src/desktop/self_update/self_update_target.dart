// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What differs between the per-user installs decision 0041 defines: the
/// manifest key, where staging lives, and how a version is switched to. The
/// controller drives one of these and knows neither OS.
library;

import 'dart:io';

import 'package:slimm_platform/platform.dart' show InstallFormat;

import 'linux_install.dart' as linux;
import 'linux_layout.dart';
import 'macos_install.dart' as macos;
import 'macos_layout.dart';
import 'self_update.dart';
import 'update_manifest.dart';
import 'windows_install.dart' as windows;
import 'windows_layout.dart';

abstract interface class SelfUpdateTarget {
  /// The key the signed manifest lists this OS's artifact under.
  String get platformKey;
  Directory get stagingDir;

  /// What a restart runs so it lands on whichever version is current.
  File get launcher;
  bool get isWritable;

  /// [unpack] overrides how the verified artifact is extracted.
  Future<void> install(VerifiedUpdate update, {linux.Unpack? unpack});
  void confirmCleanStart();
  String? takeRollbackNotice();

  /// Counts this start and, where the app is its own launcher, puts the
  /// previous version back when the new one keeps failing. True means it did
  /// and the caller must restart.
  bool rollBackIfStuck();
}

/// The target [resolvedExecutable] runs from on [os], or null when it is not a
/// per-user install the updater created or when no release artifact exists for
/// [arch] (the host's by default), so a wrong-architecture build is never
/// chosen.
SelfUpdateTarget? installTargetFor(
  String resolvedExecutable,
  String os, {
  String? home,
  String? arch,
}) {
  final key = updatePlatformKey(os: os, arch: arch ?? hostArchitecture());
  if (key == null) return null;
  return switch (os) {
    'linux' => switch (detectLinuxLayout(resolvedExecutable)) {
      final layout? => _LinuxTarget(layout, key),
      null => null,
    },
    'windows' => switch (detectWindowsLayout(resolvedExecutable)) {
      final layout? => _WindowsTarget(layout, key),
      null => null,
    },
    'macos' => switch (detectMacosLayout(
      resolvedExecutable,
      home: home ?? Platform.environment['HOME'] ?? '',
    )) {
      final layout? => _MacosTarget(layout, key),
      null => null,
    },
    _ => null,
  };
}

class _LinuxTarget implements SelfUpdateTarget {
  const _LinuxTarget(this.layout, this.platformKey);

  final LinuxInstallLayout layout;

  @override
  final String platformKey;
  @override
  Directory get stagingDir => layout.stagingDir;
  @override
  File get launcher => layout.launcher;
  @override
  bool get isWritable => layoutIsWritable(layout);

  @override
  Future<void> install(VerifiedUpdate update, {linux.Unpack? unpack}) =>
      linux.installLinuxUpdate(
        update: update,
        format: InstallFormat.tarball,
        layout: layout,
        unpack: unpack ?? linux.unpackWithTar,
      );

  @override
  void confirmCleanStart() => linux.confirmCleanStart(layout);

  @override
  String? takeRollbackNotice() => linux.takeRollbackNotice(layout);
  @override
  bool rollBackIfStuck() => false;
}

class _WindowsTarget implements SelfUpdateTarget {
  const _WindowsTarget(this.layout, this.platformKey);

  final WindowsInstallLayout layout;

  @override
  final String platformKey;
  @override
  Directory get stagingDir => layout.stagingDir;
  @override
  File get launcher => layout.launcher;
  @override
  bool get isWritable => layout.isWritable;

  @override
  Future<void> install(VerifiedUpdate update, {linux.Unpack? unpack}) =>
      windows.installWindowsUpdate(
        update: update,
        format: InstallFormat.tarball,
        layout: layout,
        unpack: unpack ?? windows.unpackZip,
      );

  @override
  void confirmCleanStart() => windows.confirmWindowsCleanStart(layout);

  @override
  String? takeRollbackNotice() => windows.takeWindowsRollbackNotice(layout);
  @override
  bool rollBackIfStuck() => false;
}

class _MacosTarget implements SelfUpdateTarget {
  const _MacosTarget(this.layout, this.platformKey);

  final MacosInstallLayout layout;

  @override
  final String platformKey;
  @override
  Directory get stagingDir => layout.stagingDir;
  @override
  File get launcher => layout.launcher;
  @override
  bool get isWritable => layout.isWritable;

  @override
  Future<void> install(VerifiedUpdate update, {linux.Unpack? unpack}) =>
      macos.installMacosUpdate(
        update: update,
        format: InstallFormat.tarball,
        layout: layout,
        unpack: unpack ?? macos.unpackWithDitto,
      );

  @override
  void confirmCleanStart() => macos.confirmMacosCleanStart(layout);

  @override
  String? takeRollbackNotice() => macos.takeMacosRollbackNotice(layout);

  @override
  bool rollBackIfStuck() => macos.rollBackMacosIfStuck(layout);
}
