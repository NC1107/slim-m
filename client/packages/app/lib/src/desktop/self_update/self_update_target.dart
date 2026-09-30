// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What differs between the per-user installs decision 0041 defines: the
/// manifest key, where staging lives, and how a version is switched to. The
/// controller drives one of these and knows neither OS.
library;

import 'dart:io';

import 'package:slimm_platform/platform.dart' show InstallFormat;

import 'linux_install.dart' as linux;
import 'linux_layout.dart';
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
}

/// The target [resolvedExecutable] runs from on [os], or null when it is not a
/// per-user install the updater created.
SelfUpdateTarget? installTargetFor(String resolvedExecutable, String os) =>
    switch (os) {
      'linux' => switch (detectLinuxLayout(resolvedExecutable)) {
        final layout? => _LinuxTarget(layout),
        null => null,
      },
      'windows' => switch (detectWindowsLayout(resolvedExecutable)) {
        final layout? => _WindowsTarget(layout),
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
}
