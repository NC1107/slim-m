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
import 'rollback_record.dart';
import 'self_update.dart';
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

  /// The highest version ever rolled back from, which must never be offered
  /// again; unlike the notice, reading it consumes nothing.
  String? failedVersion();

  /// Counts this start and, where the app is its own launcher, puts the
  /// previous version back when the new one keeps failing. True means it did
  /// and the caller must restart.
  bool rollBackIfStuck();
}

/// The target [resolvedExecutable] runs from on [os], or null when it is not a
/// per-user install the updater created.
SelfUpdateTarget? installTargetFor(
  String resolvedExecutable,
  String os, {
  String? home,
}) => switch (os) {
  'linux' => switch (detectLinuxLayout(resolvedExecutable)) {
    final layout? => _LinuxTarget(layout),
    null => null,
  },
  'windows' => switch (detectWindowsLayout(resolvedExecutable)) {
    final layout? => _WindowsTarget(layout),
    null => null,
  },
  'macos' => switch (detectMacosLayout(
    resolvedExecutable,
    home: home ?? Platform.environment['HOME'] ?? '',
  )) {
    final layout? => _MacosTarget(layout),
    null => null,
  },
  _ => null,
};

class _LinuxTarget implements SelfUpdateTarget {
  const _LinuxTarget(this.layout);

  final LinuxInstallLayout layout;

  @override
  String get platformKey => 'linux-x64';
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
  String? failedVersion() => failedVersionFloor(
    rolledBack: File(layout.path(LayoutNames.rolledBack)),
    record: File(layout.path(LayoutNames.failedVersion)),
  );
  @override
  bool rollBackIfStuck() => false;
}

class _WindowsTarget implements SelfUpdateTarget {
  const _WindowsTarget(this.layout);

  final WindowsInstallLayout layout;

  @override
  String get platformKey => 'windows-x64';
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
  String? failedVersion() => failedVersionFloor(
    rolledBack: File(layout.path(LayoutNames.rolledBack)),
    record: File(layout.path(LayoutNames.failedVersion)),
  );
  @override
  bool rollBackIfStuck() => false;
}

class _MacosTarget implements SelfUpdateTarget {
  const _MacosTarget(this.layout);

  final MacosInstallLayout layout;

  @override
  String get platformKey => 'macos';
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
  String? failedVersion() => failedVersionFloor(
    rolledBack: File(layout.path(MacosNames.rolledBack)),
    record: File(layout.path(MacosNames.failedVersion)),
  );

  @override
  bool rollBackIfStuck() => macos.rollBackMacosIfStuck(layout);
}
